# SOOM Recovery ProcessedWorkout Parity Tests

Date: 2026-07-08

## Scope

Added focused parity coverage for the existing UnifiedWorkout recovery path and the new ProcessedWorkout recovery path before migrating any Recovery provider or view model.

No Recovery UI, Recovery provider, RecoveryCalculator scoring logic, WorkoutGrowth logic, Activity Detail, Share, Profile, or Record behavior was changed.

## Files Changed

- `SOOMTests/UnifiedWorkoutToRecoveryActivityMapperTests.swift`
- `docs/reports/soom-recovery-processed-workout-parity-tests.md`

## Test Cases Added

Added parity coverage for:

- mixed recent workouts through `UnifiedWorkoutAnalysisInputSelector`
- empty workout list through both paths
- RecoveryCalculator summary parity for mixed recent workouts
- route-backed workout with source distance
- route-backed workout with missing source distance

Existing Phase 1 tests in the same file already cover:

- cycling workout
- running workout
- walking workout
- time-only workout
- missing heart rate
- route-backed workout field parity
- selector filtering for excluded processed workouts

## Parity Result

The new tests compare `RecoveryActivity` arrays field-by-field, ignoring the generated `RecoveryActivity.id`:

- workout type
- duration minutes
- distance kilometers
- average heart rate
- relative effort
- training load
- completed date

The RecoveryCalculator summary parity tests compare deterministic user-facing and downstream fields:

- score, status, description, recommendation, and trend text
- coach message
- recommendation card
- trend rows and values
- insight rows
- last updated date
- data quality label

## Accepted Difference

The only accepted difference remains route-derived distance:

- current UnifiedWorkout mapper path maps missing source distance to `0`
- ProcessedWorkout path can derive distance from renderable route data

The test `testRouteDerivedDistanceIsTheOnlyAcceptedProcessedPathDifference` asserts this intentionally. It also verifies the current RecoveryCalculator summary remains unchanged because current Recovery scoring does not consume distance.

## Provider Migration Readiness

Recovery provider migration is safer after these tests because:

- selector-level processed input parity is covered
- RecoveryCalculator summary parity is covered for mixed recent workouts
- route-derived distance behavior is explicit
- excluded workouts remain filtered before calculation

Provider migration should still be a separate task. The next migration should update only the preview/provider path to build `ProcessedWorkout` before mapping, then keep these parity tests passing.

## Verification

- Focused test attempted:
  `xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/UnifiedWorkoutToRecoveryActivityMapperTests`
- Focused test result: blocked by CoreSimulator infrastructure. Error: failed to clone device named `iPhone 17e`; device was allocated but stuck in creation state.
- Build for testing passed:
  `xcodebuild build-for-testing -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
- Generic simulator build passed:
  `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
- `git diff --check`: passed
- `git status --short`: only intended test and report changes before commit
