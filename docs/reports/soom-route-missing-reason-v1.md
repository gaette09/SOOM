# SOOM Route Missing Reason V1

Date: 2026-07-09

## Summary

Implemented route missing status for imported workouts so HealthKit summary imports can explicitly explain why route data is unavailable and prepare for GPX Import v1.

This keeps the existing route strategy intact:

- HealthKit `HKWorkoutRoute` remains first.
- Missing HealthKit route data is non-fatal.
- Local Record route behavior is unchanged.
- GPX/FIT/TCX and provider integrations remain deferred.

## Files Changed

- `SOOM/Features/UnifiedHealth/UnifiedWorkout.swift`
- `SOOM/Features/UnifiedHealth/Persistence/UnifiedWorkoutRecord.swift`
- `SOOM/Features/UnifiedHealth/Persistence/UnifiedWorkoutPersistenceMapper.swift`
- `SOOM/Features/HealthKit/HealthKitWorkoutImportPipeline.swift`
- `SOOM/Features/Workout/ProcessedWorkout.swift`
- `SOOM/Features/Workout/ProcessedWorkoutBuilder.swift`
- `SOOM/Features/Activity/DetailViews.swift`
- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutLibraryView.swift`
- `SOOMTests/HealthKitWorkoutImportPipelineTests.swift`
- `SOOMTests/ProcessedWorkoutBuilderTests.swift`
- `docs/reports/soom-route-missing-reason-v1.md`

## Route Missing Reason Cases

Added `WorkoutRouteMissingReason`:

- `none`
- `notApplicable`
- `healthKitRouteUnavailable`
- `routeFetchFailed`
- `routePersistenceFailed`
- `externalSourceRouteNotShared`
- `userSkippedRouteAttachment`
- `unknown`

`UnifiedWorkout` now carries `routeMissingReason`, persisted through `UnifiedWorkoutRecord.routeMissingReasonRaw`.

`ProcessedWorkout` now exposes:

- `hasRoute`
- `routeMissingReason`

Renderable persisted routes clear route missing state at the processed layer.

## HealthKit Missing Route Behavior

HealthKit summary import remains successful when route handling fails or route data is unavailable.

Route status rules:

- `fetchRoute` returns `nil`: `healthKitRouteUnavailable`
- route lookup cannot reconnect to source workout: `externalSourceRouteNotShared`
- route fetch throws: `routeFetchFailed`
- route persistence throws: `routePersistenceFailed`
- route persists successfully: `none`

The import pipeline saves workout summaries first, then attempts optional route persistence, then updates stored workouts with any route missing reason.

## Record / Local Behavior Preservation

SOOM local Record workouts still default to `routeMissingReason = .none`.

Location-denied or time-only local workouts remain valid no-route workouts. They are not labeled as external route failures.

Record route persistence and Mapbox style behavior were not changed.

## Activity Detail Fallback Behavior

Imported workouts with actionable route missing reasons show a calm fallback card:

- “Apple Health에서 운동은 가져왔지만 경로 데이터는 포함되지 않았습니다.”
- “원본 앱에서 GPX 파일을 가져오면 경로를 추가할 수 있습니다.”

The existing no-route behavior still avoids the map sheet when no route exists, so Activity Detail does not show a broken or blank map.

## GPX Import Readiness

The fallback card includes a non-interactive “경로 파일 가져오기 준비 중” placeholder.

No file picker, GPX parser, Strava/Wahoo/Garmin integration, scraping, login automation, HealthKit write, background sync, build bump, or TestFlight upload was added.

## Tests / Build Results

Focused test command attempted:

```sh
xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SOOMTests/HealthKitWorkoutImportPipelineTests -only-testing:SOOMTests/ProcessedWorkoutBuilderTests
```

Result:

- Build compilation succeeded after fixing a font weight issue.
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

Implement GPX Import v1:

1. Let the user select a GPX file from a route-missing imported workout.
2. Parse route coordinates locally.
3. Validate at least two coordinates.
4. Attach the route to the selected imported workout.
5. Persist through existing SOOM route persistence.
6. Reload Activity Detail and Share route display.
