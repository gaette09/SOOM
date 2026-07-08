# SOOM External Route Source Fallback Plan

Date: 2026-07-09

## Summary

HealthKit remains the first route source for SOOM imported workouts, but physical QA shows it is not sufficient for every external cycling workout.

Current finding:

- SOOM can import HealthKit workout summaries.
- SOOM can display HealthKit routes when `HKWorkoutRoute` exists.
- Some externally sourced cycling workouts can appear in Apple Health as summary data without route samples.
- If the source app does not write `HKWorkoutRoute` into Apple Health, SOOM cannot read that route through HealthKit.

Recommended next step: implement GPX Import v1 as a user-driven route fallback that attaches a user-selected route file to an existing imported workout.

## HealthKit Route Limitations

HealthKit workout summary data and route data are separate:

- Summary fields can exist through `HKWorkout`, distance quantities, active energy, and sport metadata.
- Route coordinates require `HKWorkoutRoute` samples attached to the workout.
- External apps may write summary fields into Apple Health without writing route samples.
- HealthKit permissions can allow workouts while route data is unavailable or absent.

SOOM rules:

- Do not invent route coordinates.
- Do not infer route shape from distance, speed, or start/end points.
- Treat missing route as a source-data limitation, not an import failure, when the workout summary imports correctly.
- Keep the no-route fallback clean until a user-authorized route source is available.

## Why External Cycling Workouts May Have Summary But No Route

Likely causes:

- The source app writes only activity summary data to Apple Health.
- The source app stores GPS route data internally but does not export it to HealthKit.
- The source app writes route data only to its own cloud or to another platform.
- User permissions allow summary sharing but not route/location sharing.
- The workout was recorded indoors, from a trainer, or without GPS.
- The workout was imported into Apple Health from a third-party service that normalizes distance/calories but drops route geometry.

Diagnostic rule:

- If Apple Health shows route geometry for the exact workout but SOOM does not, inspect SOOM route fetch/persistence/display.
- If Apple Health does not expose route geometry for the exact workout, SOOM must use another user-authorized route source.

## Route Source Priority

1. HealthKit `HKWorkoutRoute`

- Default path.
- Read-only.
- User-authorized through HealthKit.
- Best when the source app/device writes route data into Apple Health.
- Already compatible with SOOM route persistence and Activity Detail display.

2. User-imported GPX

- Recommended v1 fallback.
- User chooses a GPX file from Files or share sheet.
- SOOM parses route coordinates locally.
- User attaches the route to an imported workout.
- SOOM persists the route using existing `WorkoutRoutePersistenceStoring`.
- Activity Detail and Share can show route after persistence.

3. User-imported FIT/TCX

- Recommended v2 file fallback.
- More complex parsing than GPX.
- Useful for Garmin, Wahoo, bike computer, and training platform exports.
- Can include timestamps, laps, power, cadence, and richer streams, but Phase 1 should extract only route coordinates and safe summary metadata unless explicitly expanded.

4. Strava OAuth API feasibility

- Feasibility spike only.
- OAuth only; no scraping or login automation.
- User-authorized activity data only.
- Verify current API tier, scopes, detailed activity response, map/polyline availability, and activity streams availability before implementation.
- Store only user-authorized route data needed for SOOM route display.
- Respect Strava display, privacy, attribution, and data-use constraints.

5. Garmin/Wahoo direct integration

- Research phase only.
- Likely higher product and API review overhead.
- Consider only after GPX/FIT/TCX and Strava feasibility are understood.

## `routeMissingReason` Model Recommendation

Add a first-class missing-route reason before broad fallback implementation.

Recommended enum:

```swift
enum WorkoutRouteMissingReason: String, Codable, Equatable {
    case notChecked
    case healthKitRouteUnavailable
    case healthKitPermissionDenied
    case sourceDidNotProvideRoute
    case routeFetchFailed
    case routeFileImportRequired
    case routeFileInvalid
    case userDeclinedRouteImport
}
```

Recommended storage relationship:

- Keep `WorkoutRoute` persistence unchanged for actual route coordinates.
- Store route-missing status with imported workout metadata or a lightweight route import state record keyed by workout id.
- Do not overload `WorkoutRoute` with failure states.

Recommended display behavior:

- If route exists: show route badge/map.
- If route missing because HealthKit has no route: show calm user action such as “Route file can be added.”
- If permission denied: show permission-specific recovery copy.
- If file import failed: show file-specific retry copy.

## User-Facing Fallback UX

Activity row:

- Imported workout appears normally.
- Route badge appears only if a route exists.
- If no route exists and source is external, show no warning in the row unless a future import status affordance is added.

Activity Detail:

- No-route fallback remains clean.
- Add an explicit route action only when route is missing:
  - “Add route file”
  - “Import GPX”
  - Avoid technical copy like `HKWorkoutRoute missing`.

Import flow:

- After HealthKit import, detect route-missing workouts.
- Offer user-guided route attachment:
  - select workout
  - choose GPX file
  - preview route bounds/distance
  - attach route
  - persist locally

Copy principles:

- Explain that Apple Health did not include route data for this workout.
- Do not blame the source app.
- Do not imply SOOM can recover private routes automatically.
- Do not imply background sync.
- Do not imply HealthKit write-back.

## GPX Import V1 Recommendation

Scope:

- User selects GPX file.
- SOOM parses coordinates locally.
- SOOM attaches the parsed route to an existing imported HealthKit workout.
- SOOM recomputes route distance if needed.
- SOOM persists the route using existing `WorkoutRoutePersistenceStoring`.
- Activity Detail and Share show the route after persistence.

Recommended flow:

1. User opens imported workout with missing route.
2. User taps “Import GPX”.
3. iOS document picker opens.
4. User selects a `.gpx` file.
5. SOOM parses `trk/trkseg/trkpt` coordinates.
6. SOOM validates at least two coordinates.
7. SOOM calculates bounds and route distance.
8. SOOM shows a lightweight confirmation preview.
9. User confirms attachment.
10. SOOM saves `WorkoutRoute(workoutId: importedWorkout.id, source: .appleHealthKit or new .userFileImport, coordinates: ...)`.
11. Activity Detail reloads with route-backed map.

Validation rules:

- Require at least two valid coordinates.
- Drop invalid latitude/longitude values.
- Preserve altitude/timestamp when present.
- Do not smooth, snap, or simplify in v1.
- If GPX distance differs materially from summary distance, keep both:
  - workout summary distance remains HealthKit measured summary
  - route distance can power route preview/distance fallback when summary distance is missing
- Never attach route automatically to a different workout without user confirmation.

Security rules:

- Parse locally.
- Do not upload GPX by default.
- Do not keep original GPX file after extracting coordinates unless explicitly needed and approved.
- Treat route coordinates as sensitive location data.

## FIT/TCX Import V2 Recommendation

FIT/TCX support should follow GPX after the route attachment model is stable.

FIT:

- Requires binary parser or vetted library.
- Can contain GPS, sensors, laps, device metadata.
- Phase 2 should extract route only unless stream persistence is explicitly scoped.

TCX:

- XML-based.
- Can include trackpoints, heart rate, cadence, laps.
- Simpler than FIT but richer than GPX.

Rules:

- User-selected files only.
- No hidden cloud import.
- No sampled stream persistence unless explicitly planned.
- Attach route to selected workout after confirmation.

## Strava OAuth API Feasibility Spike

Official docs reviewed:

- Strava API requests require authentication, and authorization scopes are user-granted.
- The API exposes activity detail and activity streams endpoints in the reference docs.
- Strava OAuth scopes can differ from requested scopes if the athlete unchecks them.
- Strava API agreement says user-specific Strava data can only be displayed/disclosed to that specific user and must be protected with appropriate security measures.

Spike questions:

- Can SOOM access the authenticated user’s cycling activity detail under current Strava API tier?
- Does detailed activity include usable route map/polyline for the user’s own activity?
- Does `Get Activity Streams` provide `latlng` data for the user’s own cycling activity with granted scopes?
- Which scopes are required for public, followers, and private activities?
- What attribution is required when showing source/device data?
- What are current rate limits and app review requirements?
- Are there product constraints preventing SOOM from using Strava route data for Activity Detail and Share?
- Can route data be stored locally or in Supabase under Strava’s API terms, and for how long?

Implementation rules if approved:

- OAuth only.
- User-authorized data only.
- No scraping.
- No web login automation.
- No private activity bypass.
- No AI model training using Strava API data.
- No public display of user Strava activity data to other users.
- Store only route data needed for the user’s SOOM experience.
- Provide disconnect and delete behavior.

Current recommendation:

- Do not implement Strava before GPX v1.
- Run a small policy/API feasibility spike with a test Strava developer app and one user-authorized activity.

Sources:

- Strava API reference: `https://developers.strava.com/docs/reference/`
- Strava OAuth docs: `https://developers.strava.com/docs/authentication/`
- Strava API agreement: `https://www.strava.com/legal/api`

## Privacy And Security Rules

