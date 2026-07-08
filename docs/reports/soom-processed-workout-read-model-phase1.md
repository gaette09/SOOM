# SOOM Processed Workout Read Model Phase 1/2

Date: 2026-07-08

## Summary

Implemented Phase 1 and Phase 2 of the Processed Workout read-model plan:

- Added a normalized `ProcessedWorkout` value model.
- Added `WorkoutDisplaySnapshot` for display-ready metric text.
- Added explicit metric availability states.
- Added `ProcessedWorkoutBuilder` from `UnifiedWorkout` plus optional `WorkoutRoute`.
- Added focused tests for Cycling, Running, Walking, time-only, route-backed, missing metrics, pace/speed behavior, and incomplete data.

No screens were migrated in this task.

## Files Changed

- `SOOM/Features/Workout/ProcessedWorkout.swift`
- `SOOM/Features/Workout/ProcessedWorkoutBuilder.swift`
- `SOOMTests/ProcessedWorkoutBuilderTests.swift`
- `SOOM.xcodeproj/project.pbxproj`
- `docs/reports/soom-processed-workout-read-model-phase1.md`

## Model Created

`ProcessedWorkout` is a value-type read model with:

- identity/source fields from `UnifiedWorkout`
- normalized sport type
- start/end/duration
- raw numeric metrics where available
- optional processed route
- metric availability map
- display snapshot

Support types:

- `ProcessedWorkoutRoute`
- `ProcessedWorkoutMetric`
- `ProcessedWorkoutMetricState`
- `WorkoutDisplaySnapshot`

The read model is not persisted and does not change `UnifiedWorkoutStore`.

## Builder Behavior

`ProcessedWorkoutBuilder.make(from:route:)` currently:

- prefers positive summary values from `UnifiedWorkout`
- derives distance from route only when workout distance is missing and route is renderable
- derives speed from distance/duration when source speed is missing
- derives pace for Running and Hiking when distance/duration are valid
- keeps Walking as `.walking`
- uses speed as the primary display metric for Cycling and Walking
- uses pace as the primary display metric for Running
- includes route metadata only when optional route data is passed
- marks route renderable only when at least two coordinates exist

## Missing-Data Rules

Internal rules:

- non-positive numeric values are treated as unavailable
- unavailable metrics remain `nil`
- metric availability uses `.measured`, `.derived`, `.missing`, or `.unsupported`
- route fallback distance/elevation is `.derived`
- local Record-only missing metrics such as HR/calories/power/cadence are not estimated

Display snapshot rules:

- missing distance: `거리 준비 중`
- missing pace/speed: `움직임 준비 중`
- optional stat-grid style values such as HR/elevation/calories: `—`
- route badge appears only when the route is renderable

## Tests Added

`ProcessedWorkoutBuilderTests` covers:

- Cycling uses speed as the primary metric.
- Running uses derived pace as the primary metric.
- Walking remains walking and uses speed.
- Time-only workouts keep distance and movement metrics missing.
- Route-backed workouts include renderable route metadata and route-derived fallbacks.
- Missing HR, power, cadence, elevation, and calories are explicit.
- Incomplete or negative data does not crash and produces safe placeholders.

## Intentionally Not Migrated

The following were intentionally not changed:

- legacy `Workout`
- `UnifiedWorkoutStore`
- SwiftData schemas
- Record save flow
- Activity Detail
- Profile aggregation
- Share card builder/rendering
- Recovery mappers/calculators
- HealthKit import behavior
- Garmin/Samsung/Google integrations
- UI polish
- TestFlight/build number/release flow

## Verification

Commands run:

- `xcrun simctl list devices available`
- `xcodebuild test -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/ProcessedWorkoutBuilderTests`
- `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
- `git diff --check`
- `git status --short`

Results:

- Generic iOS Simulator build passed.
- Focused `ProcessedWorkoutBuilderTests` compiled and linked, but test execution was blocked by CoreSimulator infrastructure:
  - `Failed to clone device named 'iPhone 17e'.`
  - underlying note: device was allocated but stuck in creation state.
- The focused test failure is not treated as an app/test failure because logs show the test bundle built and the failure occurred during simulator cloning.
- Xcode also emitted connected-device passcode warnings during build/test discovery; these did not fail the generic simulator build.

## Next Recommended Phase

Implement Phase 3 only after Phase 1/2 settles:

- Add a compatibility adapter from legacy `Workout` to `ProcessedWorkout`.
- Add parity tests for current Activity Detail and Share-derived values.
- Do not migrate Activity Detail/Profile/Share/Recovery until the legacy adapter is covered by tests.
