module LeanplumApi
  class BadResponseError < RuntimeError; end
  class ResourceNotFoundError < RuntimeError; end

  class ResponseValidation < Faraday::Middleware
    Faraday::Request.register_middleware(leanplum_response_validation: self)

    def call(environment)
      operations = nil

      if environment.body
        operations = environment.body[:data] if environment.body[:data] && environment.body[:data].is_a?(Array)
        environment.body = environment.body.to_json
      end

      @app.call(environment).on_complete do |response|
        fail ResourceNotFoundError, response.inspect if response.status == 404
        fail BadResponseError, response.inspect unless response.status == 200 && response.body['response']
        fail BadResponseError, "No :success key in #{response.inspect}!" unless response.body['response'].is_a?(Array) && response.body['response'].first.has_key?('success')
        fail BadResponseError, "Not a success! Response: #{response.inspect}" unless response.body['response'].first['success'] == true

        validate_operation_success(operations, response) if operations
      end
    end

    private

    def validate_operation_success(operations, response)
      success_indicators = response.body['response']
      if success_indicators.size != operations.size
        fail "Attempted to do #{operations.size} operations but only received confirmation for #{success_indicators.size}!"
      end

      failures = []
      success_indicators.each_with_index do |s, i|
        if s['success'].to_s != 'true'
          LeanplumApi.configuration.logger.error("Unsuccessful request at position #{i}: #{operations[i]}")
          failures << { operation: operations[i], error: s }
        end
        LeanplumApi.configuration.logger.warn("Warning for operation #{operations[i]}: #{s['warning']}") if s['warning']
      end

      fail LeanplumValidationException.new("Operation failures: #{failures}") if failures.size > 0
    end
  end
end
