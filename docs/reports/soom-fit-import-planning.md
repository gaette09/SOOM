# SOOM FIT Import Planning

Date: 2026-07-09

## Summary

FIT should be SOOM's next file-import priority after GPX route attachment because FIT is commonly the original activity file for cycling computers and cycling apps.

GPX is useful for route-only recovery when HealthKit has a workout summary but no `HKWorkoutRoute`. FIT is different: it can preserve the original cycling activity record, including route, summary, sport metadata, and sensor data. SOOM should therefore plan both FIT route attachment and full FIT workout import before writing parser code.

This is a planning document only:

- No FIT parser implementation.
- No dependency addition.
- No app code changes.
- No TestFlight upload.

## Why FIT Matters For Cycling Devices

Cycling computers often record and export rides as FIT files. That makes FIT more important than GPX for cycling because a FIT file may contain:

- the route geometry SOOM needs for Activity Detail and Share
- device-recorded summary metrics
- sport/activity metadata
- sensor streams or summary values
- lap/event structure

FIT also gives SOOM a path that does not depend on whether Apple Health received `HKWorkoutRoute` from the source app. When HealthKit has only summary data, a user-selected FIT file can be the most faithful user-authorized fallback.

## Expected FIT Contents

A useful cycling FIT file may contain:

- sport type
- start time
- duration
- distance
- GPS route
- speed
- elevation
- heart rate
- cadence
- power
- calories
- laps/events if available

Availability is file/device dependent. SOOM should parse what exists and avoid fabricating missing data.

## FIT Compared With GPX And TCX

| Format | Primary role | Route | Summary | Sensor/activity data | SOOM priority |
| --- | --- | --- | --- | --- | --- |
| GPX | Route-first attachment. | Strong for coordinates; elevation/time optional. | Weak; distance/duration often derived. | Weak in v1; extensions deferred. | Already implemented for route attachment. |
| FIT | Activity-original cycling import. | Strong when GPS was recorded. | Strong; distance, duration, sport, calories, laps/events can exist. | Strong; HR/cadence/power/elevation can exist. | Next priority. |
| TCX | Fallback richer than GPX. | Strong when exported with trackpoints. | Medium; laps and activity structure can exist. | Medium; HR/cadence/power can exist. | After FIT. |

Practical implication:

- Use GPX when the user only needs to attach route geometry.
- Use FIT when the user has the original cycling activity file or needs richer cycling data.
- Use TCX when FIT is unavailable but a structured XML activity export exists.

## Implementation Strategy Options

### A. Native Swift FIT Parser

Build a Swift parser that understands the FIT binary structure and the message types SOOM needs.

Pros:

- Fully local and inspectable.
- No third-party dependency risk.
- Can be tailored to SOOM's staged import model.

Cons:

- Higher implementation complexity.
- Requires careful validation against many device files.
- Easy to under-handle developer fields, compressed timestamp headers, and device-specific quirks.

Recommendation:

- Viable only if Phase 1 is narrowly scoped and backed by strong sample-file coverage.

### B. Lightweight Internal Parser For Records Only

Build a minimal internal parser that extracts only the FIT messages needed for route and summary:

- file id/activity/session/lap where needed
- record messages for position, altitude, speed, HR, cadence, power
- sport metadata if available

Pros:

- Smaller surface than a full FIT implementation.
- Good for a feasibility spike.
- Avoids broad dependency adoption.

Cons:

- May fail on legitimate files that need more complete FIT profile handling.
- May become technical debt if SOOM expands to full sensor streams.

Recommendation:

- Best candidate for a Phase 1 feasibility spike, as long as failures are explicit and non-destructive.

### C. Garmin FIT SDK / Reference Logic Outside App

Use Garmin FIT SDK/reference behavior as a benchmark or development aid outside the shipped app.

Pros:

- Canonical behavior for FIT decoding concepts.
- Useful for validating sample files and expected message fields.

Cons:

- Shipping SDK code in the app requires license, size, maintenance, and platform review.
- Reference implementations may not map cleanly to Swift/iOS app architecture.

Recommendation:

- Use for offline validation and learning first. Do not add to the app until dependency/legal review passes.

### D. Server-Side Parser Later

Upload the user-selected FIT file to a server parser and return parsed summary/route data.

Pros:

- Easier dependency choices.
- Can run mature parsers outside iOS constraints.
- Easier to patch parser behavior without app release.

Cons:

- Uploads sensitive health/location data.
- Requires explicit privacy, retention, deletion, security, and account ownership design.
- Not aligned with current local-first import posture.

Recommendation:

- Defer. Server-side parsing should not be v1.

### E. Third-Party Swift Package After Review

Adopt a Swift package that parses FIT files.

Pros:

- Faster implementation if the package is mature.
- May support more FIT profile coverage than a minimal internal parser.

Cons:

- Dependency quality and maintenance risk.
- License compatibility review required.
- Security review required because FIT files are untrusted user-selected binary input.
- API stability and iOS compatibility need validation.

Recommendation:

- Consider only after review. Do not add a package before sample-file needs and parser acceptance criteria are defined.

