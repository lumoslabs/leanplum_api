module LeanplumApi
  class Connection
    LEANPLUM_API_PATH = '/api'

    def initialize(client_key, options = {})
      @client_key = client_key
      @logger = options[:logger] || Logger.new(STDERR)
    end

    def get(query)
      connection.get(LEANPLUM_API_PATH, query.merge(authentication_params))
    end

    def multi(payload)
      connection.post("#{LEANPLUM_API_PATH}?#{authed_multi_param_string}") do |request|
        request.body = { data: payload }
      end
    end

    private

    def authentication_params
      {
        appId: LeanplumApi.configuration.app_id,
        clientKey: @client_key,
        apiVersion: LeanplumApi.configuration.api_version,
        devMode: LeanplumApi.configuration.developer_mode
      }
    end

    def connection
      fail 'APP_ID not configured!' unless LeanplumApi.configuration.app_id

      options = {
        url: 'https://www.leanplum.com',
        request: {
          timeout: LeanplumApi.configuration.timeout_seconds,
          open_timeout: LeanplumApi.configuration.timeout_seconds
        }
      }

      @connection ||= Faraday.new(options) do |connection|
        connection.request :leanplum_response_validation
        connection.request :json

        connection.response :logger, @logger, bodies: true if LeanplumApi.configuration.api_debug
        connection.response :json, :content_type => /\bjson$/

        connection.adapter Faraday.default_adapter
      end
    end

    def authed_multi_param_string
      params = authentication_params.merge(action: 'multi', time: Time.now.utc.strftime('%s'))
      params.merge!(devMode: true) if LeanplumApi.configuration.developer_mode
      URI.encode_www_form(params)
    end
  end
end
