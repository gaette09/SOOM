# SOOM HealthKit Read Phase 1A Summary Import

Date: 2026-07-08

## Summary

Implemented HealthKit Read Phase 1A summary import hardening for the existing manual, read-only, local-first path:

`HealthKitWorkout -> UnifiedWorkout -> UnifiedWorkoutStore -> ProcessedWorkoutBuilder`

No HealthKit write path, background sync, third-party connector, route smoothing, sampled stream persistence, build-number bump, or TestFlight upload was added.

## Files Changed

- `SOOM/Features/HealthKit/HealthKitWorkoutToUnifiedWorkoutMapper.swift`
- `SOOMTests/HealthKitWorkoutToUnifiedWorkoutMapperTests.swift`
- `SOOMTests/HealthKitWorkoutImportPipelineTests.swift`
- `docs/reports/soom-healthkit-read-phase1a-summary-import.md`

## Current HealthKit Foundation Status

- `HealthKitManager` remains read-only at runtime with `toShare: []`.
- `HealthKitWorkoutFetcher` still fetches recent `HKWorkout` samples manually.
- `HealthKitWorkout` continues to represent summary fields: sport, start/end, duration, distance, average heart rate placeholder, and calories.
- `HealthKitWorkoutToUnifiedWorkoutMapper` remains the summary bridge into `UnifiedWorkout`.
- `HealthKitWorkoutImportPipeline` still saves mapped workouts through `UnifiedWorkoutStore`.
- `SwiftDataUnifiedWorkoutStore` already upserts by `externalId + source`, so exact HealthKit reimport does not create a second stored record.

## Imported Fields

Phase 1A preserves these summary fields when present and valid:

- Stable HealthKit identifier: `HealthKitWorkout.id.uuidString` as `UnifiedWorkout.externalId`
- Source: `.appleHealthKit`
- Sport type: cycling, running, walking, swimming, other
- Start date
- End date
- Duration seconds
- Distance meters
- Active energy kcal
- Average heart rate if present on the DTO
- Derived average speed when distance and duration are valid
- Data quality as `.partial` when at least one positive summary metric exists, otherwise `.missing`

## Hardened Missing-Data Behavior

The mapper now treats zero and negative optional summary metrics as missing:

- `distanceMeters == nil` when source distance is `nil`, `0`, or negative.
- `activeEnergyKcal == nil` when source calories are `nil`, `0`, or negative.
- `averageHeartRate == nil` when source heart rate is `nil`, `0`, or negative.
- `averageSpeedMetersPerSecond == nil` unless positive distance and positive duration exist.

This keeps imported HealthKit data aligned with `ProcessedWorkoutBuilder`, which uses nil plus metric availability states instead of zero-filled sensor values.

## Missing Fields And Deferrals

Still missing/deferred in Phase 1A:

- Average heart rate computation from HealthKit samples.
- Max heart rate.
- Elevation summary unless a route is separately fetched and processed.
- Moving time.
- Cadence and power summary persistence.
- Full sampled stream persistence.
- Route smoothing/snapping.
- HealthKit write-back.
- Background HealthKit sync.
- Garmin, Samsung Health, Google Health, or Health Connect integrations.

## Duplicate Handling

Minimal safe duplicate guardrails are already present:

- Exact reimport: `UnifiedWorkoutStore` upserts by `externalId + source`.
- HealthKit identity: mapper preserves `HealthKitWorkout.id.uuidString` as `externalId`.

Broader duplicate handling remains deferred:

- Cross-source local-vs-HealthKit duplicate resolution is not applied during raw import.
- No automatic merge or delete was added.
- Future Phase 1B should wire or validate `UnifiedWorkoutDeduplicationEngine` before analysis selection, with SOOM local workouts preferred over matching HealthKit imports.

## ProcessedWorkout Compatibility

Added focused coverage that imported HealthKit workouts can become `ProcessedWorkout` values:

- Imported cycling workouts use speed as the primary metric.
- Imported walking workouts stay `.walking` and use speed as the primary metric.
- Missing calories and heart rate remain missing in metric availability.
- HealthKit source and external identifier are preserved through the processed read model.

## Verification

Focused test command attempted:

```sh
xcodebuild test -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SOOMTests/HealthKitWorkoutToUnifiedWorkoutMapperTests -only-testing:SOOMTests/HealthKitWorkoutImportPipelineTests -only-testing:SOOMTests/ProcessedWorkoutBuilderTests -quiet
```

Result:

- Build/compile reached test startup.
- Test execution was blocked by CoreSimulator infrastructure:
  - `Failed to clone device named 'iPhone 17 Pro'.`
  - Device was allocated but stuck in creation state.
- No test assertion failure was reported before the simulator clone failure.

Requested build command:

```sh
xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'
```

Result:

- Passed.
- Existing warnings remain:
  - `totalEnergyBurned` deprecation in `HealthKitWorkout`.
  - non-Sendable capture warning in `HealthKitWorkoutMetricStreamFetcher`.

## Next Recommended Phase

Phase 1B: duplicate and source-priority guardrails.

Recommended work:

- Add focused tests for SOOM local vs Apple HealthKit overlap.
- Confirm `UnifiedWorkoutDeduplicationEngine` prefers SOOM local for same-session candidates.
- Keep raw import non-destructive.
- Decide where duplicate candidates should be applied before Profile, Growth, Share, and Recovery preview analysis.
