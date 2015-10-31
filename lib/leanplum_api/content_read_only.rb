require 'leanplum_api/http'

module LeanplumApi
  class ContentReadOnly < HTTP
    def initialize(options = {})
      raise 'Content read only key not configured!' unless LeanplumApi.configuration.content_read_only_key
      super
    end

    # Data export API requests need to use the Data Export key
    def authentication_params
      super.merge(clientKey: LeanplumApi.configuration.content_read_only_key)
    end
  end
end
