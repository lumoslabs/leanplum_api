require 'leanplum_api/connections/base_connection'

module LeanplumApi::Connection
  class Production < BaseConnection
    def authentication_params
      super.merge(clientKey: LeanplumApi.configuration.production_key)
    end
  end
end
