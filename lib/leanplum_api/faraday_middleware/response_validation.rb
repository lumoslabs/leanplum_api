module LeanplumApi
  class BadResponseError < RuntimeError; end
  class ResourceNotFoundError < RuntimeError; end

  class ResponseValidation < Faraday::Middleware
    Faraday::Request.register_middleware(leanplum_response_validation: self)

    SUCCESS = 'success'.freeze
    WARN = 'warning'.freeze

    def call(environment)
      if environment.body
        requests = environment.body[:data] if environment.body[:data] && environment.body[:data].is_a?(Array)
        environment.body = environment.body.to_json
      end

      @app.call(environment).on_complete do |response|
        fail ResourceNotFoundError, response.inspect if response.status == 404
        fail BadResponseError, response.inspect unless response.status == 200 && (responses = response.body['response']).is_a?(Array)
        fail BadResponseError, "No :success key in #{responses.inspect}!" unless responses.all? { |r| r.key?(SUCCESS) }

        validate_request_success(responses, requests) if LeanplumApi.configuration.validate_response
      end
    end

    private

    def validate_request_success(success_indicators, requests)
      if requests && success_indicators.size != requests.size
        fail "Attempted to do #{requests.size} requests but only received confirmation for #{success_indicators.size}!"
      end

      failures = success_indicators.map.with_index do |indicator, i|
        if indicator[WARN]
          LeanplumApi.configuration.logger.warn((requests ? "Warning for #{requests[i]}: " : '') + indicator[WARN].to_s)
        end

        next nil unless indicator[SUCCESS].to_s != 'true'

        requests ? { operation: requests[i], error: indicator } : { error: indicator }
      end.compact

      unless failures.empty?
        error_message = "Operation failure(s): #{failures}"
        LeanplumApi.configuration.logger.error(error_message)
        fail BadResponseError.new(error_message)
      end
    end
  end
end
