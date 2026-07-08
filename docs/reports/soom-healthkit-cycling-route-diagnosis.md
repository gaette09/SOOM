# SOOM HealthKit Cycling Route Diagnosis

Date: 2026-07-09

## Summary

Diagnosed the physical-device finding where imported HealthKit running routes display, but an imported HealthKit cycling route does not.

Code inspection did not find a cycling-specific exclusion in HealthKit route fetching, sport mapping, route persistence, `ProcessedWorkoutBuilder`, or the map-sheet route renderer:

- `HealthKitWorkoutRouteFetcher` queries `HKSeriesType.workoutRoute()` for the exact `HKWorkout`.
- The route query does not filter by running, walking, or cycling.
- `HealthKitManager` requests read access for `HKSeriesType.workoutRoute()` and cycling distance.
- `HealthKitWorkoutToUnifiedWorkoutMapper` maps `.cycling -> .cycling`.
- `WorkoutMapSheetRouteContext` can render cycling and running route overrides the same way.

The smallest safe hardening is in Activity Detail route lookup for imported HealthKit workouts. Detail previously asked for a persisted route only by `UnifiedWorkout.id`. For Apple Health imports, the HealthKit workout UUID is also stored as `externalId`; when persisted route association and stored workout identity differ across import/reimport/device state, detail can miss a valid route. The route provider now tries the stored workout id first, then falls back to the Apple Health external UUID for HealthKit imports.

If the same cycling workout still has no map after this fix, the most likely remaining explanation is that HealthKit does not expose `HKWorkoutRoute` samples for that source cycling workout. SOOM should not fake route data in that case; the no-route fallback is correct.

## Files Changed

- `SOOM/Features/Workout/WorkoutDetailRouteContextProvider.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutLibraryView.swift`
- `SOOMTests/WorkoutDetailRouteContextProviderTests.swift`
- `SOOMTests/WorkoutMapSheetRouteContextTests.swift`
- `docs/reports/soom-healthkit-cycling-route-diagnosis.md`

## Running Vs Cycling Route Path Comparison

Running path:

1. `HealthKitWorkoutFetcher` imports the running `HKWorkout` summary.
2. `HealthKitWorkoutToUnifiedWorkoutMapper` maps it to `.running`.
3. `HealthKitWorkoutImportPipeline` looks up the original `HKWorkout` by external id.
4. `HealthKitWorkoutRouteFetcher` queries route samples attached to that `HKWorkout`.
5. Route is persisted as `WorkoutRoute`.
6. Activity Detail loads the persisted route and passes it as `detailRouteOverride`.
7. `WorkoutMapSheetScaffold` renders the resolved route.

Cycling path:

1. `HealthKitWorkoutFetcher` imports the cycling `HKWorkout` summary.
2. `HealthKitWorkoutToUnifiedWorkoutMapper` maps it to `.cycling`.
3. `HealthKitWorkoutImportPipeline` uses the same original-`HKWorkout` lookup path.
4. `HealthKitWorkoutRouteFetcher` uses the same route query path.
5. Activity Detail uses the same route override and map-sheet path.

There is no code branch that intentionally drops cycling routes while preserving running routes.

## Whether Cycling Route Data Exists In HealthKit Path

The local code cannot prove whether the specific physical-device cycling workout has `HKWorkoutRoute` samples without querying that device’s Health store at runtime.

Code-level expectations:

- If HealthKit returns route samples and locations for the cycling `HKWorkout`, SOOM should persist and display them.
- If HealthKit returns no route samples for the cycling `HKWorkout`, SOOM should import the summary only and use no-route fallback.
- Some source apps/devices may write cycling distance/calories to Apple Health without writing route samples.

Device QA should inspect whether the cycling workout in Apple Health visibly has a route map and whether SOOM has route permission enabled.

## Root Cause

Confirmed code issue:

- Activity Detail route lookup for imported workouts was too narrow because it only requested `route(for: workout.id)`.
- Apple Health imports also have `externalId = HKWorkout.uuid.uuidString`.
- A route persisted under the HealthKit UUID can be missed if the stored workout id and external HealthKit UUID differ.

