# leanplum_api

Gem for the Leanplum API.

## Notes

Leanplum calls it a REST API but it is not very RESTful.

Leanplum also likes to change and break stuff in their API without changing the version number, so buyer beware.

The gem uses the ```multi``` method with a POST for all event tracking and user attribute updating requests.  Check Leanplum's docs for more information on ```multi```.

Tested with Leanplum API version 1.0.6 - which is actually totally meaningless because the version is always 1.0.6, even when they make major revisions to how the API works.

`required_ruby_version` is set to 1.9 but this code has only been tested with Ruby 2.1.5 and up!

## Configuration

You need to obtain (at a minimum) the `PRODUCTION_KEY` and `APP_ID` from Leanplum.  You may also want to configure the `DATA_EXPORT_KEY`, `CONTENT_READ_ONLY_KEY`, and `DEVELOPMENT_KEY` if you plan on calling methods that require those keys.  Then you can setup the gem for use in your application like so:

```ruby
require 'leanplum_api'

LeanplumApi.configure do |config|
  # Required keys
  config.app_id = 'MY_APP_ID'
  config.production_key = 'MY_CLIENT_KEY'

  # Optional keys
  config.data_export_key = 'MY_DATA_KEY'          # Necessary only if you want to call data export methods.
  config.content_read_only_key = 'MY_CONTENT_KEY' # Necessary for retrieving AB test info
  config.development_key = 'MY_CONTENT_KEY'       # Necessary for resetting anomalous events

  # Optional configuration variables
  config.logger = LeanplumApi::Logger.new('my.log') # Defaults to STDOUT; the gem logger class hides passwords.
  config.timeout_seconds                            # Defaults to 600
  config.api_version                                # Defaults to 1.0.6

  # S3 export required options - see note below on the S3 export API
  config.s3_bucket_name = 'my_bucket'
  config.s3_access_id = 'access_id'
  config.s3_access_key = 'access_key'

  # Set this to true to send events and user attributes to the test environment.
  # Defaults to false.  See "Debugging" below for more info.
  config.developer_mode = true

  # Override validations for leanplum response. True by default. Useful when stubbing LP responses in application tests.  
  config.validate_response = true
end
```

## Usage

### Tracking events and user attributes:

```ruby
api = LeanplumApi::API.new

# You must provide either :user_id or :device_id for requests involving
# attribute updates or event tracking.
attribute_hash = {
  user_id: 12345,
  first_name: 'Mike',
  last_name: 'Jones',
  gender: 'm',
  email: 'still_tippin@test.com',
  birthday: Date.today  # Dates/times will be converted to ISO8601 format
}
api.set_user_attributes(attribute_hash)

# In 2017, Leanplum implemented the ability to set various first and last timestamps for event occurrences, as well as
# counts for that event in their API at the same time as you set various attributes for that user.
# This is what it would look like to push data about an event that happened 5 times between 2015-02-01 and today.
attribute_hash = {
  user_id: 12345,
  events: {
    my_event_name: {
      count: 5,
      value: 'woodgrain',
      firstTime: '2015-02-01'.to_time, # Dates/times be converted to epoch milliseconds
      lastTime: Time.now.utc           # Dates/times be converted to epoch milliseconds
    }
  }
}
api.set_user_attributes(attribute_hash)

# You must also provide the :event property for event tracking.
## :info is an optional property for an extra string.
## You can optionally provide a :time; if it is not set Leanplum will timestamp the event "now".
## All other key/values besides :user_id, :device_id, :event, and :time will be sent as event params.
event = {
  user_id: 12345,
  event: 'purchase',
  info: 'reallybigpurchase',
  time: Time.now.utc, # Event timestamps will be converted to epoch seconds by the gem.
  some_event_property: 'boss_hog_on_candy'
}
api.track_events(event)
# Events tracked like that will be made part of a session; for independent events use :allow_offline
#   Ed. note 2017-09-12 - looks like Leanplum changed their API and everything is considered offline now
api.track_events(event, allow_offline: true)

# You can also track events, user attributes, and device attributes at the same time. magic!
api.track_multi(
  events: event,
  user_attributes: user_attributes,
  device_attributes: device_attributes,
  options: { force_anomalous_override: true }
)

# If your event is sufficiently far in the past, leanplum will mark your user as "Anomalous"
# To force a reset of this flag, either call the method directly
api.reset_anomalous_users([12345, 23456])
# Or use the :force_anomalous_override option when calling track_events or track_multi
api.track_events(event, force_anomalous_override: true)
```

### API based data export:

```ruby
data_export_api = LeanplumApi::DataExportAPI.new
job_id = data_export_api.export_data(start_time, end_time)
response = data_export_api.wait_for_export_job(job_id)
```

**Note well that Leanplum now officially recommends use of the automated S3 export instead of API based export.**  According to a Leanplum engineer these two data export methodologies are completely independent data paths and in our experience we have found API based data export to be missing 10-15% of the data that is eventually returned by the automated export.

### Other Available Methods
* `api.user_attributes(user_id)`
* `api.user_events(user_id)`
* `api.get_ab_tests(only_recent)`
* `api.get_ab_test(ab_test_id)`
* `api.get_messages(only_recent)`
* `api.get_message(message_id)`
* `api.get_variant(variant_id)`
* `api.get_vars(user_id)`
* `api.set_device_attributes(device_attribute_hashes)`


## Specs

`bundle exec rspec` should work fine at running existing specs.

To write _new_ specs (or regenerate one of [VCR](https://github.com/vcr/vcr)'s YAML files), you must set the `LEANPLUM_PRODUCTION_KEY`, `LEANPLUM_APP_ID`, `LEANPLUM_CONTENT_READ_ONLY_KEY`, `LEANPLUM_DEVELOPMENT_KEY`, and `LEANPLUM_DATA_EXPORT_KEY` environment variables (preferably to some development only keys) to something and then run rspec.  VCR will create fixture data based on your requests, masking your actual keys so that it's safe to commit the file.

The easiest way to do this is to create a `.env` file based on the [.env.example](.env.example) file in the repo and then fill in the blanks.

> BE AWARE THAT IF YOU WRITE A NEW SPEC OR DELETE A VCR FILE, IT'S POSSIBLE THAT REAL DATA WILL BE WRITTEN TO THE `LEANPLUM_APP_ID` YOU CONFIGURE!  Certainly a real request will be made to rebuild the VCR file, and while specs run with ```devMode=true```, it's usually a good idea to create a fake app for testing/running specs against.

```bash
cp .env.example .env
vi .env # open in your favorite text editor; edit it and fill in the various keys
bundle exec rspec
```

## Debugging

The `LEANPLUM_API_DEBUG` environment variable will trigger full printouts of Faraday's debug output to STDERR and to the configured logger.

```bash
cd /my/app
export LEANPLUM_API_DEBUG=true
bundle exec whatever
```

Alternatively you can configure the same sort of output in the gem config block:

```ruby
LeanplumApi.configure do |config|
  config.api_debug = true
end
```

### Developer Mode

You can also configure "developer mode".  This will use the `devMode=true` parameter on some requests, which seems to sends them to a separate queue which might not count towards Leanplum's usage billing.
