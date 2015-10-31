require 'logger'

module LeanplumApi
  class LeanplumApiLogger < Logger
    def format_message(severity, timestamp, progname, msg)
      @keys ||= [
        LeanplumApi.configuration.client_key,
        LeanplumApi.configuration.app_id,
        LeanplumApi.configuration.data_export_key,
        LeanplumApi.configuration.content_read_only_key,
        LeanplumApi.configuration.s3_access_key,
        LeanplumApi.configuration.s3_access_id
      ].compact

      if @keys.empty?
        "#{timestamp.strftime('%Y-%m-%d %H:%M:%S')} #{severity} #{msg}\n"
      else
        "#{timestamp.strftime('%Y-%m-%d %H:%M:%S')} #{severity} #{msg.gsub(/#{@keys.join('|')}/, '<HIDDEN_KEY>')}\n"
      end
    end
  end
end
