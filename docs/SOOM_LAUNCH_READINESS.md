# SOOM Launch Readiness

Purpose: summarize SOOM's internal TestFlight readiness after Club RLS hardening and launch documentation.

## Completed

- Record fullscreen map launch.
- READY long-press drag-select start flow.
- Record route/distance local persistence.
- Activity workout library and detail interpretation.
- Share card composer and route-first card foundation.
- Profile workout aggregation from UnifiedWorkoutStore.
- Club domain, local persistence, Supabase service foundation, and RLS-hardened migration draft.
- Purple accent system across main surfaces.
- Local secrets setup for Mapbox and weather keys.
- TestFlight readiness documentation and manual QA plans.

## In Progress

- Staging-only Club Supabase migration validation.
- Real-device share export QA.
- Real-device location/weather QA.
- TestFlight manual pass across Record, Activity, Share, Profile, Club, and Feed.

## Deferred

- Weather AQI/provider upgrade.
- Club ranking engine.
- Club challenge progress engine.
- HealthKit write.
- Background GPS smoothing.
- Direct Instagram Story API integration.
- Production Club migration.

## Blockers

No code-level blocker is currently identified for an internal TestFlight build.

Staging dependency:

- Club Supabase migration must pass staging smoke tests before it is considered production-ready.

## Risk Level

Overall risk: Medium-low for internal TestFlight.

Main risk areas:

- Share export differences on real devices.
- Location-denied and time-only workout edge cases.
- Club RLS behavior in staging.
- Weather key/network variability.

## Static Check Results

Latest sweep:

- Developer terms still appear in code/docs/tests, mostly as internal symbols, docs, or fallback implementation names.
- User-facing copy must still be manually QAed because static search cannot distinguish every Swift property name from visible UI.
- TODO entries remain in recovery/import planning areas and are known deferred work.
- No real Mapbox token prefix was found in committed files.
- `LocalSecrets.xcconfig` is referenced only as an ignored local setup path/example, not as a committed real secret.

## Launch Readiness Estimate

Internal TestFlight readiness: 91%.

Production readiness: not yet; Club staging migration, real-device QA, and backend rollout decisions remain.

## Recommended Launch Sequence

1. Build and archive internal TestFlight candidate.
2. Run `docs/SOOM_TESTFLIGHT_QA.md` on at least one real iPhone.
3. Apply Club migration to staging only.
4. Run `docs/SOOM_CLUB_SMOKE_TEST.md`.
5. Confirm permission flows with Location denied/granted.
6. Confirm share image save and iOS share sheet behavior.
7. Confirm no user-facing developer copy appears in normal flows.
8. Invite small internal beta group.
