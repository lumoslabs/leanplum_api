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
        fail BadResponseError, response.inspect unless response.status == 200 && (responses = response.body['response'])
        fail BadResponseError, "No :success key in #{responses.inspect}!" unless responses.is_a?(Array) && responses.all? { |r| r.key?(SUCCESS) }

        validate_operation_success(responses, requests)
      end
    end

    private

    def validate_operation_success(success_indicators, requests)
      if requests && success_indicators.size != requests.size
        fail "Attempted to do #{requests.size} requests but only received confirmation for #{success_indicators.size}!"
      end

      failures = success_indicators.map.with_index do |indicator, i|
        if indicator[WARN]
          LeanplumApi.configuration.logger.warn((requests ? "Warning for #{requests[i]}: " : '') + indicator[WARN].to_s)
        end

        if indicator[SUCCESS].to_s != 'true'
          (requests ? { operation: requests[i], error: indicator } : { error: indicator })
        else
          nil
        end
      end.compact

      unless failures.empty?
        error_message = "Operation failure(s): #{failures}"
        LeanplumApi.configuration.logger.error(error_message)
        fail BadResponseError.new(error_message)
      end
    end
  end
end
