# SOOM Data Pipeline v1 Audit and Implementation Plan

Date: 2026-07-08

## Summary

Build 8 UI work is acceptable for broad flow verification, but SOOM now needs a data-first pass before more Activity Detail or Share polish. The current app has two parallel workout representations:

- `UnifiedWorkout`: the normalized, SwiftData-backed model used by local Record saves, HealthKit import foundations, Profile aggregation, and recovery/growth mappers.
- `Workout`: the richer legacy UI model used by Activity Detail, Share card building, route/detail presentation, and many display-specific fields such as splits, samples, zones, achievements, and AI summary.

That split is workable short-term, but it is now the central data risk. Data Pipeline v1 should make `UnifiedWorkout` plus persisted route data the stable source of truth, define sport-specific derived metrics, and provide processed presentation snapshots for Activity Detail, Profile, and Share before direct Garmin/Samsung/Google integrations.

## Files Inspected

- `SOOM/Models/Workout.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkout.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutType.swift`
- `SOOM/Features/UnifiedHealth/UnifiedDataSource.swift`
- `SOOM/Features/UnifiedHealth/UnifiedDataQuality.swift`
- `SOOM/Features/UnifiedHealth/Persistence/UnifiedWorkoutRecord.swift`
- `SOOM/Features/UnifiedHealth/Persistence/UnifiedWorkoutStore.swift`
- `SOOM/Features/UnifiedHealth/Persistence/UnifiedWorkoutPersistenceMapper.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutLibraryViewModel.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutLibraryView.swift`
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
- `docs/ops/PROJECT_MEMORY.md`
- `docs/ops/TODAY_QUEUE.md`

## Current Data Sources

| Source | Current state | Notes |
| --- | --- | --- |
| SOOM Record | Active local source for Cycling, Running, Walking. | Saves local summary and optional route. |
| SwiftData `UnifiedWorkoutRecord` | Current normalized local persistence. | Stores summary fields, source, quality, and analysis exclusion flag. |
| SwiftData `PersistedWorkoutRoute` | Current route persistence. | Stores encoded route coordinates separately from workout summary. |
| Legacy `Workout` model | Rich UI/display model. | Includes fields not stored by local Record today. |
| HealthKit import foundation | Present but still partial. | Imports workout summaries and can optionally fetch routes/streams when wired. |
| Recovery/Profile/Share mappers | Derived consumers. | Consume `UnifiedWorkout` or mapped `WorkoutGrowthInput`, but do not own canonical data. |

## Current Stored Fields

`UnifiedWorkout` currently stores:

- Identity: `id`, `externalId`
- Source: `source`
- Sport: `workoutType`
- Time: `startDate`, `endDate`, `durationSeconds`
- Summary metrics: `distanceMeters`, `activeEnergyKcal`, `averageHeartRate`, `maxHeartRate`, `averageSpeedMetersPerSecond`, `elevationGainMeters`
- Quality and analysis state: `dataQuality`, `isExcludedFromAnalysis`
- Audit timestamps: `createdAt`, `updatedAt`

`PersistedWorkoutRoute` currently stores:

- `workoutId`, `sourceRaw`
- `encodedCoordinates`
- `coordinateCount`
- `totalDistanceMeters`
- `totalElevationGain`
- `courseIdentity`
- `createdAt`, `updatedAt`

The richer legacy `Workout` model includes fields that are not consistently persisted from Record today:

- `avgPower`
- `cadence`
- `effort`
- `splits`
- `samples`
- `zones`
- `achievements`
- `aiSummary`
- detailed route points on the model itself

## Current Calculated Fields

| Area | Current calculations |
| --- | --- |
| Record save | `averageSpeedMetersPerSecond = distance / duration` when both are available. |
| Legacy `Workout` display | Formatted distance, duration, and pace text. |
| Unified to growth | Distance km, average speed km/h, pace text for running/walking/hiking. |
| Profile | Total distance/duration, active days, workout count, sport distribution, recent 90-day totals, longest ride/run/walk, best weekly distance, consistency, morning ratio, weekend long ratio. |
| Recovery preview | Maps included unified workouts to recovery inputs and estimates effort/load from duration, HR, and calories. |
| HealthKit import | Maps summary distance, calories, average HR, and average speed when available. |
| HealthKit stream foundations | Can fetch HR, cycling cadence, and cycling power samples, but these streams are not yet part of the canonical persisted workout model. |

