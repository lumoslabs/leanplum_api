require 'leanplum_api/connections/base_connection'

module LeanplumApi::Connection
  class Development < BaseConnection
    def initialize(options = {})
      raise 'Development key not configured!' unless LeanplumApi.configuration.development_key
      super
    end

    def authentication_params
      super.merge(clientKey: LeanplumApi.configuration.development_key)
    end
  end
end
