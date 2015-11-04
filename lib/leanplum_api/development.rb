require 'leanplum_api/http'

module LeanplumApi
  class Development < HTTP
    def initialize(options = {})
      raise 'Development key not configured!' unless LeanplumApi.configuration.development_key
      super
    end

    def authentication_params
      super.merge(clientKey: LeanplumApi.configuration.development_key)
    end
  end
end
