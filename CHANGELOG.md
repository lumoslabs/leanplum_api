## HEAD
* Remove useless `.to_json` call in Faraday middleware

## 4.0.1
* Slight improvement to `ResponseValidation` readability; slight change to error messages

## 4.0.0
* **BREAKING CHANGE** - `track_multi` method signature has changed.
* **BREAKING CHANGE** - Data export methods moved to the `DataExportAPI` class
* **BREAKING CHANGE** - rename `wait_for_job` to `wait_for_export_job`
* *New Feature* - Added support for `setDeviceAttributes` (thanks @beingmattlevy)
* Fix `export_users`

## 3.1.0
* Add the ability to send events as `userAttributes` properties

## 3.0.3
* Single connection class; deprecate `wait_for_job` in favor of `wait_for_export_job`

## 3.0.2
* Leanplum changed their "Anomalous timestamp" message again, so now we're just going to reset everyone on any type of warning

## 3.0.1
* Remove `log_path` configuration option that should have come out in 3.0.0

## 3.0.0
* Parse 'True' and 'False' into booleans
