module LeanplumApi
  class API
    # API Command Constants
    SET_USER_ATTRIBUTES = 'setUserAttributes'.freeze
    SET_DEVICE_ATTRIBUTES = 'setDeviceAttributes'.freeze
    TRACK = 'track'.freeze

    # Data export related constants
    EXPORT_PENDING = 'PENDING'.freeze
    EXPORT_RUNNING = 'RUNNING'.freeze
    EXPORT_FINISHED = 'FINISHED'.freeze

    def initialize
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

    # This method is for tracking events and/or updating user and/or device attributes
    # at the same time, batched together like leanplum recommends.
    # Set the :force_anomalous_override option to catch warnings from leanplum
    # about anomalous events and force them to not be considered anomalous.
    def track_multi(events: nil, user_attributes: nil, device_attributes: nil, options: {})
      events = Array.wrap(events)

      request_data = events.map { |h| build_event_attributes_hash(h.dup, options) } +
                     Array.wrap(user_attributes).map { |h| build_user_attributes_hash(h.dup) } +
                     Array.wrap(device_attributes).map { |h| build_device_attributes_hash(h.dup) }

      response = production_connection.multi(request_data)
      force_anomalous_override(response, events) if options[:force_anomalous_override]

      response
    end

    def user_attributes(user_id)
      # Leanplum returns strings instead of booleans
      export_user(user_id)['userAttributes']
        .map { |k, v| [k, v.to_s =~ /\A(true|false)\z/i ? eval(v.downcase) : v] }
        .to_h
    end

    def user_events(user_id)
      export_user(user_id)['events']
    end

    def export_user(user_id)
      response = data_export_connection.get(action: 'exportUser', userId: user_id).first
      fail ResourceNotFoundError, "User #{user_id} not found" unless response['events'] || response['userAttributes']
      response
    end

    def get_ab_tests(only_recent = false)
      content_read_only_connection.get(action: 'getAbTests', recent: only_recent).first['abTests']
    end

    def get_ab_test(ab_test_id)
      content_read_only_connection.get(action: 'getAbTest', id: ab_test_id).first['abTest']
    end

    def get_variant(variant_id)
      content_read_only_connection.get(action: 'getVariant', id: variant_id).first['variant']
    end

    def get_messages(only_recent = false)
      content_read_only_connection.get(action: 'getMessages', recent: only_recent).first['messages']
    end

    def get_message(message_id)
      content_read_only_connection.get(action: 'getMessage', id: message_id).first['message']
    end

    def get_vars(user_id)
      production_connection.get(action: 'getVars', userId: user_id).first['vars']
    end

    def delete_user(user_id)
      development_connection.get(action: 'deleteUser', userId: user_id).first['vars']
    end

    # If you pass old events OR users with old date attributes (e.g. create_date for an old user), Leanplum
    # wil mark them 'anomalous' and exclude them from your data set.
    # Calling this method after you pass old events will fix that for all events for the specified user_id.
    def reset_anomalous_users(user_ids)
      user_ids = Array.wrap(user_ids)
      request_data = user_ids.map { |user_id| { action: SET_USER_ATTRIBUTES, resetAnomalies: true, userId: user_id } }
      development_connection.multi(request_data)
    end

    def import_csv(bucket, file_path, user_attributes = true)
      request_data = {
        createJob: true,
        defaultAction: user_attributes ? SET_USER_ATTRIBUTES : SET_DEVICE_ATTRIBUTES,
        gcsBucket: bucket,
        file: file_path
      }
      development_connection.multi_dev(request_data)
    end

    private

    def production_connection
      fail 'production_key not configured!' unless LeanplumApi.configuration.production_key
      @production ||= Connection.new(LeanplumApi.configuration.production_key)
    end

    # Only instantiated for data export endpoint calls
    def data_export_connection
      fail 'data_export_key not configured!' unless LeanplumApi.configuration.data_export_key
      @data_export ||= Connection.new(LeanplumApi.configuration.data_export_key)
    end

    # Only instantiated for ContentReadOnly calls (AB tests)
    def content_read_only_connection
      fail 'content_read_only_key not configured!' unless LeanplumApi.configuration.content_read_only_key
      @content_read_only ||= Connection.new(LeanplumApi.configuration.content_read_only_key)
    end

    def development_connection
      fail 'development_key not configured!' unless LeanplumApi.configuration.development_key
      @development ||= Connection.new(LeanplumApi.configuration.development_key)
    end

    # Deletes the user_id and device_id key/value pairs from the hash parameter.
    def extract_user_id_or_device_id_hash!(hash)
      user_id = hash.delete(:user_id) || hash.delete(:userId)
      device_id = hash.delete(:device_id) || hash.delete(:deviceId)
      fail "No device_id or user_id in hash #{hash}" unless user_id || device_id

      user_id ? { userId: user_id } : { deviceId: device_id }
    end

    # build a user attributes hash
    # @param [Hash] user_hash user attributes to set into LP user
    def build_user_attributes_hash(user_hash)
      user_attr_hash = extract_user_id_or_device_id_hash!(user_hash)
      user_attr_hash[:action] = SET_USER_ATTRIBUTES
      user_attr_hash[:devices] = user_hash.delete(:devices) if user_hash.key?(:devices)

      if user_hash.key?(:events)
        user_attr_hash[:events] = user_hash.delete(:events)
        user_attr_hash[:events].each { |k, v| user_attr_hash[:events][k] = fix_seconds_since_epoch(v) }
      end

      user_attr_hash[:userAttributes] = fix_iso8601(user_hash)
      user_attr_hash
    end

    # build a user attributes hash
    # @param [Hash] device_hash device attributes to set into LP device
    def build_device_attributes_hash(device_hash)
      device_hash = fix_iso8601(device_hash)
      extract_user_id_or_device_id_hash!(device_hash).merge(
        action: SET_DEVICE_ATTRIBUTES,
        deviceAttributes: device_hash
      )
    end

    # Events have a :user_id or :device id, a name (:event) and an optional time (:time)
    # Use the :allow_offline option to send events without creating a new session
    def build_event_attributes_hash(event_hash, options = {})
      event_name = event_hash.delete(:event)
      fail ":event key not present in #{event_hash}" unless event_name

      event = { action: TRACK, event: event_name }.merge(extract_user_id_or_device_id_hash!(event_hash))
      event.merge!(time: event_hash.delete(:time).strftime('%s').to_i) if event_hash[:time]
      event.merge!(info: event_hash.delete(:info)) if event_hash[:info]
      event.merge!(currencyCode: event_hash.delete(:currency_code)) if event_hash[:currency_code]
      event.merge!(value: event_hash.delete(:value).to_f) if event_hash[:value]
      event.merge!(allowOffline: true) if options[:allow_offline]

      event_hash.keys.size > 0 ? event.merge(params: event_hash.symbolize_keys ) : event
    end

    # Leanplum's engineering team likes to break their API and or change stuff without warning (often)
    # and has no idea what "versioning" actually means, so we just reset everyone on any type of warning.
    def force_anomalous_override(responses, events)
      user_ids_to_reset = []

      responses.each_with_index do |indicator, i|
        # This condition should be:
        # if indicator['warning'] && indicator['warning']['message'] =~ /Past event detected/i
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

    # As of 2015-10 Leanplum supports ISO8601 date & time strings as user attributes.
    def fix_iso8601(attr_hash)
      Hash[attr_hash.map { |k, v| [k, (is_date_or_time?(v) ? v.iso8601 : v)] }]
    end

    def fix_seconds_since_epoch(attr_hash)
      Hash[attr_hash.map { |k, v| [k, (is_date_or_time?(v) ? v.strftime('%s').to_i : v)] }]
    end

    def is_date_or_time?(obj)
      obj.is_a?(Date) || obj.is_a?(Time) || obj.is_a?(DateTime)
    end
  end
end
