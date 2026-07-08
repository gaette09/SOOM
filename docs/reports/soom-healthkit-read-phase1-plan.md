# SOOM HealthKit Read Integration Phase 1 Plan

Date: 2026-07-08

## Summary

SOOM should treat HealthKit Read Integration Phase 1 as a hardening and connection plan for the existing read-only HealthKit foundation, not as a new integration from scratch.

The current app already has the important pieces:

- HealthKit read permission manager and usage copy.
- `HealthKitWorkout` DTO and recent workout fetcher.
- `HealthKitWorkout -> UnifiedWorkout` mapper.
- Manual `HealthKitWorkoutImportPipeline` into `UnifiedWorkoutStore`.
- Route lookup/fetch/map support for `HKWorkoutRoute`.
- Detail-time metric stream fetch support for heart rate, cycling cadence, and cycling power.
- `ProcessedWorkout` read model used by Activity Detail, Share, Profile aggregation, and Recovery preview paths.

Recommended Phase 1 scope: keep import explicit, read-only, local-first, and summary-first. Import Apple Health workouts into `UnifiedWorkoutStore`, then convert them through `ProcessedWorkoutBuilder` for display and analysis surfaces. Do not enable write-back, background sync, direct Garmin/Samsung/Google integrations, or advanced sampled stream persistence in this phase.

## Files Inspected