## Current Display Surfaces

| Surface | Data path | Notes |
| --- | --- | --- |
| Record active HUD | Live session state from Record. | Not a persisted data consumer until save. |
| Record save | `RecordWorkoutSummary` to `UnifiedWorkout` plus optional route. | Saves partial local workout data. |
| Activity list/library | `UnifiedWorkoutStore` via `UnifiedWorkoutLibraryViewModel`. | Shows recent unified workouts and route badges. |
| Activity Detail | Often maps `UnifiedWorkout` into legacy `Workout`. | Rich detail UI depends on fields not guaranteed by unified storage. |
| Profile | `ProfileWorkoutAggregator` over `[UnifiedWorkout]`. | Strongest current normalized consumer. |
| Share | `ShareableWorkoutCardBuilder` from `WorkoutGrowthInput` or legacy `Workout`. | Uses distance, duration, pace/speed, elevation, HR, calories, route preview. |
| Recovery | Unified workout mapper to `RecoveryActivity`. | Several sports are coerced into run-like recovery inputs today. |

## Cycling Coverage

Currently captured from Record:

- Workout type
- Start/end/duration
- Distance when location accumulation is available
- Average speed derived from distance/duration
- Route coordinates when a route is captured

Currently stored:

- `workoutType = .cycling`
- Duration, optional distance, optional average speed
- Route in separate route persistence when available
- `dataQuality = .partial`

Currently displayed:

- Activity/Profile/Share can display distance, duration, speed/pace-derived values, route, and elevation/HR/calories only if available from source data.

Missing or incomplete:

- Calories from local Record
- Average/max HR from local Record
- Elevation gain from local Record route processing
- Power and cadence in canonical storage
- Speed stream, power stream, cadence stream, HR stream persistence
- Splits/laps/zones
- Device/source attribution beyond source enum

## Running Coverage

Currently captured from Record:

- Workout type
- Start/end/duration
- Distance when location accumulation is available
- Average speed derived from distance/duration
- Route coordinates when a route is captured

Currently stored:

- `workoutType = .running`
- Duration, optional distance, optional average speed
- Route in separate route persistence when available
- `dataQuality = .partial`

Currently displayed:

- Pace text can be derived by `UnifiedWorkoutToGrowthInputMapper` for running when distance and duration exist.
- Activity Detail can show legacy formatted pace after mapping.

Missing or incomplete:

- Calories from local Record
- Average/max HR from local Record
- Elevation gain from local Record route processing
- Running cadence
- Splits/laps
- HR zones and pace zones
- Stream samples for pace, speed, altitude, HR, cadence

## Walking Coverage

Currently captured from Record:

- Workout type
- Start/end/duration
- Distance when location accumulation is available
- Average speed derived from distance/duration
- Route coordinates when a route is captured

Currently stored:

- `workoutType = .walking`
- Duration, optional distance, optional average speed
- Route in separate route persistence when available
- `dataQuality = .partial`

Currently displayed:

- Profile aggregation explicitly supports walking for longest walk and sport distribution.
- Share/growth mapping can derive walking pace text.

Important gaps:

- Activity Detail mapping currently coerces walking into legacy `.run`.
- Recovery mapping currently coerces walking into run-like activity input.
- Local Record requirement says Walking compact HUD uses speed, while unified growth uses pace for walking/hiking. Data Pipeline v1 should define the canonical display rule per surface.
- Calories, HR, elevation, cadence/steps, and splits are missing from local Record storage.

## Swimming Support Gaps

Foundations exist:

- Legacy `Workout.Sport.swim`
- `UnifiedWorkoutType.swimming`
- HealthKit mapper supports swimming summary imports.

