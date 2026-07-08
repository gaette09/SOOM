# SOOM Recovery ProcessedWorkout Device QA Checklist

Date: 2026-07-08

## Context

Recovery real-data preview now uses the `ProcessedWorkout` path internally through `UnifiedWorkoutRecoveryPreviewProvider`.

Current state:

- `UnifiedWorkoutRecoveryPreviewProvider` builds `ProcessedWorkout` before mapping to `RecoveryActivity`.
- `RecoveryCalculator` is unchanged.
- WorkoutGrowth is unchanged.
- Recovery UI is unchanged.
- `RecoveryDataProviderFactory` and the production/default Recovery source are unchanged.
- Production Recovery has not migrated to saved workouts.

## QA Focus

Verify that the processed preview-provider path is stable on device and that visible workout metrics remain consistent across Activity Detail, Share, Profile, and Recovery preview surfaces before deciding whether production Recovery should use saved workouts through a processed provider.

## Result Fields

Use one result per row:

- PASS
- FAIL
- NEEDS PATCH
- Notes

## Device QA Checklist

| Area | Check | Result | Notes |
| --- | --- | --- | --- |
| Recovery | Recovery screen opens normally. |  |  |
| Recovery | Existing production Recovery score behavior appears unchanged. |  |  |
| Recovery | Production Recovery does not appear to switch unexpectedly to saved-workout data. |  |  |
| Recovery preview | Real-data preview surface opens if available in the app build. |  |  |
| Recovery preview | Saved workouts appear to influence preview/provider output if that surface uses preview data. |  |  |
| Recovery preview | Preview used-workout count looks reasonable after saved workouts exist. |  |  |
| Recovery preview | Empty or insufficient saved-workout state remains coherent and non-crashing. |  |  |
| Recovery preview | Time-only workouts do not break the recovery summary. |  |  |
| Recovery preview | Workouts without heart rate do not crash or show broken values. |  |  |
| Recovery preview | Route-backed workouts do not create visible distance inconsistencies in Recovery output. |  |  |
| Recovery preview | Excluded workouts, if toggled/available, do not appear to affect preview output. |  |  |
| Activity Detail | Activity Detail distance, duration, and pace/speed match the saved workout. |  |  |
| Share | Share card distance, duration, and pace/speed match Activity Detail for the same workout. |  |  |
| Profile | Profile totals update consistently with saved workout distance/duration. |  |  |
| Cross-surface | Activity Detail, Share, Profile, and Recovery preview do not disagree on obvious distance/duration values. |  |  |
| Navigation | No crash navigating Recovery -> Activity -> Profile -> Share. |  |  |
| Navigation | No crash returning from Share to Activity and then back to Recovery. |  |  |
| Regression | Record/save flow is not affected by Recovery preview QA. |  |  |
| Regression | WorkoutGrowth or comparison surfaces do not show obvious regressions. |  |  |

## Scenario Coverage

Run at least these workout data scenarios if available on device:

| Scenario | Result | Notes |
| --- | --- | --- |
| Recent running workout with distance and duration. |  |  |
| Recent cycling workout with distance and duration. |  |  |
| Recent walking workout with distance and duration. |  |  |
| Time-only workout or workout missing distance. |  |  |
| Workout missing average heart rate. |  |  |
| Route-backed workout with source distance. |  |  |
| Route-backed workout where route distance may fill missing source distance. |  |  |
| Mixed recent workouts across several days. |  |  |

## Known Expected Behavior

- Production/default Recovery should remain on the existing `RecoveryDataProviderFactory` flow.
- Real-data preview may reflect saved workouts because it uses `UnifiedWorkoutRecoveryPreviewProvider`.
- Route-derived distance is an accepted processed-workout difference only when source distance is missing and route data is available.
- Current Recovery scoring should not visibly change from route-derived distance alone because the current calculator does not score distance directly.

## Decision Rules

- If Recovery output is stable and no regressions appear, keep the preview provider migration and plan production provider work separately.
- If Recovery output differs unexpectedly, do not migrate production provider.
- If data appears inconsistent across Activity Detail, Share, Profile, and Recovery, inspect `ProcessedWorkoutBuilder`, `ProcessedWorkoutToRecoveryActivityMapper`, and `UnifiedWorkoutAnalysisInputSelector` before doing UI polish.
- If production Recovery appears unintentionally changed, create a focused patch before any production provider migration.
- If crashes occur during Recovery, Activity, Profile, or Share navigation, block production provider migration.

## Next Decision

After device QA:

- PASS across Recovery preview and cross-surface consistency: plan a separate production processed provider design/implementation task.
- NEEDS PATCH for preview-only issue: patch `UnifiedWorkoutRecoveryPreviewProvider` or mapper path only.
- FAIL for production Recovery behavior change: block production migration and restore existing production behavior first.

## Verification

- Documentation-only change.
- No app code modified.
- No build run, per task rule.
- `git diff --check`: passed.
- `git status --short`: only this new checklist file before commit.