- `SOOM/Info.plist`
- `SOOM/Features/HealthKit/HealthKitManager.swift`
- `SOOM/Features/HealthKit/HealthKitWorkout.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutFetcher.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutToUnifiedWorkoutMapper.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutImportPipeline.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutImportViewModel.swift`
- `SOOM/Features/HealthKit/HealthKitSettingsViewModel.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutLookupProvider.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutRouteFetcher.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutRouteMapper.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutMetricSample.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutMetricMapper.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutMetricStreamFetcher.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkout.swift`
- `SOOM/Features/UnifiedHealth/Persistence/UnifiedWorkoutStore.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutDeduplicationEngine.swift`
- `SOOM/Features/Activity/RecordWorkoutSaveFlow.swift`
- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOM/Features/Workout/ProcessedWorkout.swift`
- `SOOM/Features/Workout/ProcessedWorkoutBuilder.swift`
- `SOOM/Features/Workout/ShareableWorkoutCardBuilder.swift`
- `SOOM/Features/Settings/ProfileWorkoutAggregation.swift`
- `SOOM/Features/Recovery/ProcessedWorkoutToRecoveryActivityMapper.swift`
- `SOOM/Features/Recovery/UnifiedWorkoutRecoveryPreviewProvider.swift`
- `docs/SOOM_PERMISSION_MATRIX.md`
- `docs/SOOM_HEALTHKIT_INTEGRATION_PLAN.md`
- `docs/SOOM_UNIFIED_HEALTH_DATA_SOURCE.md`
- `docs/reports/soom-processed-workout-read-model-plan.md`
- `docs/ops/TODAY_QUEUE.md`

## Current HealthKit Foundation Status

Production foundation exists:

- `HealthKitManager` requests read access only via `toShare: []`.
- Current read types include workouts, workout routes, heart rate, active energy, walking/running distance, cycling distance, and iOS 17 cycling cadence/power.
- `HealthKitWorkoutFetcher` reads recent `HKWorkout` samples and maps them into `HealthKitWorkout`.
- `HealthKitWorkoutToUnifiedWorkoutMapper` maps HealthKit workouts to `UnifiedWorkout` with `source = .appleHealthKit` and `externalId = HKWorkout.uuid.uuidString`.
- `HealthKitWorkoutImportPipeline` imports recent workouts into `UnifiedWorkoutStore`.
- `SwiftDataUnifiedWorkoutStore` upserts by `externalId + source`, which prevents exact reimport duplicates.
- `HealthKitWorkoutRouteFetcher` and mapper can convert `HKWorkoutRoute` into `WorkoutRoute`.
- Metric stream fetchers can read heart rate, cycling cadence, and cycling power for a specific `HKWorkout`, but this should stay detail-time/interpretive in Phase 1.

Important gap:

- The current `HealthKitWorkout` summary DTO does not populate average heart rate from samples.
- Elevation is not stored on `UnifiedWorkout` from HealthKit summary unless a route is fetched and processed later.
- Power/cadence streams are not part of the stored summary model.
- `NSHealthUpdateUsageDescription` still exists in `Info.plist`, but the runtime manager does not request write permissions. Phase 1 should not add any write request.

## Phase 1 Recommendation

Build Phase 1 around this path:

`HKWorkout -> HealthKitWorkout -> UnifiedWorkout -> UnifiedWorkoutStore -> ProcessedWorkoutBuilder -> Activity/Profile/Share/Recovery preview`

Use HealthKit as a source of imported workout summaries. Do not make HealthKit the live source for core screens, and do not let HealthKit APIs leak into Activity Detail, Share, Profile, or Recovery beyond existing detail-time lookup boundaries.

Phase 1 should read first:

- Workout identity: HealthKit UUID as `externalId`.
- Sport type.
- Start date and end date.
- Duration.
- Total distance.
- Active energy.
- Route availability when safe and user-permitted.
- Average heart rate only if existing stream foundation can compute it safely without changing app behavior.

Phase 1 should avoid:

- Write-back to HealthKit.
- Background sync.
- Automatic import on app launch.
- Garmin direct integration.
- Samsung Health integration.
- Google Health / Health Connect integration.
- Advanced power/cadence stream persistence.
- Route snapping, smoothing, simplification, or matching.
- UI polish unrelated to data import.

## Required HealthKit Permissions

Keep the request user-initiated and read-only.

Required for Phase 1:

- `HKWorkoutType.workoutType()`: read workouts.
- `HKQuantityTypeIdentifierDistanceWalkingRunning`: read running/walking distance where present.
- `HKQuantityTypeIdentifierDistanceCycling`: read cycling distance where present.
- `HKQuantityTypeIdentifierActiveEnergyBurned`: read calories/active energy where present.

Optional in Phase 1 when already supported:

- `HKQuantityTypeIdentifierHeartRate`: compute average heart rate for imported workouts or detail-time zones.
- `HKSeriesType.workoutRoute()`: fetch workout route if available.

Defer as stored import data:

- `HKQuantityTypeIdentifierCyclingCadence`
- `HKQuantityTypeIdentifierCyclingPower`

These can remain detail-time stream inputs because the current summary/read model does not persist cadence or power.

## Mapping Contract

### HealthKit To SOOM

| HealthKit | SOOM target | Phase 1 rule |
| --- | --- | --- |
| `HKWorkout.uuid` | `UnifiedWorkout.id`, `externalId` | Use UUID for stable HealthKit identity. |
| `workoutActivityType` | `UnifiedWorkoutType` | Map cycling/running/walking directly; swimming allowed but not prioritized. |
| `startDate` | `startDate` / `startedAt` | Preserve exactly. |
| `endDate` | `endDate` / `endedAt` | Preserve exactly. |
| `duration` | `durationSeconds` | Clamp negative values to 0 in mapper/builder. |
| `totalDistance` | `distanceMeters` | Preserve positive meters; nil when absent or invalid. |
| `totalEnergyBurned` | `activeEnergyKcal` | Preserve positive kcal; nil when absent or invalid. |
| heart rate samples | `averageHeartRate` | Optional Phase 1 enhancement only if computed safely from attached samples. |
| route samples | `WorkoutRoute` / `ProcessedWorkoutRoute` | Persist route opportunistically; failure must not fail workout import. |
| cadence/power samples | detail-time zone summaries | Keep out of stored summary in Phase 1. |

### UnifiedWorkout To ProcessedWorkout

`ProcessedWorkoutBuilder` is the import interpretation layer:

- Measured HealthKit distance remains measured.
- If distance is missing but a renderable route exists, distance can be derived from route.
- Speed can be measured from `UnifiedWorkout.averageSpeedMetersPerSecond` or derived from distance/duration.
- Pace is derived only for running/hiking when duration and distance are positive.
- Calories, average HR, max HR, and elevation remain measured only when source data exists.
- Missing metrics must remain `.missing` or `.unsupported`, not zero-filled.

## Sport Mapping

Cycling:

- `HKWorkoutActivityType.cycling -> .cycling`.
- Primary metric: speed.
- Required Phase 1 metrics: start/end, duration, distance, calories when present.
- Optional: route, elevation from route.
- Defer stored power/cadence summaries until the read model has fields and tests.

Running:

- `HKWorkoutActivityType.running -> .running`.
- Primary metric: pace.
- Required Phase 1 metrics: start/end, duration, distance, calories when present.
- Optional: heart rate, route, route-derived elevation.
- Cadence stays deferred unless existing stream support is expanded deliberately.

Walking:

- `HKWorkoutActivityType.walking -> .walking`.
- Keep walking as walking; do not coerce to running for Activity/Profile/Share.
- Primary metric should follow `ProcessedWorkoutBuilder` current behavior: speed.
- Recovery currently maps walking into run-like recovery input; keep that as an explicit current limitation until Recovery taxonomy supports walking.

Swimming later:

- `HKWorkoutActivityType.swimming -> .swimming`.
- Defer Phase 1 validation unless existing HealthKit samples are simple and reliable.
- Route is usually not expected.
- Distance/duration/calories can map later, but stroke/lap/pool metrics are out of scope.

Other:

- Map to `.other`.
- Import only if summary data is valid and user can exclude from analysis if needed.

## Metric Mapping

Distance:

- Use `HKWorkout.totalDistance` when positive.
- Fall back to route-derived distance only through `ProcessedWorkoutBuilder` when a route is available.
- Missing distance is valid for time-only workouts.

Duration:

- Use `HKWorkout.duration`.
- Treat zero/negative duration as missing/invalid for analysis, but do not crash import.

Start/end date:

- Preserve HealthKit dates.
- Use them for sorting, duplicate detection, profile active days, and trend windows.

Calories:

- Use `totalEnergyBurned` as active energy kcal when positive.
- Missing calories should remain nil, not 0.

Heart rate:

- Current DTO has `averageHeartRate` but does not populate it from `HKWorkout`.
- Phase 1 may add average HR only if computed from attached heart rate samples with tests and without broad stream persistence.
- Otherwise keep it missing and let detail-time zone cards use the existing stream path.

Elevation:

- Prefer route-derived elevation only when `HKWorkoutRoute` locations are available.
- Do not snap, smooth, or infer elevation beyond current mapper behavior.
- Missing elevation is expected.

Route:

- Fetch only after a workout import succeeds.
- Persist `WorkoutRoute` when route permission/data exists.
- Route fetch failure must be ignored so workout import remains successful.

Cadence/power:

- Existing fetchers can read cycling cadence and power on supported OS versions.
- Keep them as detail-time zone inputs in Phase 1.
- Defer summary persistence, averages, PRs, load calculations, and power/cadence share display.

Moving time:

- Not available in the current model.
- Defer until a clear definition exists for HealthKit vs SOOM local vs Garmin.

Sampled streams:

- Heart rate/cadence/power streams should not be bulk-imported or stored in Phase 1.
- Use existing detail-time fetch only when an imported HealthKit workout detail needs zone context.

## Missing-Data Rules

- Missing means nil plus `ProcessedWorkoutMetricState.missing`, not `0`.
- Unsupported means the sport/source does not support the metric, e.g. power for walking.
- Derived means SOOM calculated the metric from available fields, e.g. speed from distance/duration.
- Estimated should be reserved for explicit estimation logic, not for absent HealthKit data.
- UI and share surfaces should use `ProcessedWorkout.display` placeholders instead of custom per-surface fallbacks.
- Recovery preview should keep low-confidence calculations clearly preview-only when HR/calories/distance are missing.

## Duplicate Prevention Strategy

Phase 1 duplicate rules:

- Exact reimport prevention: rely on `SwiftDataUnifiedWorkoutStore` upsert by `externalId + source`.
- Cross-source candidate detection: use `UnifiedWorkoutDeduplicationEngine` before analysis selection, not during raw import, unless the implementation phase explicitly wires it.
- Do not delete duplicates automatically.
- Do not merge sources automatically.
- Keep `isExcludedFromAnalysis` as the user-controllable escape hatch for imported duplicates.

Recommended source priority for analysis:

1. SOOM local/manual workout when it overlaps a HealthKit workout created from the same real session.
2. Garmin original in a future phase if Garmin direct integration exists.
3. Apple HealthKit imported workout.
4. Samsung/Google/Health Connect future sources.

This matches the current engine preference where `.soomLocal` ranks above `.appleHealthKit`.

## Local Vs HealthKit Source Priority

SOOM local Record workouts should remain the primary source for sessions recorded in SOOM because they preserve app-specific route capture, share context, and user intent.

HealthKit should fill gaps:

- Apple Watch workouts not recorded in SOOM.
- Historical workouts the user wants SOOM to analyze.
- Workouts from other apps that appear in Apple Health.

When local and HealthKit workouts overlap:

- Keep both records at import time.
- Mark duplicate candidates during analysis/library review.
- Prefer local for official analysis unless the user excludes it or chooses the HealthKit version later.

## Privacy And Permission UX

Policy:

- Ask only after an explicit HealthKit connect/import action.
- Explain that SOOM reads workout data to improve activity analysis and recovery context.
- Do not prompt on launch, tab entry, Record save, or Recovery open.
- Keep local-first behavior if permission is denied or restricted.
- Do not upload HealthKit-derived workouts to a server in Phase 1.
- Do not request write permissions in Phase 1.

UX copy should avoid:

- Medical diagnosis language.
- Claims that all metrics are available.
- Claims that imported data is automatically official.

UX copy should include:

- Read-only import.
- User control.
- Local storage.
- Missing-data transparency.
- Ability to exclude imported workouts from analysis.

## Test Strategy

Unit tests:

- `HealthKitWorkoutToUnifiedWorkoutMapper`
  - cycling/running/walking mapping.
  - calories/distance missing and invalid values.
  - average speed derived only when distance and duration are valid.
  - `externalId` equals HealthKit UUID string.
- `ProcessedWorkoutBuilder`
  - HealthKit summary with distance/duration/calories.
  - route-derived distance/elevation fallback.
  - metric availability states for missing HR/elevation/power/cadence.
- `SwiftDataUnifiedWorkoutStore`
  - reimport with same `externalId + source` upserts instead of duplicating.
- `UnifiedWorkoutDeduplicationEngine`
  - SOOM local vs HealthKit overlap marks candidate and prefers SOOM local.
- `HealthKitWorkoutImportPipeline`
  - fetch failure is contained.
  - empty fetch succeeds with zero imports.
  - route fetch failure does not fail workout import.

Integration/manual QA:

- Device with HealthKit available and permission granted.
- Device/simulator path where HealthKit is unavailable.
- Permission denied/restricted path.
- Manual import of recent cycling, running, and walking workouts.
- Re-run import and confirm no exact duplicate count increase.
- Open imported workout detail and confirm missing streams do not break UI.
- Confirm Profile, Activity Detail, Share, and Recovery preview consume processed data without source-specific crashes.

No Phase 1 tests should require real HealthKit access in CI; use fake fetchers/managers for automated coverage.

## Implementation Phases

Phase 0: Planning and audit. This document.

- Confirm existing HealthKit/read-model foundation.
- Define Phase 1 scope and deferrals.
- Do not change app code.

Phase 1A: Read-only summary import hardening.

- Keep `HealthKitWorkoutFetcher -> HealthKitWorkoutToUnifiedWorkoutMapper -> UnifiedWorkoutStore`.
- Confirm imported workouts convert cleanly through `ProcessedWorkoutBuilder`.
- Add tests for cycling/running/walking summary mapping and missing data.

Phase 1B: Duplicate and source-priority guardrails.

- Use exact `externalId + source` upsert as the first duplicate defense.
- Add or verify tests for local-vs-HealthKit overlap using `UnifiedWorkoutDeduplicationEngine`.
- Keep auto-merge/delete out of scope.

Phase 1C: Route-safe import.

- Keep route persistence optional.
- Confirm route fetch failures do not block workout import.
- Use route-derived distance/elevation only through `ProcessedWorkoutBuilder`.
- Defer route smoothing/snapping.

Phase 1D: Surface validation through `ProcessedWorkout`.

- Validate imported workouts in Activity Detail, Share, Profile aggregation, and Recovery preview.
- Keep official Recovery provider unchanged unless a later task explicitly switches it.
- Keep HealthKit-specific lookups contained to detail-time stream/zone context.

Phase 1E: Permission and privacy QA.

- Verify no HealthKit prompt appears on launch, Record entry, Record save, Profile, Share, or Recovery open.
- Verify prompt only appears from explicit HealthKit connect/import action.
- Verify denial keeps SOOM local workflows usable.

Future Phase 2:

- Consider average heart rate summary computation from samples.
- Consider imported workout library duplicate review UX.
- Consider official Recovery source switch only after duplicate handling and trust copy are ready.

Future Phase 3:

- Consider sampled stream persistence and advanced metrics.
- Consider Garmin direct integration.
- Consider cloud/user ownership migration only after separate consent and sync design.

## Explicit Deferrals

- HealthKit write.
- Background sync.
- Automatic HealthKit import.
- Garmin direct integration.
- Samsung Health integration.
- Google Health / Health Connect integration.
- Advanced power/cadence stream persistence.
- Route snapping/smoothing.
- Moving time derivation.
- Full stream/lap/split storage.
- UI polish unrelated to data import.
- Official Recovery provider switch.
- Server upload or cloud sync of HealthKit-derived records.

## Risks

Permissions:

- HealthKit authorization success does not prove every requested type was granted. UX and import code must tolerate partial access.

Duplicate workouts:

- Apple Health can contain workouts from Apple Watch, Garmin sync, and third-party apps. Exact upsert is not enough for cross-source duplicates.

Partial data availability:

- Many workouts will lack HR, calories, route, elevation, cadence, or power. SOOM must show missing data transparently.

Route availability:

- `HKWorkoutRoute` may be absent even for outdoor workouts, and route permission can differ from workout permission.

Source conflicts:

- SOOM local and HealthKit imports can represent the same real workout. Analysis should prefer local until user review or a clearer source policy exists.

User trust/privacy:

- Health data is sensitive. The app must avoid surprise prompts, server upload assumptions, and overconfident interpretations.

## Acceptance Criteria For Phase 1 Implementation

- Import remains manual and read-only.
- No HealthKit write permission is requested.
- Cycling/running/walking workouts import into `UnifiedWorkoutStore`.
- Imported workouts convert into `ProcessedWorkout`.
- Missing HR/cadence/calories/elevation/power/moving time/sampled streams are represented as missing/deferred, not fake data.
- Exact reimport does not duplicate records.
- Cross-source duplicates are detectable or explicitly excluded from automatic resolution.
- Profile, Activity Detail, Share, and Recovery preview can consume imported workouts through existing read-model paths.
- Denied or unavailable HealthKit does not block local Record workouts.
