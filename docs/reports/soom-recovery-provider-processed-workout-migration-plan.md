# SOOM Recovery Provider ProcessedWorkout Migration Plan

Date: 2026-07-08

## Context

ProcessedWorkout is now adopted by Activity Detail, Share, and Profile aggregation. Recovery has a `ProcessedWorkoutToRecoveryActivityMapper` and parity tests, but Recovery providers and view models still use the current source paths.

Relevant commits:

- `d9f2435 feat(data): add processed workout read model`
- `1254a63 feat(activity): use processed workout metrics`
- `f10c104 feat(share): use processed workout metrics`
- `9160a54 feat(profile): use processed workout aggregation`
- `bc7dfea feat(recovery): map processed workouts to recovery activity`
- `a96d171 test(recovery): add processed workout parity coverage`

This plan is documentation only. No app code was changed.

## Files Inspected

- `docs/reports/soom-recovery-processed-workout-migration-audit.md`
- `docs/reports/soom-recovery-processed-workout-mapper-phase1.md`
- `docs/reports/soom-recovery-processed-workout-parity-plan.md`
- `docs/reports/soom-recovery-processed-workout-parity-tests.md`
- `SOOM/Features/Recovery/UnifiedWorkoutRecoveryPreviewProvider.swift`
- `SOOM/Features/Recovery/RecoveryRealDataPreviewViewModel.swift`
- `SOOM/Features/Recovery/RecoveryRealDataPreviewViewContainer.swift`
- `SOOM/Features/Recovery/RecoveryViewModel.swift`
- `SOOM/Features/Recovery/RecoveryViewContainer.swift`
- `SOOM/Features/Recovery/RecoveryDataProvider.swift`
- `SOOM/Features/Recovery/ActivityRecoveryDataProvider.swift`
- `SOOM/Features/Recovery/CombinedRecoveryDataProvider.swift`
- `SOOM/Features/Recovery/RecoveryDataProviderFactory.swift`
- `SOOM/Features/Recovery/RecoveryCalculator.swift`
- `SOOM/Features/Recovery/ProcessedWorkoutToRecoveryActivityMapper.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutAnalysisInputSelector.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutToRecoveryActivityMapper.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutToGrowthInputMapper.swift`
- `SOOM/Features/Workout/ProcessedWorkoutBuilder.swift`
- `SOOM/Features/Workout/WorkoutGrowthSummaryBuilder.swift`
- `SOOMTests/UnifiedWorkoutToRecoveryActivityMapperTests.swift`
- `SOOMTests/UnifiedWorkoutRecoveryPreviewProviderTests.swift`
- `SOOMTests/RecoveryRealDataPreviewViewModelTests.swift`
- `SOOMTests/RecoveryDataProviderFactoryTests.swift`
- `SOOMTests/CombinedRecoveryDataProviderTests.swift`

## Current Provider And View Model Data Flow

Default Recovery screen:

1. `RecoveryViewContainer` creates `RecoveryViewModel`.
2. `RecoveryViewModel` uses `RecoveryDataProviderFactory.makeProvider(source:)`.
3. `RecoveryDataProviderFactory` returns `ActivityRecoveryDataProvider`.
4. `ActivityRecoveryDataProvider` fetches `[RecoveryActivity]` from a `RecoveryActivityStore`.
5. Default source remains mock-backed through `MockRecoveryActivityStore`.
6. `RecoveryCalculator.calculateSummary(from:)` calculates the summary.
7. `RecoveryViewModel` applies check-in personalization, timeline refresh, weekly summary refresh, and snapshot persistence around the fetched base summary.

Combined/check-in path:

1. `CombinedRecoveryDataProvider` fetches `[RecoveryActivity]`.
2. It fetches recent check-ins.
3. It builds `RecoveryInputContext`.
4. V1 scoring still passes only `context.activities` to `RecoveryCalculator`.

Real-data preview path:

1. `RecoveryRealDataPreviewViewContainer` creates `RecoveryRealDataPreviewViewModel`.
2. The view model uses `UnifiedWorkoutRecoveryPreviewProvider`.
3. `UnifiedWorkoutRecoveryPreviewProvider` fetches `[UnifiedWorkout]` from `UnifiedWorkoutStore`.
4. It calls `UnifiedWorkoutAnalysisInputSelector.selectRecoveryInputs(from:)`.
5. That current selector path maps through `UnifiedWorkoutToRecoveryActivityMapper`.
6. `RecoveryCalculator` calculates the preview summary from `[RecoveryActivity]`.