Missing or incomplete:

- Record mode does not currently include swimming.
- No swim-specific canonical fields for pool/open-water type, pool length, laps, stroke count, stroke rate, SWOLF, or pace per 100m.
- Route is usually absent for pool swimming and optional for open-water swimming, so no-route Activity Detail fallback needs to become first-class.
- HealthKit stream import does not yet normalize swim-specific samples.
- Profile and Share can show generic distance/duration but not swim-native metrics.

## External Integration Gaps

### Apple Health / Apple Workout

Current foundation:

- `HealthKitWorkoutImportPipeline`
- `HealthKitWorkoutToUnifiedWorkoutMapper`
- route fetching/mapping
- metric stream fetching for HR, cycling cadence, and cycling power

Gaps before production-grade import:

- Permission and onboarding flow must be verified end-to-end.
- Route and stream persistence is not integrated into the canonical data model.
- Summary-only imports are marked partial/missing, but quality reasons are not granular.
- Max HR, elevation gain, splits, zones, and workout events are not normalized.
- Deduplication is based on external ID/source and should be tested against re-import/backfill behavior.

### Garmin

No direct Garmin pipeline is present. Before adding one, SOOM needs:

- Stable canonical workout summary schema
- Route and stream persistence model
- Source-specific metadata and device attribution
- Mapping for cycling power/cadence, running cadence, elevation, laps/splits, and calories
- OAuth/backfill/sync conflict design

### Samsung Health

No direct Samsung pipeline is present. Before adding one, SOOM needs:

- A platform strategy because Samsung Health access differs by OS and may require Android/Health Connect or export/import paths.
- Canonical model that can represent Samsung workout summaries, routes, HR, calories, and sport-specific fields without UI-specific assumptions.

### Google Health / Health Connect

No direct Google/Health Connect pipeline is present. Before adding one, SOOM needs:

- A decision on whether SOOM will support Android-side Health Connect, server-side ingestion, or manual/import workflows.
- Canonical mapping for Health Connect exercise sessions, routes, speed, cadence, power, HR, calories, and metadata.
- Cross-source deduplication rules against Apple Health, Garmin, Samsung, and SOOM local workouts.

## Risks

| Risk | Impact |
| --- | --- |
| Dual model drift between `UnifiedWorkout` and legacy `Workout`. | Activity Detail, Share, and Profile can disagree about sport type or available metrics. |
| Record saves are intentionally partial. | Local workouts look real but lack HR, calories, elevation, splits, zones, and streams. |
| Route persistence is separate from summary persistence. | Consumers must coordinate two stores and handle route absence consistently. |
| Walking is coerced to running in some display/recovery paths. | Walking data may show incorrect language, effort assumptions, or sport behavior. |
| Stream data has fetchers but no stable canonical persistence. | HealthKit/Garmin-grade detail cannot be reliably reused across Activity, Profile, Share, and Recovery. |
| `UnifiedDataQuality` is too coarse for decision-making. | The app cannot explain which metrics are measured, estimated, missing, or imported. |
| Profile/recovery outputs can overstate confidence from partial data. | User-facing insights may appear more precise than the data supports. |
| External integrations before local normalization would multiply mapping bugs. | Garmin/Samsung/Google work would harden unstable assumptions. |

## Recommended Data Pipeline v1 Scope

Data Pipeline v1 should be conservative and local-first:

- Make `UnifiedWorkout` plus persisted route the canonical source for saved workouts.
- Add a processed workout snapshot layer for display surfaces instead of letting each surface derive metrics differently.
- Define sport-specific required, optional, measured, estimated, and missing metrics for Cycling, Running, and Walking.
- Normalize route-derived values such as route distance and elevation gain when the route exists.
- Keep missing fields nil or explicit placeholders rather than inventing precision.
- Preserve source attribution and data quality at a metric level where practical.
- Make Activity Detail, Profile, Share, and Recovery consume the same processed metric decisions.
- Treat HealthKit as the first external-read integration, but only after the local canonical model and processed snapshots are stable.

## Implementation Plan

