# SOOM Recovery Preview Provider ProcessedWorkout Migration

Date: 2026-07-08

## Scope

Migrated only the real-data Recovery preview provider path to use `ProcessedWorkout` before mapping into `RecoveryActivity`.

No Recovery UI, production Recovery provider/factory, RecoveryCalculator scoring logic, WorkoutGrowth logic, Activity Detail, Share, Profile, Record behavior, build number, or TestFlight state was changed.

## Files Changed

- `SOOM/Features/Recovery/UnifiedWorkoutRecoveryPreviewProvider.swift`
- `SOOMTests/UnifiedWorkoutRecoveryPreviewProviderTests.swift`
- `docs/reports/soom-recovery-preview-provider-processed-workout-migration.md`

## What Was Migrated

`UnifiedWorkoutRecoveryPreviewProvider` now:

1. fetches recent `[UnifiedWorkout]` from `UnifiedWorkoutStore`
2. builds `[ProcessedWorkout]` with `ProcessedWorkoutBuilder`
3. maps recovery inputs through `UnifiedWorkoutAnalysisInputSelector.selectRecoveryInputs(fromProcessedWorkouts:)`
4. passes `[RecoveryActivity]` to the unchanged `RecoveryCalculator`

The provider initializer now accepts an injectable `ProcessedWorkoutBuilder` with the same default production behavior.

## What Was Intentionally Not Migrated

- `RecoveryCalculator`
- WorkoutGrowth mappers/builders/providers
- `RecoveryViewModel`
- `RecoveryView`
- `RecoveryViewContainer`
- `RecoveryDataProviderFactory`
- `ActivityRecoveryDataProvider`
- `CombinedRecoveryDataProvider`
- HealthKit/Garmin/Samsung/Google integration
- production/default Recovery source behavior

## Production Behavior Preservation

The default Recovery screen remains on the existing `RecoveryDataProviderFactory` and `ActivityRecoveryDataProvider` path.

Added a focused provider test confirming `RecoveryDataProviderFactory.makeProvider()` still returns a working existing Recovery summary flow. This migration affects only `UnifiedWorkoutRecoveryPreviewProvider`, which powers real-data preview behavior.

## Tests Added Or Updated

Updated `UnifiedWorkoutRecoveryPreviewProviderTests`:

- expected summary parity now compares against the processed selector path
- added time-only workout coverage through the processed preview path
- added production factory preservation coverage

Existing tests still cover:

- preview summary creation
- empty workout handling
- excluded workout filtering
- duplicate-like workouts not being deduplicated automatically

Route-backed provider coverage was not added in this patch because `UnifiedWorkoutRecoveryPreviewProvider` currently fetches workouts only and has no route lookup dependency. Route-aware preview migration remains a separate optional phase.

## Verification

- Focused test attempted:
  `xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/UnifiedWorkoutRecoveryPreviewProviderTests`
- Focused test result: blocked by CoreSimulator infrastructure. Error: failed to clone device named `iPhone 17e`; device was allocated but stuck in creation state.
- Build for testing passed:
  `xcodebuild build-for-testing -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
- Generic simulator build initially hit an Xcode build database lock when run in parallel with build-for-testing, then passed when rerun by itself:
  `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
- `git diff --check`: passed
- `git status --short`: only intended provider, test, and report changes before commit

## Next Recommendation

Keep production Recovery source migration separate. The next safe step is a device/flow QA pass for the real-data Recovery preview, then a product decision on whether the default Recovery screen should read saved workouts through a new processed provider.
