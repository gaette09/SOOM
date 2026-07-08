# SOOM HealthKit Read Phase 1E Device QA Checklist

Date: 2026-07-08

## Summary

Phase 1E is a physical-device QA and permission-state validation gate for the completed HealthKit Read Phase 1A-1D work.

Scope remains manual, read-only, local-first, and summary-first:

`Apple Health / HealthKit -> HealthKitWorkout -> UnifiedWorkout -> UnifiedWorkoutStore -> optional WorkoutRoute -> ProcessedWorkoutBuilder -> Activity / Share / Profile / Recovery`

This checklist does not authorize new HealthKit code, new permissions, UI changes, background sync, HealthKit write-back, third-party integrations, build-number changes, or TestFlight upload.

## Preconditions

- Use a physical iPhone with Health app data available.
- Install the current SOOM build that includes commits:
  - `75b22f1 feat(healthkit): harden workout summary import`
  - `238ca1b feat(healthkit): add import duplicate guardrails`
  - `b7d2fb9 feat(healthkit): import workout routes safely`
  - `b3e252e test(healthkit): validate imported workouts across surfaces`
- Confirm the app starts cleanly before any HealthKit prompt appears.
- Confirm no HealthKit write permission is requested.
- Confirm no background sync claim appears in copy.
- Prepare Apple Health workout samples:
  - cycling workout with distance and calories
  - running workout with distance
  - walking workout
  - workout with route
  - workout without route
  - workout missing calories if available
  - workout missing heart rate if available
  - one SOOM local workout that closely matches a HealthKit workout for duplicate testing

## Permission State Matrix

### Not Requested

Checklist:

- Fresh install or reset HealthKit permission state for SOOM.
- Launch SOOM.
- Open core tabs before tapping any HealthKit import/connect action.
- Confirm no HealthKit prompt appears automatically.
- Tap the explicit HealthKit import/connect action.
- Confirm the permission prompt appears only after that action.

Expected:

- App remains usable before permission.
- Record, Activity, Profile, Share, and Recovery do not block on HealthKit.
- Copy explains read access in user-facing language.

Blockers:

- Prompt appears on launch or unrelated tab entry.
- App blocks local-first use before permission.
- Copy implies write-back, background sync, or automatic import.

### Allowed

Checklist:

- Grant requested HealthKit read access.
- Run manual import.
- Confirm import completes without crash.
- Confirm imported workouts appear in Activity once.

Expected:

- Read-only import works for available workout data.
- No HealthKit write request appears.
- Missing optional metrics remain unavailable instead of fake zeros.

Blockers:

- App requests HealthKit write access.
- Manual import crashes.
- Imported workout data is visibly inconsistent across surfaces.

### Denied

Checklist:

- Deny HealthKit access from the system prompt.
- Return to SOOM.
- Trigger manual import again.
- Navigate Activity, Profile, Share, Recovery, and Record.

Expected:

- App does not crash.
- Local SOOM workouts remain usable.
- User sees calm recoverable copy.
- Record save does not request HealthKit write permission.

Blockers:

- Denied permission crashes the app.
- App loops prompts or blocks core navigation.
- App shows developer/debug language.

### Partially Allowed

iOS can expose granular Health permissions depending on OS version and Health data type. Validate partial access when the system UI allows it.

Checklist:

- Allow workouts but deny route if the system exposes route separately.
- Allow workouts but deny heart rate if the system exposes heart rate separately.
- Allow workouts but deny active energy/calories if the system exposes calories separately.
- Run manual import after each partial state.

Expected:

- Workout summary imports when workout read access is allowed.
- Route import is skipped when route access is unavailable.
- Missing heart rate or calories remain missing, not zero-filled.
- No-route or partial-metric workouts remain coherent in Activity Detail, Share, Profile, and Recovery.

Blockers:

- Partial permission causes import failure for the whole workout when summary data is available.
- Missing optional data is displayed as fake measured data.
- Route-denied state crashes route-backed import.

### Revoked After Allowing

Checklist:

- Grant HealthKit read access and import one workout.
- Go to iOS Settings or Health app permission controls.
- Revoke SOOM Health access.
- Reopen SOOM.
- Run manual import again.
- Open previously imported workout details and downstream surfaces.

