# SOOM TCX Route Integration Synthetic Coverage Review

Date: 2026-07-18

## Scope

This review covers only local, synthetic TCX route parsing and attachment to an
existing Apple HealthKit workout. It does not use real activity files, external
services, credentials, production data, or device QA.

## Confirmed Boundary

The TCX implementation is currently limited to a local parser and
`TCXRouteAttachmentService`. The service:

- reads one bounded Garmin TCX v2 activity;
- accepts only existing `.appleHealthKit` workouts;
- validates sport, start time, duration, and distance when TCX summary values
  are present;
- refuses an existing route; and
- saves a `WorkoutRoute` before clearing `routeMissingReason`.

The Activity Detail file-import surface now accepts `.tcx` case-insensitively,
advertises its content type to the file importer, and dispatches selected data
to `TCXRouteAttachmentService`. The service is constructed locally alongside
the existing GPX and FIT services. TCX attachment failures are mapped into the
same Activity Detail result surface; compatibility mismatches use the generic
failure message.

## Synthetic Coverage Reviewed

`TCXRouteParserTests` covers synthetic documents for:

- default and prefixed Garmin namespaces;
- valid route/summary extraction and extension watts;
- invalid coordinates, insufficient points, malformed XML, unsupported roots,
  zero/multiple activities, and coordinate/lap/file-size limits.

`TCXRouteAttachmentServiceTests` covers:

- successful attachment for an existing HealthKit workout and downstream
  route-derived `ProcessedWorkout` availability;
- conservative sport, time, duration, and distance mismatches;
- optional summary fields, existing-route protection, unsupported sources,
  malformed input, and persistence failures.

## Follow-up Required Before Production Claims

- Run approved real-fixture and physical-device QA separately.
- Decide whether route persistence and workout missing-reason clearing require
  an atomic transaction or recovery behavior for a post-route workout-save
  failure.

## Verification Record

- Passed: `xcodebuild build-for-testing -quiet -project SOOM.xcodeproj -scheme
  SOOM -destination 'platform=iOS Simulator,id=EA2F4FAE-2E66-42E4-ABA8-73109D60FFD3'`.
- Passed: `git diff --check`.
- Blocked before test execution: focused synthetic tests for
  `ActivityDetailGPXRouteImportTests`, `TCXRouteParserTests`, and
  `TCXRouteAttachmentServiceTests` could not start because CoreSimulator failed
  to clone either selected iPhone simulator; no test case ran.
