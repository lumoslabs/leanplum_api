require 'leanplum_api/connection'

module LeanplumApi::Connections
  class Production < LeanplumApi::Connection
    def authentication_params
      super.merge(clientKey: LeanplumApi.configuration.production_key)
    end
  end
end