Expected:

- Existing local imported workouts remain available.
- New HealthKit read/import attempt is handled gracefully.
- Activity Detail, Share, Profile, and Recovery do not crash.
- Copy does not imply background access still exists.

Blockers:

- Revoked permission crashes import or app launch.
- Existing local imported workouts disappear unexpectedly.
- App claims sync/import success when HealthKit access is revoked.

## Manual Import QA

For each case, record:

- device / iOS version
- SOOM build
- Health workout date and sport
- Health workout source device, if visible
- expected distance, duration, calories, and route presence
- actual Activity / Detail / Share / Profile / Recovery behavior
- pass/fail and screenshots for failures

### Cycling Workout From Apple Health

Checklist:

- Import a cycling workout.
- Confirm sport maps to cycling.
- Confirm Activity Detail primary metric is speed.
- Confirm distance and duration match Health within expected rounding.
- Confirm calories appear only when present.

Expected:

- Cycling appears once in Activity.
- Share card uses cycling distance, speed, and duration.
- Profile cycling totals update once.
- Recovery maps it as a ride input and does not crash.

### Running Workout From Apple Health

Checklist:

- Import a running workout.
- Confirm sport maps to running.
- Confirm Activity Detail primary metric is pace.
- Confirm distance and duration match Health within expected rounding.

Expected:

- Running appears once in Activity.
- Share card uses running distance, pace, and duration.
- Profile running totals update once.
- Recovery maps it as a run input and does not crash.

### Walking Workout From Apple Health

Checklist:

- Import a walking workout.
- Confirm sport remains walking.
- Confirm Activity Detail uses speed behavior from `ProcessedWorkout`.

Expected:

- Walking appears once in Activity.
- Share card uses walking distance, speed, and duration.
- Profile walking totals update once.
- Recovery remains stable with the current walk-to-run-like recovery mapping limitation.

### Workout With Route

Checklist:

- Import a HealthKit workout that has route data.
- Open Activity Detail.
- Open Share composer.

Expected:

- Summary import succeeds.
- Route appears in Activity Detail if route persistence succeeds.
- Share route visuals use the existing route path if route data exists.
- Route-derived distance/elevation may fill missing summary values through `ProcessedWorkoutBuilder`.

Non-blocking:

- Route unavailable or route fetch failure is acceptable if summary import succeeds and UI fallback is clean.

Blockers:

- Route failure prevents summary import.
- Route-backed detail or share screen crashes.
- Route display uses obviously wrong workout identity.

### Workout Without Route

Checklist:

- Import a HealthKit workout with no route.
- Open Activity Detail and Share.

Expected:

- Summary import succeeds.
- Activity Detail uses no-route fallback cleanly.
- Share card still shows distance/duration/pace or speed when summary metrics exist.
- No route badge or route claim appears.

### Missing Calories

Checklist:

- Import a workout with no active energy value if available.
- Check Activity Detail and Share optional stat areas.

Expected:

- Calories remain unavailable or placeholder.
- No fake `0kcal` measured value appears.
- Profile and Recovery remain stable.

### Missing Heart Rate

Checklist:

- Import a workout with no heart rate if available.
- Check Activity Detail, Share, and Recovery.

Expected:

- Heart rate remains unavailable or placeholder.
- Recovery does not crash and uses safe fallback input.
- No copy implies heart rate was measured.

### Duplicate SOOM Local And HealthKit Workout

Checklist:

- Record or create a SOOM local workout.
- Ensure Apple Health contains a workout with same sport, similar start/end time, similar duration, and similar distance.
- Run HealthKit manual import.

Expected:

- SOOM local workout wins.
- Matching HealthKit workout is skipped.
- Activity, Profile, Share, and Recovery do not show duplicate visible sessions.

Blocker:

- Visible duplicate appears for a conservative same-session match. Patch Phase 1B.

### HealthKit-Only Workout

Checklist:

- Import a HealthKit workout with no matching SOOM local workout.

Expected:

- Workout imports once.
- Source is treated as Apple Health internally.
- Activity, Detail, Share, Profile, and Recovery remain consistent.

### Re-Import Same HealthKit Workout

Checklist:

