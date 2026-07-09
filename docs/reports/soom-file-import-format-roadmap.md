# SOOM File Import Format Roadmap

Date: 2026-07-09

## Summary

SOOM should treat file import as two related but distinct product paths:

1. Attach route data to an existing imported workout.
2. Import a full workout from a user-selected file.

GPX Import v1 now covers the first route-only fallback path for Apple HealthKit imported workouts with missing route data. The next file priority should shift to FIT because cycling computers and cycling apps commonly save the original activity as `.fit`, and FIT can contain both the route and richer activity/sensor data.

## Current State

Implemented:

- `GPXRouteParser`
- `GPXRouteAttachmentService`
- Activity Detail `GPX 경로 가져오기` entry point
- Route attachment to existing Apple HealthKit imported workouts
- `routeMissingReason` clearing after successful route attach

Current limitation:

- GPX is useful for route attachment, but it is usually not the best original activity format for cycling devices.
- GPX generally cannot preserve the richer cycling data SOOM will need for cadence, power, lap/event structure, calories, and device-recorded summary fidelity.

## Format Positioning

### GPX

Role:

- Route-first fallback.
- Best for adding route geometry to an existing imported workout.

Typical data:

- route coordinates
- elevation when exported
- timestamps when exported

Weaknesses:

- weak sensor data support
- weak sport/workout summary structure
- poor activity-original fidelity
- no reliable calories, laps, events, cadence, or power in the v1 subset

SOOM use:

- Keep GPX as the simplest route-attachment path.
- Do not treat GPX as the primary full-workout cycling import format.

### FIT

Role:

- Activity-original import target, especially for cycling computers.
- Best next format for cycling route plus activity data.

Typical data:

- route coordinates
- distance
- duration
- sport type
- heart rate
- cadence
- power
- calories
- elevation
- laps/events depending on the file and device

Strengths:

- common output from cycling computers and device ecosystems
- best chance of preserving the original activity record
- supports richer metrics that SOOM already identifies as future data gaps

Weaknesses:

- binary format
- parser strategy requires more care than XML formats
- sampled stream persistence needs explicit scope and storage rules

SOOM use:

- Prioritize FIT parser/import planning next.
- Start with safe extraction of route plus summary metadata.
- Design both route attachment and full workout import before implementing broad sampled streams.

### TCX

Role:

- Useful fallback between GPX and FIT.
- Richer than GPX, usually less complete or less device-original than FIT.

Typical data:

- route coordinates
- heart rate
- cadence
- power when exported
- laps

Strengths:

- XML-based and easier to inspect than FIT
- useful when platforms export TCX but not FIT

Weaknesses:

- vendor/platform consistency varies
- may omit some original device details
- can be large and verbose

SOOM use:

- Plan after FIT.
- Keep as a compatibility fallback for users whose source apps export TCX more reliably than FIT.

## File Format Comparison

| Format | Route | Summary | Sensors | Best SOOM use | Priority |
| --- | --- | --- | --- | --- | --- |
| GPX | Strong for coordinates; elevation/time optional. | Weak; distance/duration may be derived from points/timestamps. | Weak in v1; extensions deferred. | Attach route to an existing imported workout. | P0 complete, physical QA next. |
| FIT | Strong when GPS was recorded. | Strong; distance, duration, sport, calories, laps/events often available. | Strong; HR, cadence, power, elevation can be present. | Cycling-first route attach and full workout import. | P0 planning, P1 parser feasibility/design. |
| TCX | Strong when exported with trackpoints. | Medium; includes laps and some activity structure. | Medium; HR/cadence/power can be present. | Fallback file import when FIT is unavailable. | P2 after FIT. |

## Supported Product Paths

### A. Attach Route To Existing Imported Workout

Target:

- A workout already exists in SOOM, usually through HealthKit summary import.
- The workout has no route because HealthKit did not expose `HKWorkoutRoute`.
- User has a route/activity file from the source app or cycling computer.

Behavior:

- User selects a file from Activity Detail.
- SOOM parses route geometry.
- SOOM attaches route to the existing `UnifiedWorkout.id`.
- SOOM does not create a duplicate workout.
- Existing workout summary remains the source of truth unless a later replacement flow is explicitly designed.

Format sequence:

1. GPX route attach v1.
2. FIT route attach.
3. TCX route attach.

### B. Import Full Workout From File

Target:

- The workout does not already exist in SOOM, or the file is more complete than HealthKit summary data.
- User has a FIT or TCX file that represents the original recorded activity.

Behavior:

- User selects an activity file.
- SOOM parses summary, sport, timing, route, and safe metrics.
- SOOM maps the activity into `UnifiedWorkout`.
- SOOM persists route through existing route persistence.
- SOOM runs duplicate/source-priority checks before adding a visible workout.

Format sequence:

1. FIT full workout import design.
2. FIT summary plus route import.
3. TCX full workout fallback.
4. Broader sampled stream persistence only after read-model/storage design.

## Recommended Priority

1. GPX route attach v1 physical-device QA.
2. FIT import planning.
3. FIT parser feasibility.
4. FIT route attach and full workout import design.
5. FIT route attach implementation.
6. FIT full workout import implementation.
7. TCX import planning.
8. TCX route attach/full workout fallback.
9. Strava and Wahoo feasibility spikes.
10. Garmin developer-program research.

Reasoning:

- GPX already solves route-only fallback and should be validated on device before expanding scope.
- FIT is more important than TCX for cycling devices because it can preserve the original workout record and sensor fields.
- TCX remains valuable but should not block FIT.
- OAuth/API integrations should follow file import because file import is user-controlled, local-first, and avoids platform policy dependencies.

## FIT Planning Scope

FIT planning should answer:

- Parser strategy: vetted library, generated decoder, or minimal internal decoder.
- Supported initial message types.
- Required sample files from cycling computers and external apps.
- Route coordinate extraction rules.
- Summary extraction rules.
- Sport mapping rules.
- Duplicate prevention for file-imported workouts.
- Route attachment versus full workout creation flow.
- Storage model for file origin metadata.
- Whether sampled streams are deferred or supported in a bounded first pass.

Recommended initial FIT fields:

- start date
- end date or duration
- sport type
- distance
- calories if present
- elevation gain if present
- route coordinates
- heart rate summary if safely present
- cadence/power summary if safely present

Defer unless explicitly scoped:

- full HR stream persistence
- full cadence stream persistence
- full power stream persistence
- lap/event UI
- route smoothing/snapping
- server upload
- provider account sync

## Privacy And Storage Rules

File import remains local-first:

- User selects the file.
- SOOM parses locally.
- SOOM does not upload the original file in v1.
- SOOM stores only data needed for the user's workout experience.
- Route and sensor data are treated as sensitive health/location data.
- Server sync, provider linking, retention, and deletion semantics need explicit design before upload.

Recommended future route/file metadata:

- file format: GPX, FIT, TCX
- import mode: route attachment or full workout import
- original filename hash
- coordinate count
- parser version
- imported at
- user-confirmed at
- route origin
- source device/app when present and safe to store

## Next Recommendation

Run GPX physical-device QA while starting FIT import planning.

FIT planning should precede implementation because the first FIT support decision determines whether SOOM is building:

- route-only extraction,
- route attachment to an existing workout,
- full workout import,
- or all of the above in staged form.
