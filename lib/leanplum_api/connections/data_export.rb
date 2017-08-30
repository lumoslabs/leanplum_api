require 'leanplum_api/connections/base_connection'

module LeanplumApi::Connection
  class DataExport < BaseConnection
    def initialize(options = {})
      raise 'Data export key not configured' unless LeanplumApi.configuration.data_export_key
      super
    end

    # Data export API requests need to use the Data Export key
    def authentication_params
      super.merge(clientKey: LeanplumApi.configuration.data_export_key)
    end
  end
end
