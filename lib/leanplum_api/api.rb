module LeanplumApi
  class API
    EXPORT_PENDING = 'PENDING'.freeze
    EXPORT_RUNNING = 'RUNNING'.freeze
    EXPORT_FINISHED = 'FINISHED'.freeze
    extend Gem::Deprecate

    class LeanplumValidationException < RuntimeError; end

    def initialize(options = {})
      fail 'LeanplumApi not configured yet!' unless LeanplumApi.configuration
    end

    def set_user_attributes(user_attributes, options = {})
      track_multi(user_attributes: user_attributes, options: options)
    end

    def set_device_attributes(device_attributes, options = {})
      track_multi(device_attributes: device_attributes, options: options)
    end

    def track_events(events, options = {})
      track_multi(events: events, options: options)
    end

    # This method is for tracking events and/or updating user attributes at the same time,
    # batched together like leanplum recommends.
    # Set the :force_anomalous_override to catch warnings from leanplum about anomalous events
    # and force them to not be considered anomalous.
    def track_multi(events: nil, user_attributes: nil, device_attributes: nil, options: {})
      events = Array.wrap(events)

      request_data = []
      if user_attributes.present?
        user_attributes = Array.wrap(user_attributes)
        user_request_data = user_attributes.map { |h| build_user_attributes_hash(h) }
        request_data.concat(user_request_data)
      end

      if device_attributes.present?
        device_attributes = Array.wrap(device_attributes)
        request_data.concat(device_attributes.map { |h| build_device_attributes_hash(h) })
      end

      request_data += events.map { |h| build_event_attributes_hash(h, options) }
      response = production_connection.multi(request_data).body['response']

      force_anomalous_override(response, events) if options[:force_anomalous_override]

      response
    end

    # Returns the jobId
    # Leanplum has confirmed that using startTime and endTime, especially trying to be relatively up to the minute,
    # leads to sort of unprocessed information that can be incomplete.
    # They recommend using the automatic export to S3 if possible.
    def export_data(start_time, end_time = nil)
      fail "Start time #{start_time} after end time #{end_time}" if end_time && start_time > end_time
      LeanplumApi.configuration.logger.info("Requesting data export from #{start_time} to #{end_time}...")

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

      data_export_connection.get(params).body['response'].first['jobId']
    end

    # See leanplum docs.
    # The segment syntax is identical to that produced by the "Insert Value" feature on the dashboard.
    # Examples: 'Country = "US"', '{Country = "US"} and {App version = 1}'.
    def export_users(segment, ab_test_id)
      data_export_connection.get(action: 'exportUsers', segment: segment, ab_test_id: ab_test_id)
    end

    def get_export_results(job_id)
      response = data_export_connection.get(action: 'getExportResults', jobId: job_id).body['response'].first

      if response['state'] == EXPORT_FINISHED
        LeanplumApi.configuration.logger.info("Export finished.")
        LeanplumApi.configuration.logger.debug("  Response: #{response}")
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

    def wait_for_export_job(job_id, polling_interval = 60)
      while get_export_results(job_id)[:state] != EXPORT_FINISHED
        LeanplumApi.configuration.logger.debug("Polling job #{job_id}: #{get_export_results(job_id)}")
        sleep(polling_interval)
      end
      get_export_results(job_id)
    end

    # Remove in version 4.x
    def wait_for_job(job_id, polling_interval = 60)
      wait_for_export_job(job_id, polling_interval)
    end
    deprecate :wait_for_job, 'wait_for_export_job', 2018, 6

    def user_attributes(user_id)
      export_user(user_id)['userAttributes'].inject({}) do |attrs, (k, v)|
        # Leanplum doesn't use true JSON for booleans...
        if v == 'True'
          attrs[k] = true
        elsif v == 'False'
          attrs[k] = false
        else
          attrs[k] = v
        end

        attrs
      end
    end

    def user_events(user_id)
      export_user(user_id)['events']
    end

    def export_user(user_id)
      data_export_connection.get(action: 'exportUser', userId: user_id).body['response'].first
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
      production_connection.get(action: 'getVars', userId: user_id).body['response'].first['vars']
    end

    # Leanplum's engineering team likes to break their API and or change stuff without warning (often)
    # and has no idea what "versioning" actually means, so we just reset
    # everyone all the time. This condition should be:
    # if indicator['warning'] && indicator['warning']['message'] =~ /Past event detected/i
    def force_anomalous_override(response, events)
      user_ids_to_reset = []

      response.each_with_index do |indicator, i|
        # Leanplum's engineering team likes to break their API and or change stuff without warning (often)
        # and has no idea what "versioning" actually means, so we just reset
        # everyone all the time. This condition should be:
        # if indicator['warning'] && indicator['warning']['message'] =~ /Past event detected/i
        #
        # but it has to be:
        if indicator['warning']
          # Leanplum does not return their warnings in order!!!  So we just have
          # to reset everyone who had any events.  This is what the code should be:
          # user_ids_to_reset << request_data[i]['userId']

          # This is what it has to be:
          user_ids_to_reset = events.map { |e| e[:user_id] }.uniq
        end
      end

      unless user_ids_to_reset.empty?
        LeanplumApi.configuration.logger.debug("Resetting anomalous user ids: #{user_ids_to_reset}")
        reset_anomalous_users(user_ids_to_reset)
      end
    end
    
    # If you pass old events OR users with old date attributes (i.e. create_date for an old users), leanplum will mark
    # them 'anomalous' and exclude them from your data set.
    # Calling this method after you pass old events will fix that for all events for the specified user_id
    # For some reason this API feature requires the developer key
    def reset_anomalous_users(user_ids)
      user_ids = Array.wrap(user_ids)
      request_data = user_ids.map { |user_id| { action: 'setUserAttributes', resetAnomalies: true, userId: user_id } }
      development_connection.multi(request_data)
    end

    private

    def production_connection
      fail "production_key not configured!" unless LeanplumApi.configuration.production_key
      @production ||= Connection.new(LeanplumApi.configuration.production_key)
    end

    # Only instantiated for data export endpoint calls
    def data_export_connection
      fail "data_export_key not configured!" unless LeanplumApi.configuration.data_export_key
      @data_export ||= Connection.new(LeanplumApi.configuration.data_export_key)
    end

    # Only instantiated for ContentReadOnly calls (AB tests)
    def content_read_only_connection
      fail "content_read_only_key not configured!" unless LeanplumApi.configuration.content_read_only_key
      @content_read_only ||= Connection.new(LeanplumApi.configuration.content_read_only_key)
    end

    def development_connection
      fail "development_key not configured!" unless LeanplumApi.configuration.development_key
      @development ||= Connection.new(LeanplumApi.configuration.development_key)
    end

    # Deletes the user_id and device_id key/value pairs from the hash parameter.
    def extract_user_id_or_device_id_hash!(hash)
      user_id = hash.delete(:user_id)
      device_id = hash.delete(:device_id)
      fail "No device_id or user_id in hash #{hash}" unless user_id || device_id

      user_id ? { userId: user_id } : { deviceId: device_id }
    end

    def fix_iso8601(attr_hash)
      attr_hash = HashWithIndifferentAccess.new(attr_hash)
      attr_hash.each { |k, v| attr_hash[k] = v.iso8601 if v.is_a?(Date) || v.is_a?(Time) || v.is_a?(DateTime) }
      attr_hash
    end
    
    # Action can be any command that takes a userAttributes param.  "start" (a session) is the other command that most
    # obviously takes userAttributes.
    # As of 2015-10 Leanplum supports ISO8601 date & time strings as user attributes.
    def build_user_attributes_hash(user_hash)
      user_hash = fix_iso8601(user_hash)
      extract_user_id_or_device_id_hash!(user_hash).merge(action: 'setUserAttributes', userAttributes: user_hash)
    end

    def build_device_attributes_hash(device_hash)
      device_hash = fix_iso8601(device_hash)
      extract_user_id_or_device_id_hash!(device_hash).merge(action: 'setDeviceAttributes', deviceAttributes: device_hash)
    end

    # Events have a :user_id or :device id, a name (:event) and an optional time (:time)
    # Use the :allow_offline option to send events without creating a new session
    def build_event_attributes_hash(event_hash, options = {})
      event_hash = HashWithIndifferentAccess.new(event_hash)
      event_name = event_hash.delete(:event)
      fail ":event key not present in #{event_hash}" unless event_name

      event = { action: 'track', event: event_name }.merge(extract_user_id_or_device_id_hash!(event_hash))
      event.merge!(time: event_hash.delete(:time).strftime('%s')) if event_hash[:time]
      event.merge!(info: event_hash.delete(:info)) if event_hash[:info]
      event.merge!(allowOffline: true) if options[:allow_offline]

      event_hash.keys.size > 0 ? event.merge(params: event_hash.symbolize_keys ) : event
    end
  end
end
