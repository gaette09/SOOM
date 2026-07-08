# SOOM Build 8 TestFlight Upload

Date: 2026-07-08

## Summary

SOOM iOS version 1.0 build 8 was archived and uploaded to App Store Connect using the existing `fastlane ios beta` workflow.

## Environment Checks

- `ASC_KEY_ID`: set
- `ASC_ISSUER_ID`: set
- `ASC_KEY_PATH`: set
- `ASC_KEY_PATH` file: exists
- Secret values and key contents were not printed.

## Version And Build

- Previous build number: 7
- New build number: 8
- Marketing version: 1.0
- Bundle identifier: `app.soom.prototype`

The generated archive at `build/archive/SOOM 2026-07-08 20.47.39.xcarchive` was checked after export:

- `CFBundleShortVersionString`: 1.0
- `CFBundleVersion`: 8

## Upload Result

- Workflow: `fastlane ios beta`
- Archive result: succeeded
- IPA: `build/SOOM.ipa`
- Upload result: succeeded
- App Store Connect app: `6773525324`
- Delivery UUID: `bb60ccd8-19c8-4726-840c-6e3ad23223b5`
- Delivery log result: no errors uploading archive
- App Store Connect uploaded date from delivery log: `2026-07-08T04:50:30-07:00`

## TestFlight Status

Fastlane was configured with `skip_waiting_for_build_processing: true`, so the workflow did not wait for App Store Connect processing to complete. The upload succeeded, but TestFlight processing and tester availability were not confirmed in this run.

## Notes

- Existing Release archive warnings were emitted for iOS 18 deprecation and Sendable diagnostics in HealthKit-related code.
- Xcode emitted passcode-protected device discovery warnings while archiving for `generic/platform=iOS`; these did not fail the archive.
- Generated fastlane files were restored and intentionally excluded from the release commit.
