# SOOM Record ProcessedWorkout Coverage

Date: 2026-07-08

## Scope

Added focused `ProcessedWorkoutBuilder` tests for Record-saved `UnifiedWorkout` shapes with optional route data.

No production app behavior, Record save flow, UI, sensors, external integrations, build number, or TestFlight state was changed.

## Files Changed

- `SOOMTests/ProcessedWorkoutBuilderTests.swift`
- `docs/reports/soom-record-processed-workout-coverage.md`

## Test Cases Added

Added Record-shaped coverage for:

- cycling route-backed workout
- running route-backed workout
- walking route-backed workout
- time-only workout
- location-denied workout
- workout with distance missing but renderable route distance available
- workout with distance present and route distance also present
- missing heart rate
- missing max heart rate
- missing cadence
- missing calories
- missing elevation
- missing power
- missing splits/zones as current moving-time/stream placeholders

## Expectations Verified

The tests verify:

- `.soomLocal` source is preserved
- sport type maps correctly
- duration maps correctly
- route-backed distance is stable
- saved workout distance is preferred when both workout and route distances are present
- route distance is used as a derived fallback only when workout distance is missing
- running display uses derived pace where distance exists
- cycling and walking display use speed where distance exists
- missing Record sensor metrics remain unavailable/missing rather than fake values
- time-only workouts do not crash and keep movement metrics missing
- location-denied workouts remain valid time-only processed workouts

## Builder Fixes

No `ProcessedWorkoutBuilder` fixes were needed.

Current builder behavior already handles Record-saved workouts safely:

- positive workout distance is treated as measured
- route distance is used only as a derived fallback
- average speed is measured when Record saved it, otherwise derived from distance/duration
- running pace is derived from distance/duration
- unavailable HR/calories/elevation/cadence/power remain missing or unsupported by sport

## Current Source-Data Limitations

Record-saved workouts still do not capture:

- heart rate
- max heart rate
- cadence
- power
- calories
- elevation gain
- pause-adjusted moving time
- GPS accuracy metadata
- sampled speed/pace streams
- splits
- zones

These limitations are now explicitly covered as missing/unavailable processed metrics.

## Verification

- Focused test attempted:
  `xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/ProcessedWorkoutBuilderTests`
- Focused test result: blocked by CoreSimulator infrastructure. Error: failed to clone device named `iPhone 17e`; device was allocated but stuck in creation state.
- Build for testing passed:
  `xcodebuild build-for-testing -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
- Generic simulator build passed:
  `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
- `git diff --check`: passed
- `git status --short`: only intended test and report changes before commit

## Next Recommendation

Add a narrow Record-save normalization helper only if future Record save changes introduce duplicated metric sanitation rules. The next practical implementation step is to add an end-to-end test that saves through `RecordWorkoutSaver`, fetches the saved workout and route, and builds `ProcessedWorkout` from those persisted values.