Route data is sensitive location data.

Rules:

- User action required for every non-HealthKit route source.
- No scraping.
- No login automation.
- No silent background route import.
- No bypass of source app privacy settings.
- No importing another user’s private activity.
- No public sharing of route data unless the user explicitly uses SOOM share/export flows.
- No AI model training on Strava/API route data.
- Encrypt or otherwise protect route data at rest where platform storage supports it.
- Keep deletion path clear: deleting workout or route should remove attached route data.
- Keep original file retention minimal.

## Storage Model Implications

Existing route persistence:

- `WorkoutRoute` already stores:
  - `workoutId`
  - `source`
  - coordinates
  - total distance
  - elevation
  - bounds
  - created date

Recommended additions:

- route origin/source detail:
  - `.healthKit`
  - `.gpxFile`
  - `.fitFile`
  - `.tcxFile`
  - `.strava`
  - `.garmin`
  - `.wahoo`
- route missing reason state keyed by workout id
- optional external route source id for OAuth-backed imports
- import audit fields:
  - importedAt
  - userConfirmedAt
  - parserVersion
  - coordinateCount

Avoid:

- storing source access tokens in route records
- storing original files in local route records
- mixing sampled stream data into `WorkoutRoute` v1

## Supabase / Local Storage Implications

Local-first recommendation:

- GPX/FIT/TCX v1 route attachment should persist locally using existing route persistence first.
- Supabase sync should be deferred until route privacy and deletion semantics are explicit.

If Supabase route sync is later approved:

- Store route coordinates in a dedicated route table or storage object keyed by workout id and owner id.
- Enforce row-level security by owner.
- Encrypt sensitive route payloads if feasible.
- Keep route source metadata separate from credentials.
- Never store Strava client secret in the app.
- Store OAuth tokens only in secure server-side storage if Strava server integration is approved.
- Provide delete route/delete account cleanup.

Recommended Supabase fields:

- `id`
- `owner_id`
- `workout_id`
- `route_source`
- `external_source_id`
- `coordinate_count`
- `distance_meters`
- `elevation_gain_meters`
- `bounds`
- `encoded_polyline` or route payload reference
- `created_at`
- `updated_at`
- `deleted_at`

## Implementation Phases

### Phase 0: Route Missing Detection

Goal:

- Make route absence explicit without changing import behavior.

Tasks:

- Add route missing reason model.
- Detect HealthKit imported workouts with no persisted route.
- Preserve no-route fallback.
- Add tests for HealthKit summary-only route-missing state.

### Phase 1: GPX Import V1

Goal:

- Let users attach route coordinates to an imported workout through a selected GPX file.

Tasks:

- Add GPX parser.
- Add document picker route import flow.
- Add route preview/confirmation.
- Save `WorkoutRoute` through existing route persistence.
- Refresh Activity Detail/Share route display.
- Add parser, persistence, and Activity Detail route tests.

### Phase 2: FIT/TCX Import

Goal:

- Support common cycling computer exports.

Tasks:

- Choose vetted parser strategy.
- Extract route coordinates only in first pass.
- Attach to selected workout.
- Preserve missing/unsupported stream behavior.

### Phase 3: Strava OAuth Feasibility

Goal:

- Determine whether Strava can be a compliant route source for user-authorized activities.

Tasks:

- Register developer app.
- Validate OAuth scopes.
- Test detailed activity/map/stream availability.
- Review API policy constraints.
- Decide whether implementation is product/legal viable.

### Phase 4: Direct Device/Platform Integrations

Goal:

- Research Garmin/Wahoo direct integrations after file import and Strava feasibility.

Tasks:

- Review API access requirements.
- Review user consent and data retention requirements.
- Estimate maintenance/support cost.

## Explicit Non-Goals

- No web scraping.
- No Strava web login automation.
- No bypass of Strava API limitations.
- No private activity bypass.
- No AI model training using Strava API data.
- No public display of user Strava activity data to other users.
- No HealthKit write-back.
- No background sync in this route fallback phase.
- No route snapping/smoothing in GPX v1.
- No sampled power/cadence stream persistence in GPX v1.

## Recommended Next Implementation Step

P0: Route missing detection and fallback plan handoff.

Then:

P1: GPX Import v1.

Reasoning:

- It is user-controlled.
- It does not depend on external API approval.
- It can solve cycling route gaps for files exported from external apps/devices.
- It uses existing SOOM route persistence and Activity Detail/Share route display paths.

Strava OAuth should remain a P1 feasibility spike in parallel or immediately after GPX planning, not the first production route fallback.