## Dependency And Security Review Criteria

Before adding any FIT parser dependency, review:

- license compatibility with SOOM
- active maintenance and release history
- iOS compatibility
- Swift concurrency and memory behavior
- binary parsing safety
- bounds checking and malformed-file behavior
- large-file handling
- test coverage against real FIT files
- ability to parse without network access
- ability to disable or ignore fields SOOM does not store
- no analytics, telemetry, or hidden upload behavior
- package size and build impact
- API stability and ability to pin versions

Parser safety rules:

- Treat every FIT file as untrusted input.
- Fail safely on malformed files.
- Enforce file size limits.
- Enforce coordinate/sample count limits.
- Never crash Activity Detail because parsing failed.
- Never create or mutate a workout until validation passes.

## Required Sample FIT Files

Collect sample files before implementation:

- cycling with GPS route
- cycling without GPS route
- cycling with heart rate
- cycling with cadence
- cycling with power
- long ride
- short ride
- external Chinese cycling computer FIT if available
- Garmin FIT if available
- Wahoo FIT if available
- Bryton FIT if available
- iGPSPORT FIT if available
- Magene FIT if available
- Coospo FIT if available

For each sample, record:

- source device/app
- outdoor or indoor
- expected sport
- expected start time
- expected duration
- expected distance
- expected route availability
- expected elevation availability
- expected HR/cadence/power availability
- whether Apple Health imported a summary
- whether Apple Health exposed a route
- whether the file should attach to an existing workout or create a new workout

Sample files must be user-authorized and treated as sensitive health/location data.

## Data Mapping To SOOM

### UnifiedWorkout

FIT summary fields should map to `UnifiedWorkout`:

- FIT activity id or derived stable file id -> `externalId`
- route/file origin -> source metadata in a future model
- sport type -> `UnifiedWorkoutType`
- start time -> `startDate`
- duration/end time -> `durationSeconds` and `endDate`
- distance -> `distanceMeters`
- calories -> `activeEnergyKcal`
- average heart rate if available -> `averageHeartRate`
- max heart rate if available -> `maxHeartRate`
- average speed if available or derivable -> `averageSpeedMetersPerSecond`
- elevation gain if available -> `elevationGainMeters`
- missing route state -> `routeMissingReason`
- completeness -> `UnifiedDataQuality`

FIT import should not fake missing calories, HR, cadence, power, or elevation.

### WorkoutRoute

FIT route fields should map to `WorkoutRoute`:

- existing or new `UnifiedWorkout.id` -> `workoutId`
- FIT file origin -> future route origin metadata
- position lat/lon -> `WorkoutRouteCoordinate`
- altitude -> `WorkoutRouteCoordinate.altitude`
- timestamp -> `WorkoutRouteCoordinate.timestamp`
- coordinate-derived distance or FIT summary distance -> `totalDistanceMeters`
- elevation gain if safely derivable -> `totalElevationGain`

Route extraction should preserve point order and reject render-unsafe routes with fewer than two valid coordinates.

### ProcessedWorkout

`ProcessedWorkoutBuilder` should consume FIT-backed imports the same way it consumes HealthKit/GPX-backed data:

- route exists -> `hasRoute == true`
- route missing -> display-safe `routeMissingReason`
- measured summary distance should remain preferred over route-derived distance
- route-derived distance can be fallback when summary distance is absent
- unavailable optional metrics should remain unavailable, not zeroed

### Future Sensor Streams

FIT can contain sampled data SOOM may later store:

- heart rate samples
- cadence samples
- power samples
- elevation samples
- speed samples
- laps/events

Phase 5 should define storage and display contracts before persistence. Do not add stream persistence as an incidental side effect of route import.

## Import Modes

### Route Attach Mode

Target:

- Existing HealthKit imported workout has summary data but no route.
- User selects a FIT file for the same ride.

Flow:

1. User opens Activity Detail no-route fallback.
2. User selects a FIT file.
3. SOOM parses summary and route.
4. SOOM verifies the FIT file is a conservative match:
   - compatible sport
   - overlapping or similar start time
   - similar duration
   - similar distance when both exist
5. SOOM attaches only the route to the existing workout.
6. SOOM clears `routeMissingReason` after route persistence succeeds.
7. SOOM does not overwrite the HealthKit summary unless a later explicit replacement flow exists.

Replacement policy:

- Do not replace an existing route silently.
- Require explicit user confirmation before replacing a route.

### Full Workout Import Mode

Target:

- User has a FIT file for a workout that is not already in SOOM.
- Or the FIT file is clearly the better original activity source and the user explicitly imports it.

Flow:

1. User selects a FIT file.
2. SOOM parses summary, sport, timing, route, and safe metrics.
3. SOOM runs duplicate/source-priority checks.
4. If no duplicate exists, SOOM creates a `UnifiedWorkout`.
5. SOOM persists route if present.
6. SOOM builds `ProcessedWorkout` for surfaces.

Rules:

- Never create a visible duplicate if an equivalent local/HealthKit workout exists.
- Prefer local SOOM Record workouts over imported FIT duplicates.
- Prefer explicit user-selected FIT only after duplicate review if it conflicts with an existing imported workout.