### Phase 1: Local Workout Data Normalization

Goal: make locally recorded workouts reliable and explicit.

Recommended work:

- Define a `ProcessedWorkout` or `WorkoutDataSnapshot` read model derived from `UnifiedWorkout` plus optional `WorkoutRoute`.
- Centralize sport display naming, primary metric selection, pace/speed choice, and missing-value placeholders.
- Reconcile legacy `Workout` mapping so walking remains walking where the UI needs walking semantics.
- Record measured versus derived fields from local Record saves:
  - measured: start/end/duration, captured route, accumulated distance when available
  - derived: average speed, pace text, route bounds
  - missing: calories, HR, power, cadence, zones, splits
- Add route-derived elevation gain if route altitude data is reliable enough; otherwise keep it nil.
- Keep `dataQuality = .partial` for local Record saves unless a metric-level quality model is added.

### Phase 2: Sport-Specific Metric Calculation

Goal: standardize Cycling, Running, and Walking metrics before new integrations.

Recommended work:

- Cycling:
  - primary: distance, elapsed time, average speed
  - optional: elevation, calories, HR, power, cadence
- Running:
  - primary: distance, elapsed time, average pace
  - optional: elevation, calories, HR, cadence, splits
- Walking:
  - primary: distance, elapsed time, average speed or pace by surface
  - optional: elevation, calories, HR, steps/cadence
- Define calculation helpers for:
  - average speed
  - average pace
  - active duration fallback
  - route distance fallback
  - elevation gain fallback
  - placeholder policy for missing metrics
- Avoid sport-specific assumptions inside UI views.

### Phase 3: Processed Aggregates for Profile/Activity

Goal: make Profile and Activity display the same truth.

Recommended work:

- Feed Profile aggregation from processed workouts or a shared metric service.
- Add aggregate quality notes so Profile can avoid overconfident claims from partial data.
- Provide Activity Detail a processed detail model with stable sections:
  - route availability
  - core metrics
  - recovery-impact eligibility
  - comparison eligibility
  - chart/zone availability
- Provide Share the same processed metric text used elsewhere.

### Phase 4: HealthKit Read Integration

Goal: integrate Apple Health after local normalization is stable.

Recommended work:

- Verify HealthKit authorization and import UX.
- Import HealthKit summaries into `UnifiedWorkout` with idempotent `externalId + source` upsert.
- Persist HealthKit routes through the existing route store.
- Decide how to persist HR/cadence/power streams before showing zones or detailed charts.
- Map HealthKit quality reasons:
  - summary-only
  - route-present
  - HR-present
  - power/cadence-present
  - calories-present
- Add import tests around deduplication, re-import, partial data, and no-route workouts.

### Phase 5: External Platform Integrations

Goal: add Garmin/Samsung/Google only after SOOM can represent local and Apple Health data correctly.

Recommended work:

- Define integration contracts for:
  - source identity
  - external workout ID
  - sport type mapping
  - route mapping
  - stream mapping
  - deduplication and conflict resolution
  - backfill and incremental sync
- Add Garmin only after cycling/running power/cadence/elevation/lap semantics are supported.
- Add Samsung/Google only after the platform strategy is explicit.
- Keep source adapters thin; all final calculations should use SOOM’s canonical processing layer.

## Explicit Deferrals

The following should remain deferred until Data Pipeline v1 stabilizes:

- Further Share card UI polish
- Activity Detail visual polish
- Advanced chart redesign
- Direct Garmin integration
- Direct Samsung Health integration
- Direct Google Health / Health Connect integration

## Recommended Next Implementation Step

Start with Phase 1: local workout data normalization.

The first code task should define a processed workout read model or metric service that combines `UnifiedWorkout` and optional `WorkoutRoute`, then update Activity Detail/Profile/Share consumers to use that shared metric decision layer incrementally. This gives SOOM a stable local truth before importing richer external data.

## Verification

No app code was modified. No build or TestFlight upload was run for this documentation-only audit.

Required verification for this report:

- `git diff --check`
- `git status --short`
