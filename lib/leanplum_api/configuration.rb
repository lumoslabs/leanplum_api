module LeanplumApi
  class << self
    attr_accessor :configuration
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration) if block_given?
  end

  def self.reset!
    self.configuration = Configuration.new
  end

  class Configuration
    DEFAULT_LEANPLUM_API_VERSION = '1.0.6'

    attr_accessor :api_version
    attr_accessor :developer_mode
    attr_accessor :log_path

    # IDs and access keys provided by leanplum
    attr_accessor :app_id
    attr_accessor :client_key
    attr_accessor :content_read_only_key
    attr_accessor :data_export_key

    # Optional configuration for exporting raw data to S3.
    # If s3_bucket_name is provided, s3_access_id and s3_access_key must also be provided.
    attr_accessor :s3_bucket_name
    attr_accessor :s3_access_id
    attr_accessor :s3_access_key
    attr_accessor :s3_object_prefix

    def initialize
      @log_path = 'log'
      @api_version = DEFAULT_LEANPLUM_API_VERSION
      @developer_mode = false
    end
  end
end
