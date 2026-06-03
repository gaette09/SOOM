# SOOM Known Issues

Purpose: track known deferred work for internal TestFlight so expected limitations do not look like accidental regressions.

## Current Deferred Items

### AQI Provider Upgrade

Weather has fallback-first behavior and OpenWeather foundation. AQI/provider sophistication remains deferred.

### Club Ranking Engine

Club rankings have domain/service/UI foundation. Real ranking calculation from workout data is deferred.

### Club Challenge Engine

Challenge catalog and remaining-action copy exist. Real progress calculation engine is deferred.

### HealthKit Write

Record save is local-first. Writing completed workouts back to HealthKit is deferred.

### Background GPS Smoothing

Record route capture stores active-session coordinates. Background GPS, smoothing, filtering, and reconnect behavior are deferred.

### Direct Instagram Story Integration

Share uses image export and iOS share sheet guidance. Direct Instagram Story API integration is deferred.

### Club Staging Migration

Club Supabase migration is prepared and hardened but not yet applied to production. Staging smoke test is required first.

## Not Blockers For Internal TestFlight

- Local-first fallback when remote services are unavailable.
- Time-only workouts when location is denied.
- Share through iOS share sheet instead of direct Story API.
- Club ranking/challenge data shown as foundation until staging backend is validated.

## Watch Closely

- Share export on real devices.
- Location denial copy and time-only save copy.
- Club RLS behavior after staging migration.
- Profile aggregation for users with only time-based workouts.
