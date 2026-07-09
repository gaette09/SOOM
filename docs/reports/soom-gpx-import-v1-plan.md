# SOOM GPX Import V1 Implementation Plan

Date: 2026-07-09

## Goal

Implement GPX Import v1 as the first user-controlled route fallback for imported workouts that have HealthKit summary data but no route.

Primary target use case:

- A HealthKit imported workout, especially cycling, has distance/duration/sport metadata.
- HealthKit does not expose `HKWorkoutRoute`.
- `routeMissingReason` explains the missing route.
- The user has a GPX export from the original app/device.
- SOOM attaches that route to the existing imported workout without creating a duplicate workout.

Non-goals:

- No FIT/TCX parsing in v1.
- No Strava/Wahoo/Garmin integration.
- No external API calls.
- No scraping or login automation.
- No server upload.
- No route smoothing, snapping, simplification, or privacy masking changes.
- No sampled stream persistence beyond simple GPX route coordinate metadata.

## User Flow

1. User opens an imported workout with no route in Activity Detail.
2. Activity Detail shows the existing route-missing fallback:
   - “Apple Health에서 운동은 가져왔지만 경로 데이터는 포함되지 않았습니다.”
   - “원본 앱에서 GPX 파일을 가져오면 경로를 추가할 수 있습니다.”
3. User taps “경로 파일 가져오기”.
4. iOS document picker opens for `.gpx`.
5. User selects a GPX file.
6. SOOM parses coordinates locally.
7. SOOM validates the route.
8. SOOM shows a lightweight confirmation state:
   - coordinate count
   - route distance
   - rough bounds or preview
   - target workout date/sport/distance
9. User confirms attachment.
10. SOOM saves a `WorkoutRoute` with `workoutId = imported UnifiedWorkout.id`.
11. SOOM updates `routeMissingReason` to `.none`.
12. Activity Detail reloads and shows the route-backed map.
13. Share uses the existing route-backed path when route persistence succeeds.

## Supported GPX Subset

V1 should parse only the standard track subset needed for route display:

- `<trk>`
- `<trkseg>`
- `<trkpt lat="..." lon="...">`
- optional `<ele>`
- optional `<time>`

Mapping:

- `trkpt.lat` -> `WorkoutRouteCoordinate.latitude`
- `trkpt.lon` -> `WorkoutRouteCoordinate.longitude`
- `ele` -> `WorkoutRouteCoordinate.altitude`
- `time` -> `WorkoutRouteCoordinate.timestamp`

If multiple tracks or segments exist:

- Preserve trackpoint order.
- Flatten valid `trkseg/trkpt` points into one coordinate list.
- Do not infer gaps, pauses, or splits in v1.

## Unsupported GPX Features In V1

Defer:

- routes via `<rte>/<rtept>`
- waypoints via `<wpt>`
- extensions such as heart rate, cadence, power, temperature, and vendor metadata
- laps, splits, intervals, pauses, moving time
- route smoothing/simplification
- route snapping
- map matching
- duplicate workout creation from GPX metadata
- automatic matching to a different workout
- background imports
- batch imports

Decision:

- If a file contains only unsupported features and no valid `trk/trkseg/trkpt`, show an invalid route message and do not persist anything.

## Validation Rules

Coordinate validation:

- Require at least two valid coordinates.
- Latitude must be between `-90` and `90`.
- Longitude must be between `-180` and `180`.
- Drop invalid points rather than failing the whole file when enough valid points remain.
- Preserve altitude and timestamp only when parseable.

Distance validation:

- Calculate route distance from coordinate pairs using a deterministic local formula, ideally `CLLocation.distance(from:)` or a small shared distance helper.
- Store the calculated distance in `WorkoutRoute.totalDistanceMeters`.
- Keep HealthKit summary distance unchanged on `UnifiedWorkout`.
- `ProcessedWorkoutBuilder` should continue to prefer measured workout distance over route distance, and use route distance only as a fallback when summary distance is missing.

Empty/invalid file handling:

- Empty file: fail with “GPX 파일에서 경로를 찾지 못했습니다.”
- Malformed XML: fail with a file parse error.
- No trackpoints: fail with unsupported GPX content.
- One valid point: fail because a renderable route needs at least two coordinates.

Large file handling:

- Set a v1 file size guard before parsing.
- Recommended initial cap: 10 MB.
- Set a coordinate cap to avoid memory/UI issues.
- Recommended initial cap: 20,000 accepted points.
- If the file exceeds caps, fail gracefully and ask the user to export a smaller GPX.
- Do not simplify in v1; simplification can be a later route-quality phase.

Safety:

- Never attach a route automatically to a different workout.
- Never create a duplicate workout from GPX.
- Never overwrite an existing route without explicit user confirmation.

## Persistence Strategy

Use existing route persistence:

- Build `WorkoutRoute`.
- Set `workoutId` to the existing imported `UnifiedWorkout.id`.
- Set `source` to the workout source for v1 unless a dedicated route-origin field is added first.
- Save through `WorkoutRoutePersistenceStoring.saveRoute(_:)`.

Important:

- `SwiftDataWorkoutRoutePersistenceStore.saveRoute` already upserts by `workoutId`.
- This means attaching a GPX route to a workout with no existing route should be a normal save.
- Replacement should be guarded by confirmation because upsert will replace an existing route.

Recommended v1 source behavior:

- If no route-origin field exists yet, set `WorkoutRoute.source = unifiedWorkout.source` and document that route origin is GPX in route import audit/report only.
- If implementation adds a route-origin field, keep it additive and do not break existing HealthKit/Record route behavior.

Update workout status:

- After route save succeeds, update the stored `UnifiedWorkout.routeMissingReason` to `.none`.
- If route save fails, keep the prior route missing reason or set `.routePersistenceFailed`.
- Do not mutate distance/calories/sport metadata in v1.

## Existing-Route Strategy

If the target workout already has a route:

Preferred v1 behavior:

- Do not show “경로 파일 가져오기” by default.
- If replacement is reachable through a debug/admin path, require explicit confirmation.

If replacement is allowed:

- Show current route existence and imported GPX summary.
- Confirm replacement before calling `saveRoute`.
- Keep replacement local only.
- Do not delete the workout.

Conservative alternative:

- Defer replacement entirely in v1.
- Only allow GPX attachment when `fetchRoute(workoutId:) == nil`.

Recommendation:

- Defer replacement in v1 unless physical QA identifies a strong need. This avoids accidental route overwrite and keeps the first importer focused.

## Privacy And Security

Rules:

- Parse locally.
- Do not upload GPX or coordinates to Supabase in v1.
- Do not store the original GPX file after extracting route coordinates.
- Store only coordinates and minimal route metadata needed for Activity Detail and Share.
- Treat route data as sensitive location data.
- Do not scrape.
- Do not call external APIs.
- Do not infer or recover private routes automatically.
- Keep user action required for every file import.

Recommended file handling:

- Use document picker security-scoped access only for the selected file.
- Read the file into memory or a temporary parse buffer.
- Release security-scoped access immediately after parsing.
- Do not copy the original GPX into app storage in v1.

## Route Attachment Service

Add a small service layer in Phase 2:

Responsibilities:

- Fetch target workout by id or receive a confirmed `UnifiedWorkout`.
- Check whether a route already exists.
- Parse GPX output into coordinates.
- Build `WorkoutRoute`.
- Save route through `WorkoutRoutePersistenceStoring`.
- Update `UnifiedWorkout.routeMissingReason` to `.none` through `UnifiedWorkoutStore.saveWorkout`.
- Return a display-safe result for Activity Detail.

Suggested shape:

```swift
struct GPXRouteAttachmentService {
    func attachGPXRoute(
        fileData: Data,
        to workout: UnifiedWorkout
    ) async -> GPXRouteAttachmentResult
}
```

Keep parser pure and independent:

