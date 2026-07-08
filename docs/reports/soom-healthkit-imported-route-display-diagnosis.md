# SOOM HealthKit Imported Route Display Diagnosis

Date: 2026-07-08

## Summary

Fixed the Activity Detail route display path for HealthKit-imported workouts.

HealthKit route import and persistence were already using the correct imported `UnifiedWorkout.id`. The display break was in the map-sheet rendering path: imported workouts enter `WorkoutDetailView` through a legacy `Workout` adapter whose `route` array is empty, while the persisted HealthKit route is passed separately as `detailRouteOverride`.

`WorkoutDetailView` correctly chose the map-sheet when `detailRouteOverride` existed, but `WorkoutMapSheetScaffold` and `WorkoutMapBackground` only rendered from `workout.route`. That caused imported route-backed workouts to open the map-sheet with a fallback background instead of rendering the persisted HealthKit route.

## Files Changed

- `SOOM/Features/Activity/DetailViews.swift`
- `SOOM/Features/Activity/WorkoutMapSheetScaffold.swift`
- `SOOM/Features/Activity/WorkoutMapControls.swift`
- `SOOMTests/WorkoutMapSheetRouteContextTests.swift`
- `SOOM.xcodeproj/project.pbxproj`
- `docs/reports/soom-healthkit-imported-route-display-diagnosis.md`

## Root Cause

The route was split across two representations:

- Imported HealthKit route:
  - persisted as `WorkoutRoute`
  - associated with imported `UnifiedWorkout.id`
  - loaded by `WorkoutDetailRouteContextProvider`
  - passed into `WorkoutDetailView.detailRouteOverride`
- Legacy detail workout:
  - built by `Workout(unifiedWorkout:)`
  - intentionally has `route: []`

Before the fix:

1. `UnifiedWorkoutDetailDestination` loaded `persistedRoute` by `unifiedWorkout.id`.
2. `WorkoutDetailView.detailMapRoute` resolved to `detailRouteOverride`.
3. `WorkoutDetailView` entered `WorkoutMapSheetScaffold` because `detailMapRoute != nil`.
4. `WorkoutMapSheetScaffold` initialized camera and `WorkoutMapBackground` from `workout.route`.
5. For imported HealthKit workouts, `workout.route` was empty, so the map background fell back.

This was not a HealthKit fetch, route persistence, or source-filter bug.

## Fix Applied

Added a route override path to the map-sheet renderer:

- `WorkoutDetailView` now passes `detailMapRoute` into `WorkoutMapSheetScaffold`.
- `WorkoutMapSheetScaffold` accepts `routeOverride`.
- `WorkoutMapSheetRouteContext` resolves the display route:
  - prefer a valid override with at least two coordinates
  - otherwise fall back to the existing legacy `workout.route` conversion
  - otherwise return `nil` for clean no-route fallback
- `WorkoutMapBackground` now renders the resolved route instead of rebuilding only from `workout.route`.

The existing Mapbox style URI and route map component were not changed.

## Route Fetch / Persistence / Display Behavior

HealthKit fetch:

- `HealthKitWorkoutRouteFetcher` still fetches `HKWorkoutRoute` samples and converts locations to `WorkoutRoute`.
- Empty or unavailable route data still returns `nil`.
- Route fetch failure remains non-blocking for summary import.

Persistence:

- `HealthKitWorkoutImportPipeline` still saves route data through `WorkoutRoutePersistenceStoring`.
- Imported route is associated with the imported `UnifiedWorkout.id`.
- Route source remains `.appleHealthKit`.

Display:

- Activity Detail route lookup still fetches by `UnifiedWorkout.id`.
- Imported route-backed workouts now pass the resolved `WorkoutRoute` into the map-sheet camera and background renderer.
- Record/local route-backed workouts still use the existing `workout.route` conversion when no override is present.

## No-Route Fallback Behavior

No-route HealthKit workouts are unchanged:

- if no route is persisted, `detailRouteOverride` remains `nil`
- `WorkoutDetailView` uses the standalone detail layout
- no-route fallback remains acceptable and should not show a broken or blank map

Invalid route overrides with fewer than two coordinates are ignored, so the map does not attempt to render an unusable route.

## Record Route Regression Notes

Record route behavior is preserved:

- no Record save flow code was changed
- no route persistence schema was changed
- the map-sheet route resolver falls back to legacy `Workout.route` when no override exists
- added coverage confirms a Record-style route-backed workout still resolves as `.soomLocal`

## Tests Added

`WorkoutMapSheetRouteContextTests` covers:

- HealthKit imported route override drives the map-sheet route when legacy `Workout.route` is empty
- no-route workout returns nil route and empty coordinates
- Record route-backed workout still uses legacy `Workout.route` without override
- invalid override falls back to legacy route when available

Existing related coverage remains:

- `HealthKitWorkoutImportPipelineTests` verifies imported routes are associated with imported workout ids.
- `WorkoutDetailRouteContextProviderTests` verifies persisted route lookup by workout id.
- `HealthKitImportedWorkoutSurfaceValidationTests` verifies imported route-backed workouts are route-backed at the processed model layer.

## Verification

Focused test command attempted:

```sh
xcodebuild test -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SOOMTests/WorkoutMapSheetRouteContextTests -only-testing:SOOMTests/WorkoutDetailRouteContextProviderTests -only-testing:SOOMTests/HealthKitWorkoutImportPipelineTests -only-testing:SOOMTests/HealthKitImportedWorkoutSurfaceValidationTests -quiet
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

- Passed when rerun by itself.
- First parallel attempt hit an Xcode build database lock because the generic build was running at the same time.

Requested build:

```sh
xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'
```

Result:

- Passed.

## Physical Device QA Checklist

Retest these Phase 1E items on device:

- Import a HealthKit workout that has route data.
- Open the imported workout from Activity.
- Confirm Activity Detail opens the map-sheet view.
- Confirm the route line appears on the map when Mapbox token/style are configured.
- Confirm the bottom sheet content still shows imported distance, duration, and speed/pace.
- Confirm Share card still uses the imported workout metrics and route path.
- Import or open a HealthKit workout without route data.
- Confirm no-route fallback remains clean and does not show a broken or blank map.
- Open a Record-created route-backed workout.
- Confirm Record route-backed detail still shows the existing route map.

## Phase 1E Status

HealthKit Phase 1E device QA can continue after this fix is installed on device.

The specific imported-route display finding should be retested before treating route-backed HealthKit import as passed.
