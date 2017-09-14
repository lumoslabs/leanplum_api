require 'leanplum_api/api'

# Support for data export features are semi-deprecated in the gem, because the data they give has historically
# been inaccurate. The automated S3 export has better accuracy with a fraction of the headaches.
# Use these methods at your own risk.

module LeanplumApi
  class DataExportAPI < API
    # Returns the jobId
    # Leanplum has confirmed that using startTime and endTime, especially trying to be relatively up to the minute,
    # leads to sort of unprocessed information that can be incomplete.
    # They recommend using the automatic export to S3 if possible.
    def export_data(start_time, end_time = nil)
      LeanplumApi.configuration.logger.warn("You should probably use the direct S3 export instead of exportData")
      fail "Start time #{start_time} after end time #{end_time}" if end_time && start_time > end_time
      LeanplumApi.configuration.logger.info("Requesting data export from #{start_time} to #{end_time}...")

      # Because of open questions about how startTime and endTime work (or don't work, as the case may be), we
      # only want to pass the dates unless start and end times are specifically requested.
      params = { action: 'exportData', startDate: start_time.strftime('%Y%m%d') }
      params[:startTime] = start_time.strftime('%s') if start_time.is_a?(DateTime) || start_time.is_a?(Time)

      if end_time
        params[:endDate] = end_time.strftime('%Y%m%d')
        params[:endTime] = end_time.strftime('%s') if end_time.is_a?(DateTime) || end_time.is_a?(Time)
      end

      # Handle optional S3 export params
      if LeanplumApi.configuration.s3_bucket_name
        fail 's3_bucket_name set but s3_access_id not configured!' unless LeanplumApi.configuration.s3_access_id
        fail 's3_bucket_name set but s3_access_key not configured!' unless LeanplumApi.configuration.s3_access_key

        params.merge!(
          s3BucketName: LeanplumApi.configuration.s3_bucket_name,
          s3AccessId: LeanplumApi.configuration.s3_access_id,
          s3AccessKey: LeanplumApi.configuration.s3_access_key
        )
        params.merge!(s3ObjectPrefix: LeanplumApi.configuration.s3_object_prefix) if LeanplumApi.configuration.s3_object_prefix
      end

      data_export_connection.get(params).body['response'].first['jobId']
    end

    def get_export_results(job_id)
      response = data_export_connection.get(action: 'getExportResults', jobId: job_id).body['response'].first

      if response['state'] == EXPORT_FINISHED
        LeanplumApi.configuration.logger.info("Export finished.")
        LeanplumApi.configuration.logger.debug("  Response: #{response}")
        {
          files: response['files'],
          number_of_sessions: response['numSessions'],
          number_of_bytes: response['numBytes'],
          state: response['state'],
          s3_copy_status: response['s3CopyStatus']
        }
      else
        { state: response['state'] }
      end
    end

    # See leanplum docs.
    # The segment syntax is identical to that produced by the "Insert Value" feature on the dashboard.
    # Examples: 'Country = "US"', '{Country = "US"} and {App version = 1}'.
    def export_users(ab_test_id = nil, segment = nil)
      data_export_connection.get(action: 'exportUsers', segment: segment, ab_test_id: ab_test_id).body['response'].first['jobId']
    end

    def wait_for_export_job(job_id, polling_interval = 60)
      while get_export_results(job_id)[:state] != EXPORT_FINISHED
        LeanplumApi.configuration.logger.debug("Polling job #{job_id}: #{get_export_results(job_id)}")
        sleep(polling_interval)
      end

      get_export_results(job_id)
    end
  end
end
