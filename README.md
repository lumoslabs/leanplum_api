# leanplum_api

Gem for the Leanplum API.

## Notes

Leanplum calls it a REST API but it is not very RESTful.

The gem uses the ```multi``` method with a POST for all requests except data export.  Check Leanplum's docs for more information on ```multi```.

Tested with Leanplum API version 1.0.6.

required_ruby_version is set to 1.9 but this code has only been tested with Ruby 2.1.5!

## Configuration

You need to obtain (at a minimum) the PRODUCTION and APP_ID from Leanplum.  You may also want to configure the DATA_EXPORT_KEY, CONTENT_READ_ONLY_KEY, and DEVELOPMENT_KEY if you plan on calling methods that require those keys.  Then you can setup the gem for use in your application like so:

```ruby
require 'leanplum_api'

LeanplumApi.configure do |config|
  config.production_key = 'MY_CLIENT_KEY'
  config.app_id = 'MY_APP_ID'
  config.data_export_key = 'MY_DATA_KEY'          # Optional; necessary only if you want to call data export methods.
  config.content_read_only_key = 'MY_CONTENT_KEY' # Optional; necessary for retrieving AB test info
  config.development_key = 'MY_CONTENT_KEY'       # Optional; needed for resetting anomalous events

  # Optional configuration variables
  config.logger = LeanplumApi::Logger.new('file.log') # Defaults to STDOUT.  The gem logger class hides passwords.
  config.timeout_seconds                              # Defaults to 600
  config.api_version                                  # Defaults to 1.0.6
  config.developer_mode                               # Defaults to false

  # S3 export required options
  config.s3_bucket_name = 'my_bucket'
  config.s3_access_id = 'access_id'
  config.s3_access_key = 'access_key'

  # Set this to true to send events and user attributes to the test environment
  # Defaults to false.  See "Debugging" below for more info.
  config.developer_mode = true
end
```

## Usage

Tracking events and user attributes:

```ruby
api = LeanplumApi::API.new

# You must provide either :user_id or :device_id for requests involving
# attribute updates or event tracking.
attribute_hash = {
  user_id: 12345,
  first_name: 'Mike',
  last_name: 'Jones',
  gender: 'm',
  birthday: Date.today, # Dates and times in user attributes will be formatted as strings; Leanplum doesn't support date or time types
  email: 'still_tippin@test.com'
}
api.set_user_attributes(attribute_hash)

# You must also provide the :event property for event tracking
event = {
  user_id: 12345,
  event: 'purchase',
  time: Time.now.utc, # Event timestamps will be converted to epoch seconds by the gem.
  params: {
    'some_event_property' => 'boss_hog_on_candy'
  }
}
api.track_events(event)

# You can also track events and user attributes at the same time
api.track_multi(event, attribute_hash)

# If your event is sufficiently far in the past, leanplum will mark your user as "Anomalous"
# To force a reset of this flag, either call the method directly
api.reset_anomalous_users([12345, 23456])
# Or use the :force_anomalous_override option when calling track_events or track_multi
api.track_events(event, force_anomalous_override: true)
```

Data export:
```ruby
api = LeanplumApi::API.new
job_id = api.export_data(start_time, end_time)
response = wait_for_job(job_id)
```

## Logging

When you instantiate a ```LeanplumApi::API``` object, you can pass a ```Logger``` object to redirect the logging as you see fit.

```ruby
api = LeanplumApi::API.new(logger: Logger.new('/path/to/my/log_file.log))
```

Alternatively, you can configure a log_path in the configure block.
```ruby
LeanplumApi.configure do |config|
  config.log_path = '/path/to/my/logs'
end
```

And logs will be sent to ```/path/to/my/logs/{PID}_leanplum_{timestamp}.log```

The default log_path is ```log/```

## Tests

To run tests, you must set the LEANPLUM_PRODUCTION_KEY, LEANPLUM_APP_ID, LEANPLUM_CONTENT_READ_ONLY_KEY, LEANPLUM_DEVELOPMENT_KEY, and LEANPLUM_DATA_EXPORT_KEY environment variables (preferably to some development only keys) to something and then run rspec.
Because of the nature of VCR/Webmock, you can set them to anything (including invalid keys) as long as you are not changing anything substantive or writing new specs.  If you want to make substantive changes/add new specs, VCR will need to be able to generate fixture data so you will need to use a real set of Leanplum keys.

> BE AWARE THAT IF YOU WRITE A NEW SPEC OR DELETE A VCR FILE, IT'S POSSIBLE THAT REAL DATA WILL BE WRITTEN TO THE LEANPLUM_APP_ID YOU CONFIGURE!  Certainly a real request will be made to rebuild the VCR file, and while specs run with ```devMode=true```, it's usually a good idea to create a fake app for testing/running specs against.

```bash
export LEANPLUM_PRODUCTION_KEY=dev_somethingsomeg123456
export LEANPLUM_APP_ID=app_somethingsomething2039410238
export LEANPLUM_DATA_EXPORT_KEY=data_something_3238mmmX
export LEANPLUM_CONTENT_READ_ONLY_KEY=sometingsome23xx9
export LEANPLUM_DEVELOPMENT_KEY=sometingsome23xx923n23i

bundle exec rspec
```

## Debugging

The LEANPLUM_API_DEBUG environment variable will trigger full printouts of Faraday's debug output to STDERR and to the configured logger.

```bash
cd /my/app
export LEANPLUM_API_DEBUG=true
bundle exec rails whatever
```

You can also configure "developer mode".  This will use the "devMode=true" parameter on all requests, which sends them to a separate queue (and probably means actions logged as development tests don't count towards your bill).
