module LeanplumApi
  class BadResponseError < RuntimeError; end

  class ResponseValidation < Faraday::Middleware
    Faraday::Response.register_middleware(leanplum_response_validation: self)

    def call(environment)
      @app.call(environment).on_complete do |response|
        fail BadResponseError, response.inspect unless response.status == 200 && response.body['response']
        fail BadResponseError, "No :success key in #{response.inspect}!" unless response.body['response'].first['success']
        fail BadResponseError, "Not a success! Response: #{response}" unless response.body['response'].first['success'] == true
      end
    end
  end
end
