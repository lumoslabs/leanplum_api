module LeanplumApi
  class API
    EXPORT_PENDING = 'PENDING'
    EXPORT_RUNNING = 'RUNNING'
    EXPORT_FINISHED = 'FINISHED'

    def initialize(options = {})
      fail 'LeanplumApi not configured yet!' unless LeanplumApi.configuration

      @logger = options[:logger] || LeanplumApiLogger.new(File.join(LeanplumApi.configuration.log_path, "#{$$}_leanplum_#{Time.now.utc.strftime('%Y-%m-%d_%H:%M:%S')}.log"))
      @http = LeanplumApi::HTTP.new(logger: @logger)
    end

    def set_user_attributes(user_attributes, options = {})
      track_multi(nil, user_attributes, options)
    end

    def track_events(events, options = {})
      track_multi(events, nil, options)
    end

    # This method is for tracking events and/or updating user attributes at the same time, batched together like leanplum
    # recommends.
    # Set the :force_anomalous_override to catch warnings from leanplum about anomalous events and force them to not
    # be considered anomalous
    def track_multi(events = nil, user_attributes = nil, options = {})
      events = arrayify(events)
      user_attributes = arrayify(user_attributes)

      request_data = user_attributes.map { |h| build_user_attributes_hash(h) } + events.map { |h| build_event_attributes_hash(h) }
      response = @http.post(request_data)
      validate_response(events + user_attributes, response)

      if options[:force_anomalous_override]
        user_ids_to_reset = []
        response.body['response'].each_with_index do |indicator, i|
          if indicator['warning'] && indicator['warning']['message'] =~ /Anomaly detected/i
            user_ids_to_reset << (events + user_attributes)[i][:user_id]
          end
        end
        reset_anomalous_users(user_ids_to_reset)
      end
    end

    # Returns the jobId
    # Leanplum has confirmed that using startTime and endTime, especially trying to be relatively up to the minute,
    # leads to sort of unprocessed information that can be incomplete.
    # They recommend using the automatic export to S3 if possible.
    def export_data(start_time, end_time = nil)
      fail "Start time #{start_time} after end time #{end_time}" if end_time && start_time > end_time
      @logger.info("Requesting data export from #{start_time} to #{end_time}...")

      # Because of open questions about how startTime and endTime work (or don't work, as the case may be), we
      # only want to pass the dates unless start and end times are specifically requested.
      params = { action: 'exportData', startDate: start_time.strftime('%Y%m%d') }
      params[:startTime] = start_time.strftime('%s') if start_time.is_a?(DateTime) || start_time.is_a?(Time)
      if end_time
        params[:endDate] = end_time.strftime('%Y%m%d')
        params[:endTime] = end_time.strftime('%s') if end_time.is_a?(DateTime) || end_time.is_a?(Time)
      end

      # Handle optional S3 export params
      if LeanplumApi.configuration.s3_bucket_name
        fail 's3_bucket_name set but s3_access_id not configured!' unless LeanplumApi.configuration.s3_access_id
        fail 's3_bucket_name set but s3_access_key not configured!' unless LeanplumApi.configuration.s3_access_key

        params.merge!(
          s3BucketName: LeanplumApi.configuration.s3_bucket_name,
          s3AccessId: LeanplumApi.configuration.s3_access_id,
          s3AccessKey: LeanplumApi.configuration.s3_access_key
        )
        params.merge!(s3ObjectPrefix: LeanplumApi.configuration.s3_object_prefix) if LeanplumApi.configuration.s3_object_prefix
      end

      body = data_export_connection.get(params).body
      fail "No :response key in response body!" unless body['response']
      response = body['response'].first
      fail "No success message! Response: #{response}" unless response['success'] == true

      response['jobId']
    end

    # See leanplum docs.
    # The segment syntax is identical to that produced by the "Insert Value" feature on the dashboard.
    # Examples: 'Country = "US"', '{Country = “US”} and {App version = 1}'.
    def export_users(segment, ab_test_id)
      data_export_connection.get(action: 'exportUsers', segment: segment, ab_test_id: ab_test_id)
    end

    def get_export_results(job_id)
      response = data_export_connection.get(action: 'getExportResults', jobId: job_id).body['response'].first
      if response['state'] == EXPORT_FINISHED
        @logger.info("Export finished.")
        @logger.debug("  Response: #{response}")
        {
          files: response['files'],
          number_of_sessions: response['numSessions'],
          number_of_bytes: response['numBytes'],
          state: response['state'],
          s3_copy_status: response['s3CopyStatus']
        }
      else
        { state: response['state'] }
      end
    end

    def wait_for_job(job_id, polling_interval = 60)
      while get_export_results(job_id)[:state] != EXPORT_FINISHED
        @logger.debug("Polling job #{job_id}: #{get_export_results(job_id)}")
        sleep(polling_interval)
      end
      get_export_results(job_id)
    end

    def export_user(user_id)
      data_export_connection.get(action: 'exportUser', userId: user_id).body['response'].first['userAttributes']
    end

    def get_ab_tests(only_recent = false)
      content_read_only_connection.get(action: 'getAbTests', recent: only_recent).body['response'].first['abTests']
    end

    def get_ab_test(ab_test_id)
      content_read_only_connection.get(action: 'getAbTest', id: ab_test_id).body['response'].first['abTest']
    end

    def get_variant(variant_id)
      content_read_only_connection.get(action: 'getVariant', id: variant_id).body['response'].first['variant']
    end

    def get_messages(only_recent = false)
      content_read_only_connection.get(action: 'getMessages', recent: only_recent).body['response'].first['messages']
    end

    def get_message(message_id)
      content_read_only_connection.get(action: 'getMessage', id: message_id).body['response'].first['message']
    end

    def get_vars(user_id)
      @http.get(action: 'getVars', userId: user_id).body['response'].first['vars']
    end

    # If you pass old events OR users with old date attributes (i.e. create_date for an old users), leanplum will mark them 'anomalous'
    # and exclude them from your data set.
    # Calling this method after you pass old events will fix that for all events for the specified user_id
    # For some reason this API feature requires the developer key
    def reset_anomalous_users(user_ids)
      user_ids = arrayify(user_ids)
      request_data = user_ids.map { |user_id| { 'action' => 'setUserAttributes', 'resetAnomalies' => true, 'userId' => user_id } }
      response = development_connection.post(request_data)
      validate_response(request_data, response)
    end

    private

    # Only instantiated for data export endpoint calls
    def data_export_connection
      @data_export ||= LeanplumApi::DataExport.new(logger: @logger)
    end

    # Only instantiated for ContentReadOnly calls (AB tests)
    def content_read_only_connection
      @content_read_only ||= LeanplumApi::ContentReadOnly.new(logger: @logger)
    end

    def development_connection
      @development ||= LeanplumApi::Development.new(logger: @logger)
    end

    def extract_user_id_or_device_id_hash(hash)
      user_id = hash['user_id'] || hash[:user_id]
      device_id = hash['device_id'] || hash[:device_id]
      fail "No device_id or user_id in hash #{hash}" unless user_id || device_id

      user_id ? { 'userId' => user_id } : { 'deviceId' => device_id }
    end

    # Action can be any command that takes a userAttributes param.  "start" (a session) is the other command that most
    # obviously takes userAttributes.
    def build_user_attributes_hash(user_hash, action = 'setUserAttributes')
      extract_user_id_or_device_id_hash(user_hash).merge(
        'action' => action,
        'userAttributes' => turn_date_and_time_values_to_strings(user_hash).reject { |k,v| k.to_s =~ /^(user_id|device_id)$/ }
      )
    end

    # Events have a :user_id or :device id, a name (:event) and an optional time (:time)
    def build_event_attributes_hash(event_hash)
      fail "No event name provided in #{event_hash}" unless event_hash[:event] || event_hash['event']

      time = event_hash[:time] || event_hash['time']
      time_hash = time ? { 'time' => time.strftime('%s') } : {}

      event = extract_user_id_or_device_id_hash(event_hash).merge(time_hash).merge(
        'action' => 'track',
        'event' => event_hash[:event] || event_hash['event']
      )
      event_params = event_hash.reject { |k,v| k.to_s =~ /^(user_id|device_id|event|time)$/ }
      if event_params.keys.size > 0
        event.merge('params' => event_params )
      else
        event
      end
    end

    # Leanplum does not support dates and times as of 2015-08-11
    def turn_date_and_time_values_to_strings(hash)
      new_hash = {}
      hash.each do |k,v|
        if v.is_a?(Time) || v.is_a?(DateTime)
          new_hash[k] = v.strftime('%Y-%m-%d %H:%M:%S')
        elsif v.is_a?(Date)
          new_hash[k] = v.strftime('%Y-%m-%d')
        else
          new_hash[k] = v
        end
      end
      new_hash
    end

    # In case leanplum decides your events are too old, they will send a warning.
    # Right now we aren't responding to this directly.
    # '{"response":[{"success":true,"warning":{"message":"Anomaly detected: time skew. User will be excluded from analytics."}}]}'
    def validate_response(input, response)
      success_indicators = response.body['response']
      if success_indicators.size != input.size
        fail "Attempted to update #{input.size} records but only received confirmation for #{success_indicators.size}!"
      end

      failure_indices = []
      success_indicators.each_with_index do |s,i|
        if s['success'].to_s != 'true'
          @logger.error("Unsuccessful attempt to update at position #{i}: #{input[i]}")
          failure_indices << i
        else
          @logger.debug("Successfully updated position #{i}: #{input[i]}")
        end
      end

      fail LeanplumValidationException.new('Failed to update') if failure_indices.size > 0
    end

    def arrayify(x)
      if x && !x.is_a?(Array)
        [x]
      else
        x || []
      end
    end
  end
end
