# SOOM Profile Processed Workout Migration

Date: 2026-07-08

## Commit Under Work

- Target commit message: `feat(profile): use processed workout aggregation`
- Read-model base: `d9f2435 feat(data): add processed workout read model`
- Activity Detail migration: `1254a63 feat(activity): use processed workout metrics`
- Share migration: `f10c104 feat(share): use processed workout metrics`

## Issue Addressed

Profile aggregation still calculated totals and identity inputs directly from `[UnifiedWorkout]`. Activity Detail and Share already moved to the normalized `ProcessedWorkout` / `WorkoutDisplaySnapshot` layer, so Profile needed the same metric interpretation path to avoid cross-surface drift.

This patch migrates Profile aggregation internals to `ProcessedWorkout` while preserving the existing Profile UI and Profile Hero Identity v2 behavior.

## Files Changed

- `SOOM/Features/Settings/ProfileWorkoutAggregation.swift`
- `SOOMTests/SettingsViewModelTests.swift`
- `docs/reports/soom-profile-processed-workout-migration.md`

## Profile Aggregation Fields Now Using ProcessedWorkout

The existing `ProfileWorkoutAggregator.aggregate(_ workouts: [UnifiedWorkout])` API is preserved for current callers, including `SettingsView`. Internally, it now converts each `UnifiedWorkout` through `ProcessedWorkoutBuilder` and aggregates processed values.

The following aggregate fields now come from `ProcessedWorkout` values:

- `totalDistanceMeters`
- `totalDurationSeconds`
- `activeDays`
- `workoutCount`
- `primarySport`
- `sportDistribution`
- `recent90DayWorkoutCount`
- `recent90DayDistanceMeters`
- `longestRideDistance`
- `longestRunDistance`
- `longestWalkDistance`
- `bestWeeklyDistance`
- `consistencyScore`
- `morningWorkoutRatio`
- `weekendLongRatio`

New named processed entry points were added for tests and future callers:

- `aggregate(processedWorkouts:)`
- `profileIdentity(processedWorkouts:)`

## Preserved Behaviors

- `SettingsView` still calls `profileIdentity(from: [UnifiedWorkout])`.
- Profile Hero Identity v2 UI was not modified.
- Empty profile identity copy is unchanged.
- Dominant sport identity phrases are unchanged.
- Personal best display copy is unchanged.
- Badge and compact hero stat behavior is unchanged.
- Existing `UnifiedWorkout` tests continue to act as compatibility coverage.

## Missing-Data Behavior

Missing metrics follow the processed read-model rules:

- Missing or non-positive distance remains absent from distance totals.
- Time-only workouts still count toward workout count, active days, duration, sport distribution, and consistency.
- Distance-based stats such as longest run/ride/walk and best weekly distance exclude workouts without distance.
- A time-only profile still shows the existing warm distance fallback: `거리 준비 중`.

## Tests / Build Results

- Focused Profile test command:
  - `xcodebuild test -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/SettingsViewModelTests`
  - Result: built and linked, then failed during simulator execution with CoreSimulator infrastructure error: `Failed to clone device named 'iPhone 17e'`. This was not treated as an app/test failure.
- Build command:
  - `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
  - Result: passed.

## Added / Updated Test Coverage

Added focused Profile coverage for:

- processed workout aggregation totals
- mixed sport distribution
- primary sport from processed distance totals
- longest ride/run/walk from processed workouts
- best weekly distance from processed workouts
- time-only workouts counting toward activity while staying out of distance stats
- processed profile identity fallback for time-only workouts

## Not Changed

- No Activity Detail changes.
- No Share changes.
- No Recovery migration.
- No Record save-flow change.
- No Profile UI redesign.
- No Mapbox style URI change.
- No build number bump.
- No TestFlight upload.

## Next Recommended Migration Target

Migrate Recovery mappers/calculators to `ProcessedWorkout` next. Recovery remains the main remaining consumer that can drift from Activity Detail, Share, and Profile on sport type, missing metrics, and time-only workout interpretation.
