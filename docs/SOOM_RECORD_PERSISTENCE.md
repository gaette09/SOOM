# SOOM Record Persistence

## Scope

Record persistence is local-first. A saved Record workout can now carry minimum route and distance data when foreground location updates are available during the session. This foundation supports Activity, Activity Detail, and Share surfaces without adding cloud sync, HealthKit write, background tracking, or route recommendation backend work.

## Saved Data

Record sessions can capture:

- Route coordinates with latitude, longitude, and optional timestamp.
- Start and end coordinates derived from the captured route.
- Accumulated distance in meters from sequential coordinate distance.
- A local `WorkoutRoute` linked to the saved `UnifiedWorkout`.

If location permission is denied, unavailable, or no usable route coordinates arrive, SOOM still saves a time-only local workout.

## Distance Foundation

Distance is accumulated locally from adjacent coordinates during the active session. v1 intentionally avoids:

- Background location tracking.
- Advanced GPS smoothing.
- Route snapping.
- Navigation or directions engines.
- Remote route writes.

This means distance is useful as a local foundation, but production GPS quality tuning remains deferred.

## Save Flow

When Stop creates a finish summary:

- `distanceMeters` is included only when captured distance is greater than zero.
- `capturedRoute` is true only when at least two route coordinates exist.
- Saving writes the `UnifiedWorkout` first.
- If a route exists, saving also writes the linked local `WorkoutRoute`.

Saved route data remains private and local by default.

## Consumer Boundaries

Activity can show route availability and distance when present.

Activity Detail prefers the persisted route for the hero map and route-aware interpretation surfaces.

Share cards prefer the persisted route over generated fallback route previews when a route is available.

Profile aggregation remains deferred. The saved distance and route foundation is ready for a later profile identity aggregation pass.

## Privacy

Route coordinates are not uploaded to Supabase in this version.

Feed publish, public route sharing, start/end privacy masking, and cloud sync remain future work.

## Deferred

- Production-grade GPS tracking engine.
- Background location mode.
- Route simplification/smoothing.
- Start/end privacy masking for public exports.
- HealthKit workout write.
- Supabase route sync.
- Profile movement identity aggregation from saved workouts.
