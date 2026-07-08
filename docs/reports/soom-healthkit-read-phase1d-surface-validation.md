# SOOM HealthKit Read Phase 1D Surface Validation

Date: 2026-07-08

## Summary

Added validation coverage showing manually imported Apple HealthKit workouts remain coherent across existing `ProcessedWorkout` consumers.

This phase did not change UI, HealthKit permissions, background sync, HealthKit write behavior, Record behavior, third-party integrations, build number, or TestFlight state.

## Files Changed

- `SOOMTests/HealthKitImportedWorkoutSurfaceValidationTests.swift`
- `SOOM.xcodeproj/project.pbxproj`
- `docs/reports/soom-healthkit-read-phase1d-surface-validation.md`

## Validation Surfaces Covered

The new integration-level tests validate the existing path:

`HealthKitWorkout -> HealthKitWorkoutImportPipeline -> UnifiedWorkout -> optional WorkoutRoute -> ProcessedWorkoutBuilder`

Then they assert downstream consumer behavior through:

- Activity Detail display snapshot values via `WorkoutDisplaySnapshot`
- Share card model values via `ShareableWorkoutCardBuilder`
- Profile aggregation via `ProfileWorkoutAggregator.aggregate(processedWorkouts:)`
- Recovery preview input mapping via `ProcessedWorkoutToRecoveryActivityMapper`
- Duplicate filtering through `HealthKitWorkoutImportPipeline`

No SwiftUI view hierarchy or renderer behavior was changed.

## Route-Backed Behavior

Coverage imports a HealthKit cycling workout with route data and verifies:

- the HealthKit source and external identifier are preserved
- route data is associated with the imported `UnifiedWorkout.id`
- route-derived distance and elevation are present when summary distance is missing
- Activity Detail snapshot values show Apple Health source, cycling sport, distance, duration, speed, elevation, calories, and route badge
- Share card values match the processed snapshot
- Profile aggregation includes the workout once with cycling totals
- Recovery mapping consumes the processed workout as a ride input

## No-Route Behavior

Coverage imports a HealthKit running workout without route data and verifies:

- summary import succeeds
- no route is persisted or passed into the processed model
- route availability remains `.missing`
- Activity Detail snapshot uses normal distance/pace values and no route badge
- Share/Profile/Recovery consumers remain coherent without route data

## Missing Metric Behavior

Coverage imports a HealthKit walking workout with missing distance, calories, heart rate, and elevation and verifies:

- missing optional metrics remain `nil`
- metric availability stays `.missing`
- display snapshot uses placeholders such as `거리 준비 중`, `움직임 준비 중`, and `—`
- Share optional metric fields remain absent instead of zero-filled
- Profile counts the workout and duration activity without adding fake distance
- Recovery mapping uses safe zero values only at the recovery input boundary

## Duplicate Behavior

Coverage verifies:

- a HealthKit workout skipped as a duplicate of an existing SOOM local workout produces no processed downstream surface input
- Profile and Recovery processed selectors receive no HealthKit input for that skipped duplicate
- a HealthKit-only workout imported twice with the same external identifier is saved once by the store upsert behavior and can be represented once by downstream processed validation

## Tests / Build Results

Focused test command:

```sh
xcodebuild test -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SOOMTests/HealthKitImportedWorkoutSurfaceValidationTests -only-testing:SOOMTests/HealthKitWorkoutImportPipelineTests -only-testing:SOOMTests/ProcessedWorkoutBuilderTests -only-testing:SOOMTests/ShareableWorkoutCardBuilderTests -only-testing:SOOMTests/UnifiedWorkoutToRecoveryActivityMapperTests -quiet
```

Result:

- Tests compiled and reached test startup.
- Execution was blocked by CoreSimulator infrastructure:
  - `Failed to clone device named 'iPhone 17 Pro'.`
  - Device was allocated but stuck in creation state.
- No test assertion failure was reported before the simulator clone failure.

Build-for-testing command:

```sh
xcodebuild build-for-testing -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'
```

Result:

- Passed.
- Warnings remain for deprecated test `HKWorkout` initializers, including the new test fixture using the same local pattern, plus an existing always-true `UIActivityViewController` type check in share renderer tests.

Requested build command:

```sh
xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'
```

Result:

- Passed.

## Limitations

- This is model/builder/mapper validation, not physical device UI QA.
- Route rendering pixels, Mapbox camera fit, and Share export rendering remain covered by their existing route/share tests and device QA.
- Recovery default production provider remains unchanged; this phase validates the processed recovery input path.
- HealthKit detail-time streams for heart rate, cadence, and power remain deferred.

## Next Recommended Phase

Phase 1E: manual import QA and permission-state validation.

Recommended work:

- Run a physical device QA pass with Apple Health workouts that include route and no-route cases.
- Validate HealthKit permission denied, partial permission, and no data states.
- Confirm Activity Detail, Share, Profile, and Recovery preview behave as expected with real imported workouts.
- Continue deferring HealthKit write, background sync, Garmin/Samsung/Google integrations, advanced sampled stream persistence, and UI polish unrelated to import correctness.