- Import a HealthKit workout.
- Run manual import again.
- Check Activity and Profile counts.

Expected:

- Existing `externalId + source` upsert prevents duplicate stored records.
- Activity shows one visible workout.
- Profile totals do not double count.

Blocker:

- Same HealthKit workout appears twice after re-import.

## Surface Validation On Device

Activity:

- Imported workout appears once.
- Sport label/icon matches cycling, running, or walking.
- Route badge appears only when route exists.

Activity Detail:

- Distance, duration, pace or speed match Health data within expected rounding.
- Route-backed workout shows route if route persistence succeeds.
- No-route workout uses fallback cleanly.
- Missing calories, heart rate, or elevation show placeholders/unavailable states, not fake measured zeros.

Share:

- Share card uses imported workout distance, duration, and pace/speed from the processed path.
- Optional metrics are omitted or placeholder-backed when missing.
- Route visual appears only if route exists.
- No private/sensitive Health wording leaks into public share copy.

Profile:

- Profile aggregation updates once per imported workout.
- Re-import does not double count.
- Duplicate SOOM local plus HealthKit session does not inflate totals.
- Time-only or missing-distance workouts count as activity but do not add fake distance.

Recovery:

- Recovery screen or preview does not crash with imported workouts.
- Missing heart rate/calories do not create broken values.
- Cycling maps to ride-like recovery input; running maps to run-like input.
- Walking remains stable with the current recovery taxonomy limitation.

Permission Denied / Revoked:

- Denied permission does not crash.
- Revoked permission is handled gracefully.
- Previously imported local records remain visible.
- App does not claim import/sync success without access.

## Privacy And Copy Checks

Pass criteria:

- Copy clearly explains Apple Health read access.
- Copy uses product language, not developer or API terms.
- Copy does not imply HealthKit write-back.
- Copy does not imply background sync.
- Copy does not imply Garmin, Samsung Health, Google Health, or Health Connect integration.
- Denied/revoked states are recoverable and calm.

Blockers:

- Scary, overly technical, or blame-heavy permission copy.
- Any user-facing claim that SOOM writes to Apple Health.
- Any user-facing claim that import happens in the background.
- Any prompt loop after denial or revocation.

## Decision Rules

- If permission-state QA and manual import QA pass, Phase 1 HealthKit read is ready for limited TestFlight validation.
- If duplicates appear, block release validation and patch Phase 1B duplicate/source-priority guardrails.
- If routes fail but summary import works, document as non-blocking unless the UI breaks or makes a false route claim.
- If denied or revoked permission crashes, block release validation.
- If imported data appears inconsistent across Activity Detail, Share, Profile, or Recovery, inspect `ProcessedWorkoutBuilder` and HealthKit mapping before UI polish.
- If HealthKit write permission appears, block immediately.
- If background sync behavior or claims appear, block immediately.

## Evidence Template

Use one row per scenario.

| Scenario | Permission State | Expected | Actual | Result | Evidence |
| --- | --- | --- | --- | --- | --- |
| Cycling import | Allowed | Appears once with speed |  |  |  |
| Running import | Allowed | Appears once with pace |  |  |  |
| Walking import | Allowed | Appears once as walking |  |  |  |
| Route-backed workout | Allowed route | Route shown if available |  |  |  |
| No-route workout | Allowed workout | Fallback clean |  |  |  |
| Missing calories | Partial/missing data | Placeholder/unavailable |  |  |  |
| Missing heart rate | Partial/missing data | Placeholder/unavailable |  |  |  |
| Local duplicate | Allowed | Local wins, HK skipped |  |  |  |
| HealthKit-only | Allowed | Imports once |  |  |  |
| Re-import | Allowed | Upsert/no duplicate |  |  |  |
| Denied | Denied | No crash |  |  |  |
| Revoked | Revoked | Graceful handling |  |  |  |

## Final Sign-Off

Phase 1E passes only when:

- all permission states are validated or documented as unavailable on the tested iOS version
- cycling, running, and walking imports are validated on device
- route and no-route behaviors are validated
- duplicate and re-import behaviors are validated
- Activity Detail, Share, Profile, and Recovery remain consistent
- no HealthKit write, background sync, or new permission behavior is observed
