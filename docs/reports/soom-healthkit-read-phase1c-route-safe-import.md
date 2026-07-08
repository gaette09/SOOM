# SOOM HealthKit Read Phase 1C Route-Safe Import

Date: 2026-07-08

## Summary

Implemented HealthKit Read Phase 1C route-safe import hardening for the existing manual, read-only HealthKit import path.

The path remains:

`HealthKitWorkout -> UnifiedWorkout -> UnifiedWorkoutStore -> optional WorkoutRoute -> ProcessedWorkoutBuilder`

Route import is optional and non-blocking. A HealthKit workout without route data still imports successfully, and route fetch or route persistence failures do not fail the workout summary import.

## Files Changed

- `SOOM/Features/HealthKit/HealthKitWorkoutImportPipeline.swift`
- `SOOMTests/HealthKitWorkoutImportPipelineTests.swift`
- `docs/reports/soom-healthkit-read-phase1c-route-safe-import.md`

## Route Import Strategy

Existing foundation used:

- `HealthKitWorkoutRouteFetcher` fetches `HKWorkoutRoute` samples for an `HKWorkout`.
- `HealthKitWorkoutRouteMapper` maps HealthKit route locations into `WorkoutRoute`.
- `WorkoutRoute` stores coordinates, distance, elevation, bounds, source, and `workoutId`.
- `SwiftDataWorkoutRoutePersistenceStore` persists route coordinates by `workoutId`.
- `ProcessedWorkoutBuilder` accepts an optional `WorkoutRoute` and derives route state, distance, and elevation when summary fields are missing.

Phase 1C hardening:

- The import pipeline still saves the `UnifiedWorkout` summary first.
- Route lookup/fetch/persistence runs only for imported Apple HealthKit workouts that were not skipped by duplicate guardrails.
- Any fetched route is associated with the imported `UnifiedWorkout.id` and `UnifiedWorkout.source` before saving.
- Route fetch returning `nil` is treated as normal no-route behavior.
- Route fetch throwing an error is ignored after summary import succeeds.
- Route persistence throwing an error is ignored after summary import succeeds.

## Optional And Non-Blocking Behavior

The import flow does not require route dependencies:

- If no route lookup provider, route fetcher, or route store is injected, summary import still works.
- If a HealthKit workout lookup fails, route import is skipped.
- If no `HKWorkoutRoute` exists, route import is skipped.
- If route save fails, the summary import result remains successful.

No background sync, HealthKit write, third-party source, sampled stream persistence, route smoothing, or route snapping was added.

## No-Route Behavior

Imported no-route workouts continue through the normal processed read model:

- `ProcessedWorkout.route == nil`
- route metric availability is `.missing`
- summary distance remains measured when HealthKit distance exists
- display falls back to the existing no-route/fallback UI path

## Route Failure Behavior

Route failures are contained:

- Route fetch errors do not change `savedCount`.
- Route persistence errors do not change `savedCount`.
- No failed route creates a failed workout import result.
- Skipped duplicate HealthKit workouts do not attempt route persistence.

## ProcessedWorkout Compatibility

Added focused coverage that an imported HealthKit workout with a saved route can build a `ProcessedWorkout` with:

- `source == .appleHealthKit`
- renderable route
- route coordinate count
- route-derived distance when summary distance is missing
- route-derived elevation when available
- `.measured` route availability
- `.derived` distance/elevation availability when those values came from route

This keeps Activity Detail and Share compatible with existing route-aware `ProcessedWorkoutBuilder` and route preview paths without adding UI work.

## Limitations

- Route import still depends on HealthKit route availability and user-granted route read permission.
- Route lookup uses `UnifiedWorkout.externalId` as the original HealthKit workout UUID.
- No route smoothing, snapping, simplification, privacy masking changes, or route matching was added.
- No sampled stream persistence was added beyond optional route coordinates.
- No route-linked duplicate review UI was added.
- Imported routes are local-first and are not uploaded to a server.

## Tests Added

Focused tests cover:

- HealthKit workout with route imports summary and route.
- Fetched route is associated with the imported workout before saving.
- Imported route-backed workout builds a `ProcessedWorkout` with route-derived fields.
- HealthKit workout without route imports summary only.
- Route fetch failure still imports workout summary.
- Route persistence failure still imports workout summary.
- Duplicate-skipped HealthKit workout does not persist route.

Existing related coverage remains:

- `HealthKitWorkoutRouteMapperTests` covers coordinate, bounds, distance, timestamp, and elevation mapping.
- `WorkoutRoutePersistenceStoreTests` covers SwiftData route save/fetch/upsert/delete behavior.
- `ProcessedWorkoutBuilderTests` covers route-derived distance/elevation/read-model compatibility.

## Verification

Focused test command attempted:

```sh
xcodebuild test -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SOOMTests/HealthKitWorkoutImportPipelineTests -only-testing:SOOMTests/HealthKitWorkoutRouteMapperTests -only-testing:SOOMTests/WorkoutRoutePersistenceStoreTests -only-testing:SOOMTests/ProcessedWorkoutBuilderTests -quiet
```

Result:

- Tests compiled and reached test startup.
- Execution was blocked by CoreSimulator infrastructure:
  - `Failed to clone device named 'iPhone 17 Pro'.`
  - Device was allocated but stuck in creation state.
- No test assertion failure was reported before the simulator clone failure.

Requested build command:

```sh
xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'
```

Result:

- Passed.

## Next Recommended Phase

Phase 1D: surface validation through `ProcessedWorkout`.

Recommended work:

- Validate imported HealthKit workouts in Activity Detail, Share, Profile aggregation, and Recovery preview.
- Keep official Recovery provider unchanged unless a later task explicitly switches it.
- Keep HealthKit-specific lookups contained to detail-time stream/zone context.
- Continue deferring HealthKit write, background sync, route smoothing/snapping, Garmin/Samsung/Google integrations, and sampled stream persistence.
