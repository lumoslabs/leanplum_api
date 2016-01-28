require 'leanplum_api/connections/production'

module LeanplumApi
  class Development < Production
    def initialize(options = {})
      raise 'Development key not configured!' unless LeanplumApi.configuration.development_key
      super
    end

    def authentication_params
      super.merge(clientKey: LeanplumApi.configuration.development_key)
    end
  end
end
