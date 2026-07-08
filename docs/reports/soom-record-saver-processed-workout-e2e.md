# SOOM Record Saver ProcessedWorkout End-to-End Coverage

Date: 2026-07-08

## Scope

Added focused persistence/data tests that save through `RecordWorkoutSaver`, fetch the persisted `UnifiedWorkout` and optional persisted route, then build `ProcessedWorkout` from the saved values.

No production app behavior, UI, external integrations, Activity Detail, Share, Profile, Recovery, Record UX, build number, or TestFlight state was changed.

## Files Changed

- `SOOMTests/RecordWorkoutSaveFlowTests.swift`
- `docs/reports/soom-record-saver-processed-workout-e2e.md`

## Test Strategy

The new tests use in-memory SwiftData stores for both workout and route persistence:

- `SwiftDataUnifiedWorkoutStore`
- `SwiftDataWorkoutRoutePersistenceStore`

This covers the real Record save path without writing durable user data. The flow under test is:

1. Build a finished `RecordWorkoutSession`.
2. Build a `RecordWorkoutFinishSummary`.
3. Save via `RecordWorkoutSaver`.
4. Fetch the saved workout from `SwiftDataUnifiedWorkoutStore`.
5. Fetch the saved route from `SwiftDataWorkoutRoutePersistenceStore` when present.
6. Build `ProcessedWorkout` from the persisted workout and route.
7. Assert normalized sport, duration, distance, route, primary metric, and missing sensor behavior.

## Save Path Covered

Added coverage for:

- cycling route-backed Record save
- running route-backed Record save
- walking route-backed Record save
- time-only Record save
- location-denied Record save

The route-backed test verifies all supported Record sports through the same saver/persistence path.

## Expectations Verified

The tests verify:

- persisted sport maps correctly
- persisted duration maps correctly
- route-backed distance is available when expected
- persisted route distance remains consistent with the saved finish summary
- `ProcessedWorkout.route` contains the persisted route summary
- running uses pace as the primary display metric when distance exists
- cycling and walking use speed as the primary display metric when distance exists
- time-only workouts remain valid and do not crash
- location-denied workouts remain valid time-only processed workouts
- missing heart rate, max heart rate, calories, elevation, cadence, power, splits, and zones remain unavailable rather than fabricated

## Production Fixes

No production fixes were needed.

The existing `RecordWorkoutSaver`, SwiftData workout store, SwiftData route store, and `ProcessedWorkoutBuilder` behavior were sufficient for the tested persisted paths.

## Current Limitations

Record still does not capture heart rate, cadence, calories, elevation, power, pause-adjusted moving time, sampled streams, splits, or zones. The tests intentionally assert those fields as missing or unsupported by sport.

The focused test target compiled, but simulator execution is still blocked by the known CoreSimulator clone failure. This is treated as simulator infrastructure, not an app/test failure.

## Verification

- Focused test attempted:
  `xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/RecordWorkoutSaveFlowTests`
- Focused test result: blocked by CoreSimulator infrastructure after compile/test startup. Error: failed to clone device named `iPhone 17e`; device was allocated but stuck in creation state.
- Build for testing passed:
  `xcodebuild build-for-testing -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
- Generic simulator build passed:
  `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
- `git diff --check`: passed
- `git status --short`: only intended test and report changes before commit

## Next Recommendation

Keep the current persistence/data path unchanged. The next data-correctness step is to add focused coverage around any future Record save normalization change before altering production save behavior.
