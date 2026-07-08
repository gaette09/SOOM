# SOOM Recovery ProcessedWorkout Migration Audit

Date: 2026-07-08

## Context

`ProcessedWorkout` has been implemented and adopted by Activity Detail, Share card model building, and Profile aggregation.

Relevant commits:

- `d9f2435 feat(data): add processed workout read model`
- `1254a63 feat(activity): use processed workout metrics`
- `f10c104 feat(share): use processed workout metrics`
- `9160a54 feat(profile): use processed workout aggregation`

This audit covers Recovery only. No app code was changed.

## Files Inspected

- `SOOM/Features/Recovery/RecoveryCalculator.swift`
- `SOOM/Features/Recovery/RecoveryActivityModels.swift`
- `SOOM/Features/Recovery/RecoveryActivityMapper.swift`
- `SOOM/Features/Recovery/RecoveryActivityStore.swift`
- `SOOM/Features/Recovery/LocalActivityStore.swift`
- `SOOM/Features/Recovery/ActivityRecoveryDataProvider.swift`
- `SOOM/Features/Recovery/CombinedRecoveryDataProvider.swift`
- `SOOM/Features/Recovery/RecoveryDataProviderFactory.swift`
- `SOOM/Features/Recovery/RecoveryViewModel.swift`
- `SOOM/Features/Recovery/UnifiedWorkoutRecoveryPreviewProvider.swift`
- `SOOM/Features/Recovery/RecoveryRealDataPreviewViewModel.swift`
- `SOOM/Features/HealthKit/HealthKitActivityStore.swift`
- `SOOM/Features/HealthKit/HealthKitRecoveryActivityMapper.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutAnalysisInputSelector.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutToRecoveryActivityMapper.swift`
- `SOOM/Features/Workout/WorkoutRecoveryImpactBuilder.swift`
- `SOOM/Features/Workout/WorkoutGrowthMetricsBuilder.swift`
- `SOOM/Features/Workout/WorkoutGrowthSummaryBuilder.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutToGrowthInputMapper.swift`
- `SOOM/Features/Workout/ProcessedWorkout.swift`
- `SOOM/Features/Workout/ProcessedWorkoutBuilder.swift`
- `SOOMTests/RecoveryCalculatorTests.swift`
- `SOOMTests/RecoveryActivityMapperTests.swift`
- `SOOMTests/UnifiedWorkoutToRecoveryActivityMapperTests.swift`
- `SOOMTests/UnifiedWorkoutRecoveryPreviewProviderTests.swift`
- `SOOMTests/RecoveryRealDataPreviewViewModelTests.swift`
- `SOOMTests/CombinedRecoveryDataProviderTests.swift`
- `SOOMTests/HealthKitRecoveryActivityMapperTests.swift`
- `SOOMTests/HealthKitRecoverySourceSmokeTests.swift`
- `SOOMTests/WorkoutRecoveryImpactBuilderTests.swift`
- `SOOMTests/WorkoutGrowthMetricsBuilderTests.swift`
- `SOOMTests/WorkoutGrowthSummaryBuilderTests.swift`

## Current Recovery Data Flow

Recovery calculation is centered on `RecoveryActivity`.

Current production/default path:

1. `RecoveryViewModel` requests a `RecoverySummary` from a `RecoveryDataProvider`.
2. The default provider is `ActivityRecoveryDataProvider`.
3. `ActivityRecoveryDataProvider` fetches `[RecoveryActivity]` from a `RecoveryActivityStore`.
4. The default store is `MockRecoveryActivityStore`.
5. `RecoveryCalculator.calculateSummary(from:)` calculates score, trends, recommendations, and insights from `[RecoveryActivity]`.

Combined/check-in-aware path:

1. `CombinedRecoveryDataProvider` fetches activities from `RecoveryActivityStore`.
2. It fetches check-ins from `RecoveryCheckInStore`.
3. It builds `RecoveryInputContext`.
4. Current calculation still passes only `context.activities` to `RecoveryCalculator`.
5. Check-in signals are summarized but not yet used by the calculator.

Local mock/snapshot path:

1. `LocalActivityStore` owns `[LocalWorkoutSnapshot]`.
2. `RecoveryActivityMapper.map(_ snapshot:)` converts local snapshots into `RecoveryActivity`.
3. `RecoveryCalculator` consumes the mapped activities.

HealthKit activity-store path:

1. `HealthKitActivityStore` fetches `[HealthKitWorkout]`.
2. `HealthKitRecoveryActivityMapper` maps HealthKit workouts to `RecoveryActivity`.
3. `RecoveryCalculator` consumes the mapped activities.

UnifiedWorkout preview path:

1. `UnifiedWorkoutRecoveryPreviewProvider` fetches `[UnifiedWorkout]` from a `UnifiedWorkoutStore`.
2. `UnifiedWorkoutAnalysisInputSelector.selectRecoveryInputs(from:)` filters excluded workouts and maps each included workout through `UnifiedWorkoutToRecoveryActivityMapper`.
3. `RecoveryCalculator` consumes the mapped activities.
4. This path is preview/development-facing, not the default production `RecoveryViewModel` provider.

## Current Recovery Input Sources

- `RecoveryActivity.mockWeek`: default mock activity data.
- `LocalWorkoutSnapshot`: local snapshot mock/preview input.
- `HealthKitWorkout`: HealthKit-specific recovery preview/source input.
- `UnifiedWorkout`: real saved/imported workout preview input.
- `RecoveryCheckIn`: collected by combined provider and personalization, but not part of calculator scoring yet.
- Legacy `Workout`: used by `RecoveryActivityMapper.map(_ workout:)` and by `WorkoutRecoveryImpactBuilder`, not by the default Recovery screen provider.

## Where UnifiedWorkout Is Used

`UnifiedWorkout` currently enters Recovery through:

- `UnifiedWorkoutRecoveryPreviewProvider`
- `UnifiedWorkoutAnalysisInputSelector.selectRecoveryInputs(from:)`
- `UnifiedWorkoutToRecoveryActivityMapper.map(_:)`
- tests around real-data preview and preview-provider parity

The current mapper behavior:

- maps `.running` to `.run`
- maps `.cycling` to `.ride`
- maps `.swimming` to `.swim`
- maps `.walking`, `.hiking`, `.strength`, `.yoga`, `.other` to `.run`
- derives duration minutes with a minimum of 1
- maps missing distance to `0`
- maps missing average heart rate to `0`
- estimates relative effort from duration and heart rate fallback
- estimates training load from duration, heart rate fallback, and calories

This behavior is covered by `UnifiedWorkoutToRecoveryActivityMapperTests`.

## Where Legacy Workout Is Used

Legacy `Workout` appears in two adjacent Recovery-related areas:

- `RecoveryActivityMapper.map(_ workout:)`
  - converts legacy `Workout` to `RecoveryActivity`
  - maps `WorkoutSport` to `RecoveryWorkoutType`
  - estimates training load from duration, heart rate, and effort
- `WorkoutRecoveryImpactBuilder.build(workout:)`
  - converts legacy `Workout` to `WorkoutGrowthInput`
  - classifies a workout's local recovery impact for Activity Detail surfaces

These should not be changed as part of the first Recovery `ProcessedWorkout` migration unless a compile dependency forces it.

## Where ProcessedWorkout Can Be Safely Introduced

The safest insertion point is a new adapter that maps `ProcessedWorkout` to `RecoveryActivity`.

Recommended new adapter:

- `ProcessedWorkoutToRecoveryActivityMapper`

Recommended first consumers:

- Add `UnifiedWorkoutAnalysisInputSelector.selectRecoveryInputs(from processedWorkouts:)`, or add a separate processed selector.
- Update `UnifiedWorkoutRecoveryPreviewProvider` to build processed workouts from fetched `UnifiedWorkout` and map processed workouts into existing `RecoveryActivity`.

This preserves the core calculator contract:

```swift
RecoveryCalculator.calculateSummary(from: [RecoveryActivity])
```

The adapter can use normalized fields:

- `workoutType`
- `durationSeconds`
- `distanceMeters`
- `activeEnergyKcal`
- `averageHeartRate`
- `endedAt`
- `isExcludedFromAnalysis`
- `metricAvailability`

The adapter should not use display strings from `WorkoutDisplaySnapshot` for calculation.

## Calculations That Must Not Change Yet

Do not change these in Phase 1:

- `RecoveryCalculator.calculateScore`
- `RecoveryCalculator.calculateFatigueScore`
- `RecoveryCalculator.calculateTrainingLoadTrend`
- `RecoveryCalculator.calculateFatigueTrend`
- `RecoveryCalculator.calculateHeartRateTrend`
- `RecoveryCalculator.estimateRestDays`
- `RecoveryCalculator` recommendation thresholds
- existing empty-summary score/status behavior
- existing score clamp bounds
- `WorkoutGrowthMetricsBuilder` comparison thresholds
- `WorkoutGrowthSummaryBuilder` heuristic branches
- `WorkoutRecoveryImpactBuilder` impact classification thresholds
- training-load and relative-effort formulas in existing mappers

The current tests explicitly protect score ranges, empty-summary behavior, and preview-provider formula parity.

## Risks Of Changing RecoveryCalculator

Changing `RecoveryCalculator` before the input layer is normalized would be high risk because:

- It would mix data-model migration with product/scoring changes.
- Existing Recovery copy and thresholds are calibrated around current `RecoveryActivity.trainingLoad` and `relativeEffort`.
- Check-ins are collected but not currently included in score calculation; adding them would change score semantics.
- HealthKit and UnifiedWorkout mappers use similar but separate load formulas.
- Walking/hiking currently fall back to run-like recovery type; changing that needs product language and score validation.
- Recovery summaries are user-facing and can affect trust if scores shift without explanation.

## Proposed Migration Strategy

Phase 0: audit only

- Complete this report.
- Do not change code.

Phase 1: adapter parity

- Add `ProcessedWorkoutToRecoveryActivityMapper`.
- Add tests that compare mapper output against `UnifiedWorkoutToRecoveryActivityMapper` for equivalent UnifiedWorkout inputs.
- Update `UnifiedWorkoutRecoveryPreviewProvider` or selector path to use processed workouts internally.
- Keep `RecoveryCalculator` input type as `[RecoveryActivity]`.
- Keep score outputs stable for existing preview-provider tests.
- Keep walking/hiking fallback behavior unless product explicitly changes it.

Phase 2: Recovery preview/store integration

- Consider a `ProcessedWorkoutRecoveryPreviewProvider` or extend current preview provider with processed inputs.
- Keep default production `RecoveryViewModel` provider unchanged until real saved workouts are intended to power Recovery.
- Add tests for time-only workouts, missing HR, missing calories, missing distance, and excluded workouts.

Phase 3: production Recovery source decision

- Decide whether production Recovery should use:
  - mock/local activity store
  - saved `UnifiedWorkoutStore` through processed adapter
  - HealthKit direct source
  - combined source with de-duplication
- Do not switch production default without a product decision and device QA.

Phase 4: scoring model redesign, later

- Only after normalized input parity is stable, evaluate new training load, HR zone, HRV, sleep, and check-in integration.

## Recommended Phase 1 Implementation Scope

Keep Phase 1 narrow:

- Add `ProcessedWorkoutToRecoveryActivityMapper`.
- Add `RecoveryActivity` mapping from `ProcessedWorkout`.
- Add a processed-workout recovery input selector or selector overload.
- Update only the UnifiedWorkout preview path to build `ProcessedWorkout` before mapping.
- Preserve output parity for existing UnifiedWorkout recovery preview tests.
- Do not change production default provider.
- Do not change calculator formulas.
- Do not change UI.

Potential mapping policy for Phase 1:

- `durationMinutes`: `max(Int((durationSeconds / 60).rounded()), 1)` to match current mapper.
- `distanceKm`: `max(distanceMeters / 1000, 0)` with missing distance as `0`.
- `averageHeartRate`: rounded positive average HR, missing as `0`.
- `completedAt`: `endedAt`.
- `relativeEffort`: same formula as current UnifiedWorkout mapper.
- `trainingLoad`: same formula as current UnifiedWorkout mapper.
- `workoutType`: preserve current recovery mapping, including walking/hiking fallback to run unless product explicitly changes it.

## Tests Required Before Implementation

Minimum tests:

- `ProcessedWorkoutToRecoveryActivityMapperTests`
  - running maps to run
  - cycling maps to ride
  - swimming maps to swim
  - walking/hiking fallback parity with current mapper
  - duration/distance/heart-rate/completedAt parity
  - nil HR maps safely
  - training load and relative effort stay within MVP ranges
  - time-only workout maps without crash
  - missing calories does not crash
  - excluded workout handling remains in selector/provider, not mapper

- `UnifiedWorkoutRecoveryPreviewProviderTests`
  - existing score/status/recommendation parity remains unchanged
  - excluded workouts remain excluded
  - empty store remains data-insufficient
  - duplicate-like workouts remain not deduplicated automatically

- `RecoveryCalculatorTests`
  - unchanged; should continue passing as regression guard

Optional tests:

- selector tests proving `[ProcessedWorkout]` filtering mirrors `[UnifiedWorkout]`
- snapshot tests for real-data preview used workout count

## Explicitly Deferred

- New recovery scoring model
- New training-load model
- TRIMP / HR zone / power / cadence load calculation
- HRV, sleep, resting HR, or readiness score integration
- Check-in-driven score changes
- Garmin/Samsung/Google direct integrations
- HealthKit write support
- Advanced charts
- Recovery UI polish unrelated to data correctness

## Next Implementation Recommendation

Implement Phase 1 only: add a `ProcessedWorkoutToRecoveryActivityMapper`, wire it into the UnifiedWorkout preview/selector path, and prove parity with existing mapper and provider tests. Treat any score change as a bug unless deliberately approved.
