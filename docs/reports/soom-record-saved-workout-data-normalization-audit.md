# SOOM Record Saved Workout Data Normalization Audit

Date: 2026-07-08

## Context

`ProcessedWorkout` is now used by Activity Detail, Share, Profile aggregation, and Recovery preview. The next data quality risk is the local Record save path that creates SOOM-owned `UnifiedWorkout` rows.

This audit reviews Record save behavior only. No app code was changed.

## Files Inspected

- `SOOM/Features/Activity/RecordWorkoutSaveFlow.swift`
- `SOOM/Features/Activity/RecordWorkoutSession.swift`
- `SOOM/Features/Activity/RecordView.swift`
- `SOOM/Features/Activity/RecordLocationState.swift`
- `SOOM/Features/Activity/RecordLocationManager.swift`
- `SOOM/Features/Activity/RecordLaunchPlan.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkout.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutType.swift`
- `SOOM/Features/UnifiedHealth/Persistence/UnifiedWorkoutRecord.swift`
- `SOOM/Features/UnifiedHealth/Persistence/UnifiedWorkoutPersistenceMapper.swift`
- `SOOM/Features/UnifiedHealth/Persistence/UnifiedWorkoutStore.swift`
- `SOOM/Features/Workout/ProcessedWorkout.swift`
- `SOOM/Features/Workout/ProcessedWorkoutBuilder.swift`
- `SOOM/Features/Workout/WorkoutRoute.swift`
- `SOOM/Features/Workout/WorkoutRouteMapper.swift`
- `SOOM/Features/Workout/WorkoutRoutePersistenceStore.swift`
- `SOOMTests/RecordWorkoutSaveFlowTests.swift`
- `SOOMTests/RecordWorkoutSessionTests.swift`
- `SOOMTests/ProcessedWorkoutBuilderTests.swift`
- `SOOMTests/WorkoutRoutePersistenceStoreTests.swift`

## Current Record Save Flow

1. `RecordWorkoutSessionStarter.start(sport:locationState:)` creates a local-first `RecordWorkoutSession`.
2. If location is authorized and a coordinate exists, the session starts with a one-point `RecordRouteCapture`.
3. `RecordView.recordLocationIfNeeded(from:)` appends location samples while the session is active.
4. `RecordWorkoutSession.recordingLocation(_:at:speedMetersPerSecond:)` updates:
   - route coordinates
   - accumulated distance
   - last/start coordinate fields
   - current speed
   - max speed
5. Tapping end marks the session `.finished`.
6. `RecordWorkoutSummaryBuilder.makeSummary(from:)` creates `RecordWorkoutSummary` only for finished sessions.
7. `RecordWorkoutSaver.save(_:)` maps summary to `UnifiedWorkout`, saves it through `UnifiedWorkoutStore`, then saves `WorkoutRoute` if available.
8. `RecordView.saveFinishedSession(_:)` uses `SwiftDataUnifiedWorkoutStore` and `SwiftDataWorkoutRoutePersistenceStore`.

## Current Saved Fields

Saved into `UnifiedWorkout` from Record:

- `id`: session/summary ID
- `externalId`: `nil`
- `source`: `.soomLocal`
- `workoutType`: from selected `RecordSportMode`
- `startDate`: session start
- `endDate`: finished date
- `durationSeconds`: elapsed time at finish
- `distanceMeters`: accumulated route distance when greater than zero, otherwise `nil`
- `activeEnergyKcal`: `nil`
- `averageHeartRate`: `nil`
- `maxHeartRate`: `nil`
- `averageSpeedMetersPerSecond`: `distance / duration` when distance exists and duration is positive, otherwise `nil`
- `elevationGainMeters`: `nil`
- `dataQuality`: `.partial`
- `isExcludedFromAnalysis`: `false`
- `createdAt` / `updatedAt`: save time

Saved into `WorkoutRoute` when route exists:

- `workoutId`
- `source`: `.soomLocal`
- coordinates with latitude, longitude, timestamp
- total distance meters
- bounds derived by `WorkoutRoute`
- created date

Route altitude/elevation:

- Record route coordinates do not currently carry altitude.
- Record route `totalElevationGain` is not populated.

## Fields Required By ProcessedWorkout

`ProcessedWorkoutBuilder` can use:

- required identity/source fields:
  - `id`
  - `externalId`
  - `source`
  - `workoutType`
  - `startDate`
  - `endDate`
  - `durationSeconds`
  - `isExcludedFromAnalysis`
  - `dataQuality`