## Where UnifiedWorkout Currently Enters Recovery

`UnifiedWorkout` enters Recovery only through the real-data preview path:

- `UnifiedWorkoutRecoveryPreviewProvider`
- `RecoveryRealDataPreviewViewModel`
- `RecoveryRealDataPreviewViewContainer`
- tests for preview provider and real-data preview view model

The default Recovery screen does not yet use `UnifiedWorkoutStore` or `ProcessedWorkout`.

## Where ProcessedWorkout Can Be Introduced Safely

Safest first insertion point:

- `UnifiedWorkoutRecoveryPreviewProvider.fetchPreviewSummary()`

Recommended change:

1. Fetch `[UnifiedWorkout]` exactly as today.
2. Build `[ProcessedWorkout]` with `ProcessedWorkoutBuilder`.
3. Call `UnifiedWorkoutAnalysisInputSelector.selectRecoveryInputs(fromProcessedWorkouts:)`.
4. Pass the resulting `[RecoveryActivity]` to the unchanged `RecoveryCalculator`.

This keeps the public provider API stable:

```swift
func fetchPreviewSummary() async throws -> UnifiedWorkoutRecoveryPreviewResult
```

It also keeps `RecoveryRealDataPreviewViewModel` unchanged unless dependency injection needs to expose `ProcessedWorkoutBuilder` for tests.

## Files Likely To Change

Primary implementation files:

- `SOOM/Features/Recovery/UnifiedWorkoutRecoveryPreviewProvider.swift`

Likely test files:

- `SOOMTests/UnifiedWorkoutRecoveryPreviewProviderTests.swift`
- `SOOMTests/RecoveryRealDataPreviewViewModelTests.swift`
- `SOOMTests/UnifiedWorkoutToRecoveryActivityMapperTests.swift` only if additional parity helpers are needed

Possible supporting file, only if injection is needed:

- `SOOM/Features/UnifiedHealth/UnifiedWorkoutAnalysisInputSelector.swift`

Files that should not change in the first provider migration:

- `SOOM/Features/Recovery/RecoveryCalculator.swift`
- `SOOM/Features/Recovery/RecoveryViewModel.swift`
- `SOOM/Features/Recovery/RecoveryView.swift`
- `SOOM/Features/Recovery/RecoveryViewContainer.swift`
- `SOOM/Features/Recovery/ActivityRecoveryDataProvider.swift`
- `SOOM/Features/Recovery/CombinedRecoveryDataProvider.swift`
- `SOOM/Features/Recovery/RecoveryDataProviderFactory.swift`
- WorkoutGrowth builders/mappers
- Activity Detail, Share, Profile, and Record files

## Phased Implementation Plan

### Phase 1: Preview Provider Internal Migration

Scope:

- Add `ProcessedWorkoutBuilder` dependency to `UnifiedWorkoutRecoveryPreviewProvider`.
- Keep default initializer behavior unchanged.
- In `fetchPreviewSummary()`, build processed workouts from fetched UnifiedWorkouts.
- Use `selector.selectRecoveryInputs(fromProcessedWorkouts:)`.
- Keep `usedWorkoutCount` based on resulting recovery inputs, as today.
- Do not change view model or UI behavior.

Expected behavior:

- Equivalent non-route data produces identical `RecoveryActivity` arrays and identical `RecoverySummary` output.
- Existing preview-provider tests continue to pass.
- Existing parity tests remain the guardrail.

### Phase 2: Route-Aware Preview Provider, Optional

Only do this if a route source can be accessed without broad architecture work.

Scope:

- Provide optional route lookup by workout ID.
- Pass routes into `ProcessedWorkoutBuilder`.
- Accept the documented route-derived distance difference only when source distance is missing.

Defer this phase if route lookup requires new persistence plumbing.

### Phase 3: Production Source Decision

Do not switch the default Recovery screen automatically in Phase 1.

Before production/default Recovery uses ProcessedWorkout:

- decide whether the source should be `UnifiedWorkoutStore`, HealthKit direct, mock/local activity store, or a combined/de-duplicated source
- define source precedence
- decide whether check-ins remain personalization-only or become scoring inputs later
- add device QA around Recovery score trust and copy

### Phase 4: Production Provider Migration

After product decision and parity confidence:

- add a new `ProcessedWorkoutRecoveryDataProvider`, or extend factory with a source that reads `UnifiedWorkoutStore`
- keep output contract as `RecoverySummary`
- still pass `[RecoveryActivity]` into unchanged `RecoveryCalculator`
- keep rollback path to `ActivityRecoveryDataProvider`

## Parity And Rollback Strategy

Parity guardrails:

- Keep `UnifiedWorkoutToRecoveryActivityMapperTests` parity coverage passing.
- Add preview-provider test asserting processed provider output matches the old selector output for equivalent fixtures.
- Keep `RecoveryCalculatorTests` passing.
- Keep `UnifiedWorkoutRecoveryPreviewProviderTests.testRecoveryCalculatorFormulaOutputIsNotChangedByPreviewProvider` updated to compare against the processed path while still proving summary parity.

Rollback:

- If migration changes score/status/recommendation unexpectedly, revert the provider implementation to `selector.selectRecoveryInputs(from:)`.
- Because the first migration stays inside `UnifiedWorkoutRecoveryPreviewProvider`, rollback is a single-file behavior change.
- Do not delete `UnifiedWorkoutToRecoveryActivityMapper` until all Recovery providers and tests no longer need it.

Accepted difference:

- `ProcessedWorkoutBuilder` may derive distance from route data when source distance is missing.
- If route input is added later, this must be asserted in tests and documented as route-derived behavior.
- Current RecoveryCalculator score should not change from this distance-only difference because current scoring uses training load, relative effort, and rest days, not distance.

## Tests Needed

Required tests for Phase 1:

- `UnifiedWorkoutRecoveryPreviewProviderTests`
  - provider uses processed path and still returns the same score/status/recommendation for mixed recent workouts
  - excluded workouts remain excluded
  - empty store remains data-insufficient
  - duplicate-like workouts remain not deduplicated automatically
  - used workout count remains based on included recovery inputs

- `UnifiedWorkoutToRecoveryActivityMapperTests`
  - keep existing ProcessedWorkout parity tests passing
  - keep route-derived missing-distance accepted-difference test passing

- `RecoveryRealDataPreviewViewModelTests`
  - existing publish/error/comparison behavior remains unchanged

- `RecoveryCalculatorTests`
  - unchanged score clamps, empty summary, trends, and insights

Optional tests if shared selector code changes:

- `UnifiedWorkoutAnalysisInputSelectorTests`
- `UnifiedWorkoutToGrowthInputMapperTests`
- WorkoutGrowth provider/builder tests only if touched

## Risk Notes

- Recovery trust risk: even small score/copy differences can feel like a product change. Keep calculator output identical unless an accepted difference is documented.
- Source decision risk: default Recovery is still mock/local/provider-based. Switching production Recovery to saved workouts is a product-source decision, not just a mapper migration.
- Route difference risk: ProcessedWorkout can derive route distance, which can make inputs more complete than the old UnifiedWorkout mapper. Keep this isolated and documented.
- Check-in risk: check-ins are currently personalization/context only, not scoring inputs. Do not introduce check-in scoring changes during provider migration.
- HealthKit risk: HealthKit has its own RecoveryActivity mapper/source. Do not merge it with ProcessedWorkout provider migration without a separate integration design.
- WorkoutGrowth risk: Recovery provider migration should not touch growth heuristics or growth input mapping.

## What Must Not Change

- `RecoveryCalculator` scoring logic
- `WorkoutGrowth` calculation logic
- Recovery UI layout/copy
- Activity Detail behavior
- Share behavior
- Profile aggregation behavior
- Record behavior
- Mapbox style URI
- build number
- TestFlight upload
- external platform integrations
- HealthKit/Garmin/Samsung/Google ingestion logic
- new recovery scoring or training-load model

## Migration Recommendation

Safe to implement next:

- Migrate `UnifiedWorkoutRecoveryPreviewProvider` internally to build `ProcessedWorkout` and use the processed selector path.

Not safe to implement yet:

- changing the default `RecoveryViewModel` provider to saved workouts
- replacing `RecoveryDataProviderFactory` default source
- changing `RecoveryCalculator`
- changing WorkoutGrowth

This keeps the next task small, reversible, and protected by the parity tests added in `a96d171`.

## Verification

- Documentation-only change.
- No app code modified.
- No build run, per task rule.
- `git diff --check`: passed.
- `git status --short`: only this new report file before commit.