## Missing-Data Rules

General:

- Missing field means unavailable, not zero.
- Do not infer route geometry from distance/time.
- Do not infer calories from power/HR in v1.
- Do not infer power/cadence from speed.
- Do not infer outdoor route for indoor trainer files.

Route:

- No GPS route in FIT -> preserve summary import and set a route-missing status.
- Fewer than two valid coordinates -> no renderable route.
- Invalid coordinates -> drop if enough valid points remain; otherwise fail route extraction.

Summary:

- Missing distance -> allow duration-only import if user confirms, but mark data quality partial.
- Missing sport -> classify conservatively as `.other` unless the file source or session clearly indicates cycling.
- Missing start time -> block full workout import because duplicate prevention and display become unsafe.

Sensors:

- Missing HR/cadence/power should not block route or summary import.
- Present streams should not be persisted until stream storage is explicitly designed.

## Duplicate Prevention

FIT duplicate matching should reuse the conservative source-priority posture from HealthKit import:

- exact external/file id match should upsert rather than duplicate
- compatible sport required
- overlapping start/end time required
- similar duration required
- similar distance required when both distances exist
- missing distance should make matching more conservative, not more aggressive

Priority:

1. SOOM local Record workout wins by default.
2. Existing HealthKit imported workout wins unless the user is explicitly attaching a FIT route to it.
3. FIT full workout import should create a new workout only when no conservative duplicate exists.

Avoid destructive merges:

- Do not delete existing workouts automatically.
- Prefer skip, attach route, or require duplicate review.

## Privacy And Local-First Rules

FIT files can contain sensitive health, performance, and location data.

Rules:

- User-selected files only.
- Parse locally in early phases.
- Do not upload original FIT files.
- Do not keep original file copies unless explicitly designed.
- Store only data needed for the user's SOOM experience.
- Treat route, HR, cadence, and power as sensitive user data.
- Do not use FIT data for AI/model training.
- Do not share imported activity data publicly by default.
- Provide deletion behavior through existing workout/route deletion paths before adding cloud sync.

Server-side parsing is deferred until:

- privacy policy is updated
- retention rules are defined
- deletion behavior is defined
- data ownership is defined
- transport/storage security is reviewed
- user consent copy is designed

## Test Strategy

Parser feasibility tests:

- valid cycling FIT with route
- valid cycling FIT without route
- malformed FIT fails safely
- empty file fails safely
- oversized file fails before parse
- unsupported message combinations fail gracefully

Mapping tests:

- sport maps to cycling
- start/end/duration map correctly
- distance maps correctly
- calories maps when present
- route coordinates map to `WorkoutRoute`
- elevation maps when available
- HR/cadence/power summaries are available only when present

Route attach tests:

- FIT route attaches to matching HealthKit imported workout
- non-matching FIT does not attach automatically
- existing route is not replaced by default
- route persistence failure preserves summary
- attached route builds a route-backed `ProcessedWorkout`

Full import tests:

- FIT-only workout creates one `UnifiedWorkout`
- duplicate local Record workout prevents visible duplicate
- duplicate HealthKit imported workout is skipped or reviewed
- no-route FIT workout imports summary cleanly

Device QA:

- import sample ride from Garmin/Wahoo/Bryton/iGPSPORT/Magene/Coospo when available
- validate route display in Activity Detail
- validate Share card route display
- validate Profile aggregation counts once
- validate Recovery mapping does not crash

## Implementation Phases

### Phase 0: Collect Sample FIT Files

Goal:

- Build a representative test corpus before writing parser code.

Output:

- sample manifest
- expected field matrix
- privacy handling notes

### Phase 1: FIT Parser Feasibility Spike

Goal:

- Choose parser strategy.
- Decode enough sample files to prove route and summary extraction.

Output:

- parser strategy recommendation
- dependency/security review if a package is considered
- extraction report for sample files

### Phase 2: Extract Route + Summary Only

Goal:

- Build a safe extraction layer that returns summary and route data without mutating app state.

Output:

- parsed FIT activity model
- validation errors
- focused tests

### Phase 3: Attach FIT Route To Existing Workout

Goal:

- Attach route from a matching FIT file to an existing HealthKit imported workout.

Output:

- route attachment service or generalized file route attachment service
- match validation
- `routeMissingReason` clearing after success

### Phase 4: Full FIT Workout Import

Goal:

- Create a new `UnifiedWorkout` from a FIT file when no safe duplicate exists.

Output:

- full import pipeline
- duplicate guardrails
- route persistence
- `ProcessedWorkout` compatibility

### Phase 5: Sensor Streams

Goal:

- Persist and surface richer FIT data such as HR, cadence, power, elevation, and laps/events.

Output:

- stream storage model
- metric availability rules
- Activity Detail/Profile/Share/Recovery validation

## Next Recommendation

Start Phase 0 and Phase 1 together:

1. Collect representative cycling FIT files.
2. Create a sample manifest with expected fields.
3. Evaluate parser strategies against those files.
4. Choose a parser approach before adding dependencies or app code.