- optional metrics:
  - `distanceMeters`
  - `averageSpeedMetersPerSecond`
  - `activeEnergyKcal`
  - `averageHeartRate`
  - `maxHeartRate`
  - `elevationGainMeters`
- optional route:
  - coordinates
  - total distance
  - total elevation gain
  - bounds

Record currently satisfies the required identity/time fields and route-backed distance for location-authorized sessions. Sensor and elevation fields are absent.

## Fields Missing Or Unreliable

Must-fix or verify soon:

- Route persistence is separate from `UnifiedWorkout`; every display surface that wants route-derived fallback must receive or fetch the route explicitly.
- Saved `UnifiedWorkout.distanceMeters` and saved `WorkoutRoute.totalDistanceMeters` should remain identical for route-backed Record workouts.
- `averageSpeedMetersPerSecond` is average speed from `distance / duration`, not a sampled moving-speed average.
- Time-only workouts save `distanceMeters == nil`, which is valid but must remain consistently handled by Activity Detail, Share, Profile, and Recovery.

Known unavailable metrics:

- heart rate
- max heart rate
- cadence
- power
- calories
- elevation gain
- altitude in route points
- pause-adjusted moving time
- GPS accuracy metadata

Potential reliability issues:

- Duration currently uses wall-clock elapsed time from start to finish. Pause/resume does not subtract paused time.
- Distance accumulation uses Haversine distance between accepted coordinates and ignores GPS accuracy.
- Location manager uses `distanceFilter = 10` and nearest-ten-meters accuracy, which is acceptable for MVP but not advanced GPS quality.
- Route capture starts only with an authorized coordinate; denied/location-missing sessions become time-only.
- Current/max speed is tracked in active session HUD but not persisted except average speed.

## Cycling Coverage

Current local Record save supports:

- sport type: `.cycling`
- duration
- route-backed distance when location is available
- average speed derived from total distance/duration
- route coordinates
- time-only fallback

Missing:

- cycling cadence
- cycling power
- heart rate
- calories
- elevation gain
- moving time
- sampled speed stream

Risk:

- Share/Profile/Activity can show distance and speed, but advanced cycling metrics remain placeholders or missing.
- Recovery uses fallback HR and calorie behavior, so cycling recovery load is an MVP estimate.

## Running Coverage

Current local Record save supports:

- sport type: `.running`
- duration
- route-backed distance when location is available
- pace can be derived by `ProcessedWorkoutBuilder` from distance/duration
- average speed saved from distance/duration
- route coordinates
- time-only fallback

Missing:

- heart rate
- cadence/step rate
- calories
- elevation gain
- moving time
- splits
- sampled pace stream

Risk:

- Running Activity Detail and Share can derive pace when distance exists.
- Time-only running workouts show movement placeholders, which is acceptable but should be QA'd.

## Walking Coverage

Current local Record save supports:

- sport type: `.walking`
- duration
- route-backed distance when location is available
- average speed derived from distance/duration
- route coordinates
- time-only fallback

Missing:

- heart rate
- step cadence
- calories
- elevation gain
- moving time

Risk:

- Walking uses speed as primary processed metric, which is supported when distance exists.
- Walking recovery type currently falls back to run-like recovery behavior through the Recovery mapper, by design from earlier audits.

## Time-Only Workout Behavior

Supported today:

- Record can start without location permission.
- Finished session creates a summary.
- Saved workout has duration and sport, but `distanceMeters == nil`.
- No route is saved.
- Tests cover saving time-only workouts without location permission.

ProcessedWorkout behavior:

- duration is measured.
- distance is missing.
- speed/pace are missing or unsupported depending sport.
- display surfaces should use placeholders such as distance pending/time-only copy.

Risk:

- Share transparent cards and Profile aggregation must avoid treating missing distance as zero-distance performance.
- Recovery should remain stable because current score uses duration, fallback HR, calories, effort/load formulas, not visible route distance.

## Location Denied Behavior

Supported today:

- Record start is local-first and allowed without location authorization.
- `RecordLocationState.locationButtonAction` keeps fallback for denied/restricted/unknown.
- Session starts without route capture if no authorized coordinate exists.
- Save flow creates a time-only `UnifiedWorkout`.

Risk:

- Users may expect a map route but only receive time-only saved data.
- Activity Detail no-route fallback must remain coherent.

## Route-Backed Workout Behavior

Supported today:

- Authorized coordinate seeds route capture.
- Subsequent active location updates append route points.
- Segments shorter than `0.5m` are ignored.
- `RecordWorkoutSummary.distanceMeters` comes from accumulated route distance.
- `RecordWorkoutSaver` saves both `UnifiedWorkout.distanceMeters` and `WorkoutRoute.totalDistanceMeters`.
- Tests assert route and workout distance match.

Missing:

- altitude/elevation gain
- route accuracy/source quality metadata
- privacy masking at save time
- route simplification/smoothing
- moving-time calculation

Risk:

- Route-derived fallback can differ only if future code saves route distance but fails to save workout distance; tests currently guard the local Record path.
- Advanced route quality is deferred and should not block ProcessedWorkout normalization.

## Missing Metric Fallback Behavior

Expected `ProcessedWorkout` fallbacks:

- no distance: distance state missing and display placeholder
- no HR: average/max heart rate missing and display `—`
- no calories: display `—`
- no elevation: display `—`
- no speed/pace: placeholder unless derivable from distance/duration
- route missing: no route badge/fallback map behavior

This is generally safe, but surfaces must avoid converting nil metrics into misleading zeros.

## Risks For Display Surfaces

Activity Detail:

- Safe for duration, sport, route, distance, speed/pace when route distance exists.
- Missing HR/elevation/calories should show fallbacks.
- Time-only detail must avoid broken stat tiles.

Share:

- Transparent metric cards need stable placeholders when distance/pace/speed is missing.
- Route-backed cards need route fetch; saved `UnifiedWorkout` alone is not enough for route line rendering.

Profile:

- Total distance should exclude missing-distance workouts from distance sums.
- Time-only workouts should still count where workout count/activity count expects them.

Recovery:

- Preview provider now uses ProcessedWorkout path.
- Local Record workouts without HR/calories use existing fallback formulas.
- Recovery score remains an estimate until sensor/external data exists.

## Recommended Normalization Changes

Minimal safe Record save improvements:

1. Add a small `RecordWorkoutSaveNormalizationPolicy` or equivalent helper.
   - sanitize positive duration, distance, speed
   - keep unavailable metrics as `nil`
   - centralize data quality decisions

2. Add explicit tests for `ProcessedWorkoutBuilder` output from saved Record workouts.
   - cycling route-backed
   - running route-backed
   - walking route-backed
   - time-only
   - location denied

3. Confirm route/workout distance consistency at the mapper level.
   - if route is saved, `UnifiedWorkout.distanceMeters` should match `WorkoutRoute.totalDistanceMeters`
   - if no route is saved, `distanceMeters` should remain `nil`

4. Add pause-duration decision before changing duration math.
   - current behavior uses elapsed wall-clock duration
   - if moving time is desired, define and test it separately

5. Keep missing sensors as nil.
   - do not fake calories, HR, cadence, or elevation
   - preserve clear missing-data rules for ProcessedWorkout

6. Consider persisting average/max speed only if it is product-relevant.
   - average speed is already saved as distance/duration
   - max/current speed are currently HUD-only and not part of UnifiedWorkout

## Must-Fix Data Gaps Before Production Provider Expansion

- Add focused tests that build `ProcessedWorkout` from Record-saved `UnifiedWorkout` plus optional route and assert expected metric availability.
- Ensure every route-backed Record save persists both workout distance and route distance consistently.
- Confirm time-only workouts remain valid and visible across Activity Detail, Share, Profile, and Recovery.
- Document that Record-saved workouts are `.partial` quality and sensor-light.

## Future / Deferred Work

Explicitly deferred:

- Garmin/Samsung/Google integration
- full HealthKit write
- advanced GPS smoothing
- route snapping
- route privacy masking at save time
- pause-adjusted moving time
- HR/cadence/power/calorie sensor integration
- elevation calculation
- advanced charts
- UI polish
- TestFlight upload

## Recommended Next Implementation Scope

Implement a narrow Record saved-workout normalization test pass:

- add tests around `RecordWorkoutSaver` plus `ProcessedWorkoutBuilder`
- verify route-backed and time-only saved workouts become coherent `ProcessedWorkout`
- add a small normalization helper only if current mapper rules begin duplicating or diverging
- do not change UI or external integrations

This should happen before migrating production Recovery to saved workouts or doing further UI polish based on Record-generated data.

## Verification

- Documentation-only change.
- No app code modified.
- No build run, per task rule.
- `git diff --check`: passed.
- `git status --short`: only this new audit file before commit.
