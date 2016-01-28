module LeanplumApi
  class Logger < ::Logger
    def format_message(severity, timestamp, progname, msg)
      @hide_keys ||= [
        LeanplumApi.configuration.production_key,
        LeanplumApi.configuration.app_id,
        LeanplumApi.configuration.data_export_key,
        LeanplumApi.configuration.content_read_only_key,
        LeanplumApi.configuration.development_key,
        LeanplumApi.configuration.s3_access_key,
        LeanplumApi.configuration.s3_access_id
      ].compact

      msg = msg.gsub(/#{@hide_keys.map { |k| Regexp.quote(k) }.join('|')}/, '<HIDDEN_KEY>') unless @hide_keys.empty?
      "#{timestamp.strftime('%Y-%m-%d %H:%M:%S')} #{severity} #{msg}\n"
    end
  end
end
