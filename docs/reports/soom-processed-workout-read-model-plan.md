# SOOM Processed Workout Read-Model Design Plan

Date: 2026-07-08

## Summary

SOOM should add a local processed workout/read-model layer before changing Activity Detail, Profile, Share, Recovery, or external ingestion. The current app has two active source models:

- `UnifiedWorkout`: normalized persistence and integration model.
- `Workout`: legacy rich UI model used by Activity Detail and several display/share paths.

The recommended target is `ProcessedWorkout`, with a display-facing nested model named `WorkoutDisplaySnapshot` if the implementation wants a clearer split between canonical derived data and preformatted UI text. Do not delete `Workout` yet and do not break `UnifiedWorkoutStore`. Add adapters first, then move screens gradually.

## Files Inspected

- `docs/reports/soom-data-pipeline-v1-audit.md`
- `docs/ops/PROJECT_MEMORY.md`
- `docs/ops/TODAY_QUEUE.md`
- `SOOM/Models/Workout.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkout.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutType.swift`
- `SOOM/Features/UnifiedHealth/UnifiedDataSource.swift`
- `SOOM/Features/UnifiedHealth/UnifiedDataQuality.swift`
- `SOOM/Features/UnifiedHealth/Persistence/UnifiedWorkoutRecord.swift`
- `SOOM/Features/UnifiedHealth/Persistence/UnifiedWorkoutStore.swift`
- `SOOM/Features/UnifiedHealth/Persistence/UnifiedWorkoutPersistenceMapper.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutLibraryView.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutLibraryViewModel.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutAnalysisInputSelector.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutToGrowthInputMapper.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutToRecoveryActivityMapper.swift`
- `SOOM/Features/Activity/RecordLaunchPlan.swift`
- `SOOM/Features/Activity/RecordWorkoutSession.swift`
- `SOOM/Features/Activity/RecordWorkoutSaveFlow.swift`
- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOM/Features/Workout/WorkoutRoute.swift`
- `SOOM/Features/Workout/PersistedWorkoutRoute.swift`
- `SOOM/Features/Workout/WorkoutRoutePersistenceStore.swift`
- `SOOM/Features/Workout/WorkoutRouteStore.swift`
- `SOOM/Features/Workout/WorkoutGrowthInput.swift`
- `SOOM/Features/Workout/ShareableWorkoutCardBuilder.swift`
- `SOOM/Features/Workout/ShareableWorkoutCardModel.swift`
- `SOOM/Features/Workout/ShareableWorkoutCardRenderer.swift`
- `SOOM/Components/ShareableWorkoutCardView.swift`
- `SOOM/Features/Settings/ProfileWorkoutAggregation.swift`
- `SOOM/Features/Settings/ProfileSummaryCard.swift`
- `SOOM/Features/Recovery/UnifiedWorkoutRecoveryPreviewProvider.swift`
- `SOOM/Features/HealthKit/HealthKitWorkout.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutImportPipeline.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutToUnifiedWorkoutMapper.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutRouteFetcher.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutRouteMapper.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutMetricSample.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutMetricMapper.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutMetricStreamFetcher.swift`
- relevant tests listed by `SOOMTests/*Workout*`, `SOOMTests/*Share*`, `SOOMTests/*Profile*`, `SOOMTests/*Recovery*`, and `SOOMTests/*HealthKit*`

## Why A Read-Model Layer Is Needed

The current data flow lets multiple surfaces derive their own interpretation of the same workout:

- Record saves a partial `UnifiedWorkout` and optional persisted route.
- Activity Detail still uses legacy `Workout`, then builds `WorkoutGrowthInput` and temporary `UnifiedWorkout` drafts from it.
- Profile aggregates directly from `[UnifiedWorkout]`.
- Share can build from either `WorkoutGrowthInput` or legacy `Workout`.
- Recovery maps `UnifiedWorkout` to `RecoveryActivity`, with walking/hiking/other currently falling back to run-like recovery input.

This creates avoidable inconsistencies:

- Walking can be stored as `.walking` but displayed or interpreted as running in some paths.
- Distance, pace, speed, duration, and placeholders are formatted independently by different views/builders.
- Route availability is split between `UnifiedWorkout` and `WorkoutRoute`.
- Missing data can look like measured data when default values such as `0` are used.
- HealthKit and future external integrations would multiply these differences if they map directly into each surface.

The read model should become the single local interpretation layer between stored/raw data and display/analysis consumers.

## Source Models Currently Active

| Model | Role today | Keep? | Notes |
| --- | --- | --- | --- |
| `UnifiedWorkout` | Normalized saved workout and integration model. | Yes | Keep as persistence/source-of-truth summary model. |
| `WorkoutRoute` | In-memory route model. | Yes | Pair with `UnifiedWorkout` when building processed snapshots. |
| `PersistedWorkoutRoute` | SwiftData route storage. | Yes | Keep store contract unchanged. |
| `Workout` | Legacy rich UI model. | Yes, temporarily | Do not delete until Activity Detail and Share are migrated. |
| `WorkoutGrowthInput` | Growth/comparison/share calculation input. | Yes, as adapter target initially | Eventually build it from `ProcessedWorkout`. |
| `RecoveryActivity` | Recovery calculator input. | Yes | Eventually build it from `ProcessedWorkout`. |
| `HealthKitWorkout` | HealthKit fetch DTO. | Yes | Should continue mapping to `UnifiedWorkout`, then into processed snapshot. |

## Target Model Recommendation

Recommended names:

- `ProcessedWorkout`: canonical local read model with normalized numeric values, route state, metric availability, and sport-specific interpretation.
- `WorkoutDisplaySnapshot`: optional display-ready companion or nested property containing formatted strings for Activity Detail/Profile/Share.

Recommended module location:

- `SOOM/Features/Workout/ProcessedWorkout.swift`
- `SOOM/Features/Workout/ProcessedWorkoutBuilder.swift`
- `SOOM/Features/Workout/ProcessedWorkoutDisplayFormatter.swift`

Keep the model as a value type:

- `struct ProcessedWorkout: Identifiable, Equatable`
- no SwiftData annotations
- no direct persistence responsibility
- built from source models on demand

## Required Fields

`ProcessedWorkout` should include:

- `id: UUID`
- `externalId: String?`
- `source: UnifiedDataSource`
- `workoutType: UnifiedWorkoutType`
- `startedAt: Date`
- `endedAt: Date`
- `durationSeconds: TimeInterval`
- `isExcludedFromAnalysis: Bool`
- `dataQuality: UnifiedDataQuality`
- `distanceMeters: Double?`
- `averageSpeedMetersPerSecond: Double?`
- `averagePaceSecondsPerKilometer: Double?`
- `activeEnergyKcal: Double?`
- `averageHeartRate: Double?`
- `maxHeartRate: Double?`
- `elevationGainMeters: Double?`
- `route: ProcessedWorkoutRoute?`
- `metricAvailability: [ProcessedWorkoutMetric: ProcessedWorkoutMetricState]`

Recommended support types:

- `ProcessedWorkoutMetric`: distance, duration, pace, speed, elevation, calories, averageHeartRate, maxHeartRate, power, cadence, route, splits, zones
- `ProcessedWorkoutMetricState`: measured, derived, estimated, missing, unsupported

## Optional Fields

Add only when source data exists or a consumer already needs the placeholder:

- `averagePowerWatts: Double?`
- `averageCadence: Double?`
- `steps: Int?`
- `splits: [ProcessedWorkoutSplit]`
- `samples: [ProcessedWorkoutSample]`
- `heartRateZones: [ProcessedWorkoutZone]`
- `sourceDeviceName: String?`
- `importedAt: Date?`
- `routePrivacyState`
- `courseIdentity`

Do not add persistence or external sync metadata beyond what is needed for display and mapping in v1.

## Sport-Specific Fields

### Cycling

Required interpretation:

- primary distance: meters/km
- primary duration: elapsed time
- primary movement metric: average speed
- optional elevation gain
- optional HR/calories
- optional power/cadence when streams become canonical

Display policy:

- use speed, not pace, as the primary movement metric
- show power/cadence only when measured or imported
- do not fake power, cadence, or calories for local Record workouts

### Running

Required interpretation:

- primary distance: meters/km
- primary duration: elapsed time
- primary movement metric: average pace
- optional elevation gain
- optional HR/calories/cadence/splits

Display policy:

- derive pace only when duration and distance are positive
- pace should be `missing` when distance is absent
- splits/zones should be hidden when source data is absent

### Walking

Required interpretation:

- primary distance: meters/km when available
- primary duration: elapsed time
- primary movement metric should be explicit by surface:
  - Record compact HUD: speed per current product decision
  - Activity/Profile/Share: choose one canonical default in the formatter, preferably speed for consistency with current Record direction unless product explicitly switches to pace

Display policy:

- keep `workoutType = .walking`; do not coerce walking to running
- recovery mapping should avoid run-specific language when walking support is added
- steps/cadence should remain missing until measured/imported

## Route Fields

`ProcessedWorkoutRoute` should include:

- `workoutId: UUID`
- `source: UnifiedDataSource`
- `coordinates: [WorkoutRouteCoordinate]`
- `coordinateCount: Int`
- `totalDistanceMeters: Double`
- `totalElevationGainMeters: Double?`
- `bounds: WorkoutRouteBounds?`
- `hasRenderableRoute: Bool`
- `courseIdentity: String?`

Route rules:

- route is available only when at least two valid coordinates exist
- route distance may be used as a fallback only when workout distance is missing
- route elevation may be used only when altitude data is reliable enough and documented as derived
- route privacy masking remains a share/feed concern, not a core processed-workout mutation

## Derived Metrics

The builder should centralize:

- duration minutes
- distance km
- average speed m/s and km/h
- average pace seconds/km
- display pace text
- display speed text
- route presence
- route-derived distance fallback
- route-derived elevation fallback, if accepted
- sport-specific primary metric
- missing versus unsupported status

Derivation order:

1. Prefer measured/source summary values from `UnifiedWorkout`.
2. Use route-derived values only when summary values are absent and route quality is sufficient.
3. Use calculated values from summary distance/duration only when both are positive.
4. Keep unavailable values nil and mark as missing or unsupported.

## Display-Ready Metrics

`WorkoutDisplaySnapshot` should include stable text for:

- sport title
- sport icon name
- source title
- date text
- time text
- duration text
- distance text
- primary metric label/value
- speed text
- pace text
- elevation text
- calories text
- average HR text
- max HR text
- data quality label
- route badge label
- missing metric placeholders

This avoids each screen formatting its own distance/duration/pace strings.

## Missing-Data Rules

Use explicit missing-data behavior:

- `nil` means no measured or acceptable derived value exists.
- `0` means a real zero only when zero is valid for that metric.
- Display placeholders should come from the formatter, not raw models.
- Metrics that cannot apply to a sport should be `unsupported`, not `missing`.
- Metrics not captured by local Record should remain absent rather than estimated unless a later phase explicitly adds an estimate.
- Share cards should omit optional missing metrics instead of showing misleading zeros.
- Profile aggregation should exclude missing distances from distance totals but still count valid workouts and duration.
- Recovery should lower confidence when HR/calories/effort inputs are missing.

Recommended Korean placeholders:

- distance: `거리 준비 중`
- pace/speed: `움직임 준비 중`
- HR/calories/elevation: omit in compact surfaces, `--` only in stable grids
- route: no-route fallback copy controlled by Activity Detail

## Migration And Compatibility Strategy

Do this incrementally:

1. Add `ProcessedWorkout` and builder without changing stored data.
2. Add `ProcessedWorkoutBuilder.make(from unifiedWorkout:route:)`.
3. Add `ProcessedWorkoutBuilder.make(from legacyWorkout:)` only for compatibility during migration.
4. Add tests that compare existing mapper outputs against processed values.
5. Move Activity Detail entry points to accept `ProcessedWorkout` while keeping a legacy initializer.
6. Move Share/Profile/Recovery mappers to consume `ProcessedWorkout` or builder outputs.
7. Only after all consumers are moved, decide whether legacy `Workout` should become preview/mock-only or be retired.

Compatibility requirements:

- Do not change `UnifiedWorkoutStore`.
- Do not modify SwiftData schemas in the read-model phase.
- Do not delete `Workout`.
- Do not change Record save flow except through later implementation tasks.
- Do not require production data migration for the first read-model implementation.

## Activity Detail Consumption

Recommended path:

- Add an Activity Detail adapter that receives `ProcessedWorkout`.
- Let Activity Detail use `WorkoutDisplaySnapshot` for core stat tiles, labels, primary metric, route/no-route state, and missing-data copy.
- Keep advanced sections gated by metric availability:
  - route section: `route.hasRenderableRoute`
  - sensor section: HR/zones/samples availability
  - comparison: sufficient distance/duration/sport match
  - recovery: sufficient duration plus HR/calorie confidence if available
- Keep the existing legacy `Workout` path during migration by converting it into `ProcessedWorkout`.

First Activity Detail migration target:

- Replace local `workoutGrowthInput` and `unifiedWorkoutForDraft` derivations with processed adapters so Share/Feed drafts use the same values as the detail screen.

## Profile Consumption

Recommended path:

- Add `ProfileWorkoutAggregator.aggregate(_ workouts: [ProcessedWorkout])`.
- Keep the existing `[UnifiedWorkout]` aggregator as a compatibility wrapper that maps to processed workouts first.
- Use processed metric states to avoid overconfident aggregate claims:
  - distance totals from measured or accepted derived distances
  - workout count from valid non-excluded workouts
  - bests only when required metric exists
  - walking remains walking

First Profile migration target:

- Introduce processed aggregation behind existing profile API, then update tests to verify identical output for current complete/partial data cases.

## Share Consumption

Recommended path:

- Add `WorkoutGrowthInput(processedWorkout:)` or `ShareableWorkoutCardBuilder.build(processedWorkout:route:)`.
- Keep existing `Workout` and `WorkoutGrowthInput` builders during migration.
- Use processed display text for distance, duration, pace/speed, elevation, HR, and calories.
- Use processed route availability for route-backed cards.
- Continue preview/export separation from recent Share patches.

First Share migration target:

- Build share models from `ProcessedWorkout` for Activity Detail share flow while keeping renderer unchanged.

## Recovery Consumption

Recommended path:

- Add `ProcessedWorkoutToRecoveryActivityMapper`.
- Stop mapping walking/hiking/other to run-specific semantics unless the recovery model has no alternative; if fallback remains necessary, mark it as a known limitation.
- Use metric availability to calculate confidence:
  - full confidence with HR/calories/known duration
  - lower confidence with duration-only local Record workouts
  - no false precision for training load when data is sparse

First Recovery migration target:

- Wrap current `UnifiedWorkoutToRecoveryActivityMapper` with processed input and preserve existing output where data is equivalent.

## HealthKit And External Mapping Preparation

HealthKit should still map raw `HealthKitWorkout` into `UnifiedWorkout` first. The processed builder then interprets:

- HealthKit summary distance/duration/calories/HR
- route if imported
- future HR/cadence/power streams once persisted

Future Garmin/Samsung/Google adapters should follow the same pattern:

1. raw source DTO
2. canonical stored model
3. route/stream persistence
4. `ProcessedWorkout`
5. display/analysis consumers

This prevents external integrations from adding direct UI-specific mapping paths.

## What Not To Implement Yet

Explicitly defer:

- deleting legacy `Workout`
- changing `UnifiedWorkoutStore`
- SwiftData schema migrations
- production data migration
- Garmin integration
- Samsung Health integration
- Google Health / Health Connect integration
- full HealthKit write support
- advanced chart redesign
- Share card visual polish unrelated to data correctness
- Activity Detail visual polish unrelated to data correctness
- route privacy masking changes beyond existing share/feed policy
- estimated calories/HR/power/cadence for local Record workouts

## Phased Implementation Plan

### Phase 1: Define `ProcessedWorkout` / `WorkoutDisplaySnapshot`

Deliverables:

- value types and support enums
- metric availability model
- formatter/display snapshot
- unit tests for missing data, pace/speed derivation, and sport-specific primary metrics

### Phase 2: Adapter From `UnifiedWorkout`

Deliverables:

- `ProcessedWorkoutBuilder.make(from unifiedWorkout: UnifiedWorkout, route: WorkoutRoute?)`
- tests for cycling/running/walking, route/no-route, partial data, and excluded workouts
- no changes to `UnifiedWorkoutStore`

### Phase 3: Adapter From Legacy `Workout`

Deliverables:

- `ProcessedWorkoutBuilder.make(from legacyWorkout: Workout)`
- parity tests against existing `WorkoutGrowthInput(shareableWorkout:)` and Activity Detail formatting where practical
- clear TODO that legacy adapter is transitional

### Phase 4: Move Activity Detail To Read Model

Deliverables:

- Activity Detail accepts processed workout data
- core stat tiles and route/no-route state use display snapshot
- share/feed draft derivations use processed adapters
- existing Activity Detail tests updated around data correctness, not visual polish

### Phase 5: Move Share/Profile Aggregation To Read Model

Deliverables:

- Share card builder can build from processed workout
- Profile aggregator can aggregate processed workouts
- compatibility wrappers keep existing callers working
- tests verify current behavior remains stable for existing unified workouts

### Phase 6: Prepare HealthKit/External Ingestion Mapping

Deliverables:

- HealthKit import still persists `UnifiedWorkout`, route, and later streams
- processed builder handles imported route and metric availability
- external source adapter contract documented for Garmin/Samsung/Google
- no direct Garmin/Samsung/Google implementation yet

## Recommended Next Implementation Step

Implement Phase 1 and Phase 2 only:

- Add `ProcessedWorkout`, `ProcessedWorkoutRoute`, metric availability enums, and `WorkoutDisplaySnapshot`.
- Add a builder from `UnifiedWorkout` plus optional `WorkoutRoute`.
- Add focused unit tests for Cycling, Running, Walking, no-route, missing distance, pace/speed derivation, and walking not being coerced to running.

Do not migrate screens in the first code task unless the new read model is covered by tests and the change remains small.

## Verification

This is a documentation/design plan only:

- No app code modified.
- No build run.
- No TestFlight upload run.

Required checks:

- `git diff --check`
- `git status --short`
