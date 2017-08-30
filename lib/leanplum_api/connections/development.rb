require 'leanplum_api/connection'

module LeanplumApi::Connections
  class Development < LeanplumApi::Connection
    def initialize(options = {})
      raise 'Development key not configured!' unless LeanplumApi.configuration.development_key
      super
    end

    def authentication_params
      super.merge(clientKey: LeanplumApi.configuration.development_key)
    end
  end
end
