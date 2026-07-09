# SOOM GPX Import V1 Attachment Service

Date: 2026-07-09

## Summary

Implemented GPX Import v1 Phase 2: a service that parses a GPX file and attaches the resulting route to an existing Apple HealthKit imported workout.

This phase is service-only:

- No file picker UI.
- No Activity Detail UI changes.
- No HealthKit import behavior changes.
- No duplicate workout creation.
- No external API, scraping, server upload, build bump, or TestFlight upload.

## Files Changed

- `SOOM/Features/Workout/GPXRouteAttachmentService.swift`
- `SOOMTests/GPXRouteAttachmentServiceTests.swift`
- `SOOM.xcodeproj/project.pbxproj`
- `docs/reports/soom-gpx-import-v1-attachment-service.md`

## Service Behavior

Added:

- `GPXRouteAttachmentService`
- `GPXRouteAttachmentResult`
- `GPXRouteAttachmentError`

Input:

- Existing `UnifiedWorkout.id`
- GPX `Data`
- Optional explicit replacement flag

Behavior:

1. Fetch the existing workout from `UnifiedWorkoutStore`.
2. Refuse unsupported sources.
3. Parse GPX data with `GPXRouteParser`.
4. Refuse replacement when the workout already has a persisted route unless `replacingExistingRoute` is true.
5. Persist a `WorkoutRoute` using the existing `WorkoutRoutePersistenceStoring` model.
6. Associate the route with the existing `UnifiedWorkout.id`.
7. Clear `routeMissingReason` to `.none` after route persistence succeeds.

The service currently supports Apple HealthKit imported workouts. Local Record workouts are rejected with `.unsupportedSource(.soomLocal)` so existing Record route behavior remains unchanged.

## Route Persistence Behavior

The attached route is persisted as:

- `workoutId`: existing `UnifiedWorkout.id`
- `source`: existing workout source
- `coordinates`: parsed GPX coordinates
- `totalDistanceMeters`: parser-calculated GPX distance
- `totalElevationGain`: derived from positive altitude deltas when elevation exists
- `createdAt`: service date provider

The service does not create a new workout and does not mutate summary fields such as duration, sport, or calories.

## Route Missing Reason Behavior

Successful attachment:

- Updates the existing workout to `routeMissingReason == .none`.

Invalid GPX:

- Does not save a route.
- Does not modify the workout.

Route persistence failure:

- Preserves the workout summary.
- Updates an existing missing-route state to `.routePersistenceFailed` when applicable.

## Replacement Policy

Default behavior is no replacement:

- If a persisted route already exists, the service returns `.alreadyHasRoute`.
- Existing route-backed workouts are not modified silently.

Explicit replacement is available through `replacingExistingRoute: true`, but no UI path calls it yet.

## Tests Added

`GPXRouteAttachmentServiceTests` covers:

- Attaching valid GPX to a HealthKit imported no-route workout.
- Persisting the route with the existing workout id.
- Clearing `routeMissingReason` after successful attachment.
- Invalid GPX leaving workout and route storage unchanged.
- Existing route not replaced by default.
- Explicit replacement replacing the persisted route.
- Persistence failure preserving workout summary and reporting failure.
- `ProcessedWorkoutBuilder` consuming the attached route.
- Local Record workout behavior remaining unchanged.
- Missing workout returning `workoutNotFound`.

## Intentionally Deferred

- File picker UI.
- Activity Detail "경로 파일 가져오기" entry point.
- User confirmation UI for replacing an existing route.
- FIT import.
- TCX import.
- Strava, Wahoo, Garmin, Komoot, TrainingPeaks, Decathlon, or other provider integrations.
- Server upload.
- Route smoothing, snapping, or simplification.

## Verification

Focused attachment/parser test command:

```sh
xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SOOMTests/GPXRouteAttachmentServiceTests -only-testing:SOOMTests/GPXRouteParserTests
```

Result:

- Test execution was blocked by CoreSimulator infrastructure:
  - `Failed to clone device named 'iPhone 17 Pro'.`
  - `Device was allocated but was stuck in creation state.`
- Xcode also reported a connected device was passcode protected while preparing destinations.

Build-for-testing command:

```sh
xcodebuild build-for-testing -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'
```

Result:

- Passed.

Required build command:

```sh
xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'
```

Result:

- Passed.

## Next Recommended Step

Implement GPX Import v1 Phase 3: Activity Detail file importer entry point.

Recommended scope:

1. Show the existing no-route fallback for imported workouts with `routeMissingReason`.
2. Add a user-initiated "경로 파일 가져오기" action.
3. Present a GPX file importer.
4. Call `GPXRouteAttachmentService`.
5. Refresh the processed workout route view after successful attachment.
6. Keep replacement confirmation explicit and defer FIT/TCX.
