# SOOM GPX Import V1 Parser

Date: 2026-07-09

## Summary

Implemented GPX Import v1 Phase 1: a pure Swift GPX parser and focused parser tests.

This phase is parser-only:

- No file picker UI.
- No Activity Detail UI changes.
- No route attachment service.
- No route persistence writes.
- No HealthKit import changes.
- No external APIs, scraping, server upload, build bump, or TestFlight upload.

## Files Changed

- `SOOM/Features/Workout/GPXRouteParser.swift`
- `SOOMTests/GPXRouteParserTests.swift`
- `SOOM.xcodeproj/project.pbxproj`
- `docs/reports/soom-gpx-import-v1-parser.md`

## Parser Behavior

Added:

- `GPXRouteParser`
- `GPXParsedRoute`
- `GPXRouteParserError`

Parser input:

- `Data`
- `String` helper for tests and simple callers

Parser output:

- `[WorkoutRouteCoordinate]`
- `coordinateCount`
- `totalDistanceMeters`

The parser uses `XMLParser` with a delegate, so parsing is streaming-style and does not require recursive XML tree traversal.

Distance is calculated locally with a Haversine formula over valid coordinate pairs. This distance is parser output only; it does not mutate any workout summary data.

## Supported GPX Subset

Supported:

- `trk`
- `trkseg`
- `trkpt lat/lon`
- optional `ele`
- optional `time`

Behavior:

- Multiple segments are flattened in document order.
- Valid `ele` values map to `WorkoutRouteCoordinate.altitude`.
- Valid ISO 8601 `time` values map to `WorkoutRouteCoordinate.timestamp`.
- Missing `ele` or `time` is allowed.

## Validation Rules

Implemented:

- Empty data fails with `.emptyData`.
- Files over `maximumFileSizeBytes` fail before parsing.
- Malformed XML fails with `.malformedXML`.
- GPX with no `trkpt` fails with `.noTrackPoints`.
- Latitude must be `-90...90`.
- Longitude must be `-180...180`.
- Invalid trackpoints are ignored.
- Fewer than two valid coordinates fails with `.insufficientValidCoordinates`.
- Accepted coordinates over `maximumCoordinateCount` fails with `.coordinateLimitExceeded`.

Default limits:

- File size: 10 MB.
- Coordinates: 20,000.

## Tests Added

`GPXRouteParserTests` covers:

- valid GPX with one track segment
- valid GPX with multiple track segments
- optional elevation parsing
- optional time parsing
- missing elevation/time still succeeds
- invalid lat/lon points are ignored when enough valid points remain
- empty data fails
- GPX with no `trkpt` fails
- malformed XML fails cleanly
- single valid point fails
- file size cap fails before parsing
- coordinate cap fails cleanly

## Intentionally Deferred

- `rte/rtept`
- `wpt`
- GPX extensions
- FIT
- TCX
- file picker
- route attachment service
- route persistence writes
- `routeMissingReason` updates after attachment
- Activity Detail import action
- route replacement flow
- server upload
- route smoothing, snapping, or simplification

## Verification

Focused parser test command:

```sh
xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SOOMTests/GPXRouteParserTests
```

Result:

- Parser and tests compiled.
- Test execution was blocked by CoreSimulator infrastructure:
  - `Failed to clone device named 'iPhone 17 Pro'.`
  - `Device was allocated but was stuck in creation state.`

Required build command:

```sh
xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'
```

Result:

- Passed.

## Next Recommended Step

Implement GPX Import v1 Phase 2: route attachment service.

Recommended scope:

1. Accept parsed `GPXParsedRoute` plus a confirmed imported `UnifiedWorkout`.
2. Refuse attachment if a route already exists unless replacement is explicitly enabled.
3. Build `WorkoutRoute(workoutId: unifiedWorkout.id, source: unifiedWorkout.source, coordinates: parsed.coordinates, totalDistanceMeters: parsed.totalDistanceMeters)`.
4. Save through `WorkoutRoutePersistenceStoring`.
5. Update `UnifiedWorkout.routeMissingReason` to `.none` only after route save succeeds.
