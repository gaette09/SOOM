# SOOM FIT Import v1 Phase C: Route Attachment Service

Date: 2026-07-09

## Summary

Phase C adds a local FIT route attachment service that follows the existing GPX attachment pattern. It parses a FIT route, persists the route with the existing `WorkoutRoute` persistence model, associates it with an existing imported workout id, and clears `routeMissingReason` after a successful attach.

This does not add UI, file picker changes, full FIT workout import, sensor stream persistence, external APIs, or server upload.

## Files Changed

- `SOOM/Features/Workout/FITRouteAttachmentService.swift`
- `SOOMTests/FITRouteAttachmentServiceTests.swift`
- `SOOM.xcodeproj/project.pbxproj`
- `docs/reports/soom-fit-import-v1-attachment-service.md`

## Service Behavior

`FITRouteAttachmentService`:

- Fetches an existing `UnifiedWorkout` by id.
- Allows attachment only for `.appleHealthKit` imported workouts.
- Parses FIT data through `FITRouteParser`.
- Requires at least two route coordinates.
- Persists the route through `WorkoutRoutePersistenceStoring`.
- Associates the route with the existing `UnifiedWorkout.id`.
- Does not create a duplicate workout.
- Clears `routeMissingReason` to `.none` after a successful route save.
- Preserves the workout summary if FIT parsing or route persistence fails.

## Route Persistence

The service writes a `WorkoutRoute` using:

- `workoutId`: existing imported workout id
- `source`: existing workout source
- `coordinates`: parsed FIT route coordinates
- `totalDistanceMeters`: parsed FIT distance or parser-derived route distance
- `totalElevationGain`: parsed FIT session ascent when available, otherwise derived from coordinate altitude

This keeps Activity Detail, Share, and ProcessedWorkout consumers on the existing route model.

## routeMissingReason

Successful attachment clears the missing-route state:

- `.healthKitRouteUnavailable` -> `.none`
- `.externalSourceRouteNotShared` -> `.none`

If route persistence fails after a valid FIT parse, the service records `.routePersistenceFailed` when the workout already had a missing-route reason. The workout summary remains intact.

## Replacement Policy

Existing routes are not replaced by default. The service returns `.alreadyHasRoute` when a route exists unless `replacingExistingRoute` is explicitly true.

The UI phase should keep the default as no replacement.

## Tests Added

`FITRouteAttachmentServiceTests` uses synthetic FIT binary fixtures and covers:

- Valid FIT attaches to a HealthKit imported no-route workout.
- Route is persisted with the existing workout id.
- `routeMissingReason` clears after success.
- Invalid FIT does not modify the workout or persist a route.
- Existing route is not replaced by default.
- Explicit replacement can replace an existing route.
- Persistence failure preserves the workout summary and records `.routePersistenceFailed`.
- `ProcessedWorkoutBuilder` can consume the attached route.
- Local SOOM Record workouts are rejected and unchanged.
- Missing workout returns `workoutNotFound`.

## Deferred

- Real-device FIT compatibility testing.
- Real FIT sample coverage from Garmin/Wahoo/Bryton/iGPSPORT/Magene/Coospo and external Chinese cycling computers.
- Activity Detail `.fit` file importer entry point.
- Full FIT workout import.
- HR/cadence/power sampled stream persistence.
- FIT/TCX/Strava/Wahoo/Garmin provider integrations.

## Verification

Completed for this phase:

```sh
xcodebuild build-for-testing -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator' # passed
xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator' # passed
```

Focused simulator test execution was attempted:

```sh
xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SOOMTests/FITRouteParserTests -only-testing:SOOMTests/FITRouteAttachmentServiceTests
```

It failed before test execution because CoreSimulator could not clone `iPhone 17 Pro` and reported the device was stuck in creation state. This is treated as infrastructure. Build-for-testing remains the primary verification gate until simulator cloning is fixed.

Xcode also emitted existing connected-device passcode warnings and existing HealthKit deprecation warnings.

Pending final release hygiene:

```sh
git diff --check
git status --short
```

## Next Recommended Step

Proceed to Phase D if build-for-testing passes: extend the existing Activity Detail route import entry point to accept `.fit` files and dispatch `.gpx` files to GPX attachment and `.fit` files to FIT attachment.