```swift
struct GPXRouteParser {
    func parse(_ data: Data) throws -> GPXParsedRoute
}
```

## Tests Required

Parser tests:

- Parses simple GPX with `trk/trkseg/trkpt`.
- Parses multiple segments in stable order.
- Preserves `ele` when present.
- Preserves `time` when valid.
- Drops invalid lat/lon points.
- Fails when fewer than two valid points remain.
- Fails on malformed XML.
- Fails on no trackpoints.
- Enforces file size or coordinate caps.

Distance tests:

- Calculates nonzero distance for two or more coordinates.
- Keeps zero distance from duplicate coordinates safe but still validates coordinate count.
- Does not use GPX distance to mutate `UnifiedWorkout.distanceMeters`.

Attachment service tests:

- Attaches route to existing imported `UnifiedWorkout.id`.
- Does not create a duplicate workout.
- Saves via existing route persistence.
- Updates `routeMissingReason` to `.none` on success.
- Keeps route missing reason or sets `.routePersistenceFailed` on save failure.
- Refuses replacement when a route already exists, unless replacement is explicitly enabled.
- Local Record workout with no route is not accidentally treated as HealthKit route fallback.

Activity Detail tests:

- Missing-route imported workout shows fallback entry point.
- After route attachment, `ProcessedWorkout.hasRoute == true`.
- Route-backed Activity Detail uses the map path.
- No-route fallback remains clean if parse or save fails.

Regression tests:

- Existing HealthKit route import still persists route.
- Existing Record route behavior still works.
- Share route-backed behavior still works once route exists.

## Implementation Phases

### Phase 1: GPX Parser Utility

Goal:

- Add a pure Swift parser with no UI or persistence.

Deliverables:

- `GPXRouteParser`
- `GPXParsedRoute`
- parser errors
- parser tests

Rules:

- Parse only supported v1 subset.
- Keep parser deterministic.
- No app behavior changes.

### Phase 2: Route Attachment Service

Goal:

- Attach parsed route to an existing imported workout.

Deliverables:

- `GPXRouteAttachmentService`
- route persistence through `WorkoutRoutePersistenceStoring`
- route missing reason update through `UnifiedWorkoutStore`
- attachment tests

Rules:

- No duplicate workout creation.
- No route replacement unless explicitly enabled.
- No server upload.

### Phase 3: Activity Detail File Import Entry Point

Goal:

- Make the existing route-missing fallback actionable.

Deliverables:

- Replace “경로 파일 가져오기 준비 중” placeholder with an import action.
- Add document picker for `.gpx`.
- Wire selected file to attachment service.
- Refresh Activity Detail route state after success.

Rules:

- Keep UI change minimal and route-specific.
- Do not change Mapbox style URI.
- Do not change Record route behavior.

### Phase 4: Device QA

Goal:

- Validate physical file import flows with real external cycling GPX files.

Checklist:

- Import cycling GPX exported from source app.
- Import running GPX.
- Invalid GPX fails gracefully.
- Large GPX fails gracefully.
- Existing route is not overwritten accidentally.
- Activity Detail map appears after successful attach.
- Share card uses route after attach.
- App handles revoked HealthKit permission because GPX attachment is local-first.

### Phase 5: Future FIT/TCX

Goal:

- Reuse attachment model for richer file formats.

Rules:

- Do not add FIT/TCX until GPX route attachment is stable.
- Keep route-only extraction first.
- Defer sensor streams until the read model supports them safely.

## Open Questions Before Coding

- Should v1 add a dedicated route origin field, or keep `WorkoutRoute.source = unifiedWorkout.source` and document GPX origin separately?
- Should replacement be fully deferred or hidden behind explicit confirmation?
- What file size and coordinate caps should ship for TestFlight?
- Should the first confirmation view show a mini route preview or only text metrics?

## Recommended Next Implementation Step

Start with Phase 1 only:

- Implement `GPXRouteParser` as a pure Swift utility.
- Add parser tests.
- Do not add UI, file picker, persistence, or routeMissingReason updates until parser behavior is proven.
