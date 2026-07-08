# SOOM Recovery ProcessedWorkout Parity Verification Plan

Date: 2026-07-08

## Context

Recovery `ProcessedWorkout` mapper Phase 1 was implemented in `bc7dfea feat(recovery): map processed workouts to recovery activity`.

Current state:

- `ProcessedWorkoutToRecoveryActivityMapper` exists.
- `UnifiedWorkoutAnalysisInputSelector` has `selectRecoveryInputs(fromProcessedWorkouts:)`.
- `RecoveryCalculator` is unchanged.
- WorkoutGrowth calculation logic is unchanged.
- Recovery UI, view models, and production/default providers have not migrated.

This plan defines the parity work required before replacing any Recovery source with a `ProcessedWorkout`-based path.

## Files Inspected

- `docs/reports/soom-recovery-processed-workout-migration-audit.md`
- `docs/reports/soom-recovery-processed-workout-mapper-phase1.md`
- `SOOM/Features/Recovery/RecoveryCalculator.swift`
- `SOOM/Features/Recovery/ProcessedWorkoutToRecoveryActivityMapper.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutToRecoveryActivityMapper.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutAnalysisInputSelector.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutToGrowthInputMapper.swift`
- `SOOM/Features/Workout/WorkoutGrowthSummaryBuilder.swift`
- `SOOMTests/UnifiedWorkoutToRecoveryActivityMapperTests.swift`
- `SOOMTests/UnifiedWorkoutRecoveryPreviewProviderTests.swift`
- `SOOMTests/RecoveryCalculatorTests.swift`
- `SOOMTests/WorkoutGrowthSummaryBuilderTests.swift`

## What Needs To Be Compared

Parity must be proven at three levels:

1. Recovery input parity:
   - Compare `[RecoveryActivity]` from the current UnifiedWorkout path against `[RecoveryActivity]` from the new ProcessedWorkout path.
   - Compare count, order, sport type, duration, distance, average heart rate, relative effort, training load, and completed date.

2. Recovery summary parity:
   - Pass both activity arrays into the same `RecoveryCalculator(referenceDate:)`.
   - Compare output fields that users see or that downstream UI consumes.

3. Adjacent WorkoutGrowth parity, only if the implementation touches shared selector or provider plumbing:
   - Compare existing `UnifiedWorkoutToGrowthInputMapper` and `WorkoutGrowthSummaryBuilder` outputs remain unchanged.
   - Do not migrate WorkoutGrowth to `ProcessedWorkout` as part of the Recovery source switch unless a separate scoped task explicitly does that.

## Current UnifiedWorkout Mapper Path

Current path:

1. `UnifiedWorkoutRecoveryPreviewProvider` fetches `[UnifiedWorkout]` from `UnifiedWorkoutStore`.
2. `UnifiedWorkoutAnalysisInputSelector.selectRecoveryInputs(from:)` filters `isExcludedFromAnalysis`.
3. `UnifiedWorkoutToRecoveryActivityMapper.map(_:)` converts each `UnifiedWorkout` to `RecoveryActivity`.
4. `RecoveryCalculator.calculateSummary(from:)` calculates score, trends, recommendations, insights, and data quality.

Current mapper policy:

- running to run
- cycling to ride
- swimming to swim
- walking, hiking, strength, yoga, and other to run fallback
- missing distance to `0`
- missing heart rate to `0`
- rounded duration minutes with minimum `1`
- existing MVP relative effort and training load formulas
- completed date from `UnifiedWorkout.endDate`

## New ProcessedWorkout Mapper Path

Target path for parity tests:

1. Start from the same `[UnifiedWorkout]` fixtures as the current path.
2. Build `[ProcessedWorkout]` with `ProcessedWorkoutBuilder`.
3. Include optional route data only in route-specific tests.
4. `UnifiedWorkoutAnalysisInputSelector.selectRecoveryInputs(fromProcessedWorkouts:)` filters `isExcludedFromAnalysis`.
5. `ProcessedWorkoutToRecoveryActivityMapper.map(_:)` converts each `ProcessedWorkout` to `RecoveryActivity`.
6. The same `RecoveryCalculator(referenceDate:)` calculates summaries from the processed path.

This path must not use `WorkoutDisplaySnapshot` strings for scoring or recovery calculations.

## RecoveryCalculator Outputs To Compare

For equivalent activity inputs, compare:

- `score`
- `status`
- `description`
- `recommendation`
- `trendText`
- `coachMessage.coachName`
- `coachMessage.subtitle`
- `coachMessage.message`
- `recommendationCard.title`
- `recommendationCard.description`
- `recommendationCard.actionLabel`
- `recommendationCard.icon`
- `trends.count`
- each trend `title`, `currentValue`, `unit`, `changeText`, `direction`, and `values`
- `insights.count`
- each insight `title`, `message`, `icon`, and `tone`
- `lastUpdated`
- `dataQuality`

Use one fixed `referenceDate` in all parity tests so date-window behavior and `lastUpdated` are deterministic.

## WorkoutGrowth Outputs To Compare If Applicable