Not found:

- no cycling exclusion in `HealthKitWorkoutRouteFetcher`
- no cycling mapping bug
- no source filter excluding `.appleHealthKit`
- no map-sheet cycling exclusion
- no Record route dependency change

## Fix Applied

Updated `WorkoutDetailRouteContextProvider`:

- `route(for workoutId:)` still fetches by the exact workout id.
- new `route(for workout:)` first fetches by `workout.id`.
- for `.appleHealthKit` workouts, it falls back to `UUID(uuidString: workout.externalId)` when that differs from `workout.id`.

Updated `UnifiedWorkoutLibraryView`:

- row route badge and detail destination now use `route(for: UnifiedWorkout)`.

This is intentionally a lookup hardening only. It does not change route import, route persistence schema, Mapbox style, Record route behavior, Feed, Share layout, background sync, or HealthKit write behavior.

## No-Route Fallback Behavior

No-route cycling HealthKit workouts still fall back cleanly:

- if no persisted route exists by either workout id or HealthKit external UUID, detail receives no route override
- no fake route is created
- Activity Detail stays on the no-route fallback path

## Tests Added / Updated

Updated `WorkoutDetailRouteContextProviderTests`:

- HealthKit route can be found by external id when stored workout id differs.
- cycling HealthKit route uses imported workout id when available.
- running HealthKit route uses imported workout id when available.
- no-route cycling HealthKit workout returns nil.

Updated `WorkoutMapSheetRouteContextTests`:

- cycling HealthKit route override resolves as route-backed.
- running HealthKit route override resolves as route-backed.

Existing route-safe import tests continue to cover:

- cycling HealthKit route persists with imported workout id
- no-route HealthKit import remains summary-only
- route fetch failure does not fail summary import

## Verification

Focused test command attempted:

```sh
xcodebuild test -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SOOMTests/WorkoutDetailRouteContextProviderTests -only-testing:SOOMTests/WorkoutMapSheetRouteContextTests -only-testing:SOOMTests/HealthKitWorkoutImportPipelineTests -only-testing:SOOMTests/HealthKitWorkoutRouteMapperTests -quiet
```

Result:

- Tests compiled and reached test startup.
- Execution was blocked by CoreSimulator infrastructure:
  - `Failed to clone device named 'iPhone 17 Pro'.`
  - Device was allocated but stuck in creation state.
- Xcode also emitted connected-device passcode warnings during discovery.
- No test assertion failure was reported before the simulator clone failure.

Build-for-testing:

```sh
xcodebuild build-for-testing -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'
```

Result:

- Passed when run by itself.
- A parallel attempt hit Xcode’s build database lock while the generic build was running.

Requested build:

```sh
xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'
```

Result:

- Passed.

## Physical Device QA Checklist

Retest cycling route:

- Confirm the cycling workout in Apple Health visibly has a route map.
- Confirm SOOM has HealthKit route read permission.
- Import or re-import the cycling workout.
- Open the imported cycling workout from Activity.
- Confirm the Activity row route badge appears if route exists.
- Confirm Activity Detail opens map-sheet and shows the route line.
- Confirm distance/duration/speed remain correct.

Compare with running:

- Import/open a route-backed running workout.
- Confirm running route still displays.
- Confirm both running and cycling use the same route-backed map behavior.

No-route cycling:

- Import a cycling workout that has no HealthKit route.
- Confirm summary imports.
- Confirm no-route fallback remains clean.
- Confirm no fake route claim appears.

If cycling still fails:

- Capture whether Apple Health shows a route for that exact cycling workout.
- Capture whether SOOM shows the imported cycling workout source as Apple Health.
- Re-run import after deleting the previous imported cycling workout if local test data can be safely reset.
- Treat “Apple Health has no route sample for this cycling workout” as non-blocking.
- Treat “Apple Health shows a route but SOOM still has no route after this fix” as a blocker for another route-fetch instrumentation pass.

## Phase 1E Status

Cycling route QA can continue after installing this fix on device.

If the cycling source workout has no `HKWorkoutRoute` samples, Phase 1E should document it as source-data unavailable and continue no-route fallback QA.