WorkoutGrowth is not part of the RecoveryCalculator input contract, but it shares UnifiedWorkout selector plumbing.

If the next implementation only adds Recovery parity tests and a processed Recovery preview path, WorkoutGrowth can be guarded by existing tests only.

If shared selector/provider code is changed in a way that could affect growth inputs, compare:

- `UnifiedWorkoutAnalysisInputSelector.selectGrowthInputs(from:)` output count and order
- `WorkoutGrowthInput` fields:
  - `id`
  - `source`
  - `workoutType`
  - `startDate`
  - `durationMinutes`
  - `distanceKm`
  - `averagePaceText`
  - `averageSpeedKmh`
  - `averageHeartRate`
  - `elevationGainMeters`
  - `activeEnergyKcal`

Do not change `WorkoutGrowthSummaryBuilder` heuristics during Recovery parity work.

## Acceptable Differences

No differences are acceptable for equivalent UnifiedWorkout inputs without route-derived fallback data.

Allowed documented difference:

- `ProcessedWorkoutBuilder` can derive missing `distanceMeters` from route data when the source workout distance is missing and the route is renderable.
- The direct `UnifiedWorkoutToRecoveryActivityMapper` maps missing source distance to `0`.
- In route-backed missing-distance tests, the processed path may produce non-zero `RecoveryActivity.distanceKm`; resulting Recovery summary differences must be documented as intentional and route-derived.

Other differences must block migration until explained or fixed:

- changed score
- changed status
- changed recommendation copy
- changed trend values
- changed insight count/content
- changed filtering of excluded workouts
- changed workout ordering
- changed walking/hiking fallback behavior
- changed missing heart-rate or missing calorie behavior

## Required Test Cases

Add parity coverage for:

- cycling workout
- running workout
- walking workout
- time-only workout
- route-backed workout with source distance
- route-backed workout with missing distance
- missing heart rate
- missing calories
- mixed recent workouts across 7 days
- excluded workout mixed with included workouts
- empty workout list

Minimum mixed recent fixture:

- day 0 running, distance and heart rate present
- day 1 cycling, distance and calories present
- day 3 walking, heart rate missing
- day 5 time-only workout
- one excluded high-load workout that must not affect either path

## Recommended Next Implementation

Add focused parity tests before changing any Recovery source:

1. Build current activities:
   - `selector.selectRecoveryInputs(from: unifiedWorkouts)`

2. Build processed activities:
   - `processedWorkouts = unifiedWorkouts.map { ProcessedWorkoutBuilder().make(from: $0, route: routeByWorkoutId[$0.id]) }`
   - `selector.selectRecoveryInputs(fromProcessedWorkouts: processedWorkouts)`

3. Compare `RecoveryActivity` arrays:
   - exact equality by field, ignoring `RecoveryActivity.id`

4. Compare `RecoveryCalculator` summaries:
   - exact equality for deterministic fields with fixed reference date
   - numeric equality for scores/trend values

5. Add route-backed missing-distance test:
   - assert the activity distance difference is intentional
   - assert summary differences, if any, are limited to distance-dependent text/values and documented

6. Keep provider/source unchanged:
   - do not migrate `UnifiedWorkoutRecoveryPreviewProvider`
   - do not change `RecoveryViewModel`
   - do not change default production `RecoveryDataProvider`

7. Run existing recovery and growth tests:
   - `UnifiedWorkoutToRecoveryActivityMapperTests`
   - `UnifiedWorkoutRecoveryPreviewProviderTests`
   - `RecoveryCalculatorTests`
   - `UnifiedWorkoutAnalysisInputSelectorTests`
   - `UnifiedWorkoutToGrowthInputMapperTests`
   - `WorkoutGrowthSummaryBuilderTests` if selector/shared plumbing changes

## Migration Gate

Recovery source can switch to the processed path only after:

- `RecoveryActivity` arrays match for equivalent non-route-fallback fixtures.
- `RecoveryCalculator` summaries match for equivalent non-route-fallback fixtures.
- Excluded workouts are filtered identically.
- Empty and time-only inputs remain stable.
- Route-derived distance differences are explicitly documented and accepted.
- Existing RecoveryCalculator tests pass.
- Existing WorkoutGrowth tests pass or are confirmed unaffected.
- No Recovery UI/provider migration is bundled with scoring or growth logic changes.

If any unplanned score, trend, insight, or recommendation difference appears, block migration and keep the current UnifiedWorkout path until the difference is fixed or product-approved.

## What Not To Change In The Parity Implementation

- Do not change `RecoveryCalculator`.
- Do not change WorkoutGrowth scoring or summary heuristics.
- Do not change Recovery UI.
- Do not change production/default Recovery provider.
- Do not change Activity Detail, Share, Profile, or Record save flow.
- Do not add a new recovery scoring model.
- Do not add external platform integration work.
- Do not upload TestFlight.
- Do not bump build number.

## Verification For This Plan

- Documentation-only change.
- No app code modified.
- No build run, per task rule.
- `git diff --check`: passed.
- `git status --short`: only this new report file before commit.
