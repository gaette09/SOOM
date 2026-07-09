# SOOM GPX Import V1 Activity Detail Entry

Date: 2026-07-09

## Summary

Implemented GPX Import v1 Phase 3: a user-initiated Activity Detail entry point for attaching GPX routes to supported imported workouts that already show the route-missing fallback.

This phase keeps the scope narrow:

- No FIT or TCX import.
- No Strava, Wahoo, Garmin, or other provider integration.
- No server upload.
- No local Record route behavior change.
- No Mapbox style URI change.
- No build bump or TestFlight upload.

## Files Changed

- `SOOM/Features/Activity/ActivityDetailGPXRouteImport.swift`
- `SOOM/Features/Activity/DetailViews.swift`
- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutLibraryView.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutLibraryViewContainer.swift`
- `SOOMTests/ActivityDetailGPXRouteImportTests.swift`
- `SOOM.xcodeproj/project.pbxproj`
- `docs/reports/soom-gpx-import-v1-activity-detail-entry.md`

## Entry Point Behavior

The existing Activity Detail route-missing card now shows:

- Button: `GPX 경로 가져오기`
- Help text: `원본 앱에서 GPX 파일을 내보내면 이 운동에 경로를 추가할 수 있습니다.`

The action is only supplied for eligible imported workouts:

- source is `appleHealthKit`
- no persisted route is currently loaded
- `routeMissingReason` is actionable for route attachment

The action is not supplied for local Record workouts, route-backed workouts, or workouts with non-actionable route state.

## File Importer Behavior

Activity Detail uses SwiftUI `fileImporter` from the existing route-missing fallback card.

Allowed picker content types:

- custom GPX type when iOS can infer it from `.gpx`
- `.xml`
- `.data`

Before reading the selected file, SOOM validates that the selected URL has a `.gpx` extension. This keeps `.xml` and `.data` picker fallback broad enough for document providers while still enforcing GPX-only import in app logic.

File handling:

- User-selected file only.
- Security-scoped access is started and stopped around the read.
- The file is read locally into `Data`.
- The original GPX file is not copied or uploaded.
- `GPXRouteAttachmentService` performs parsing and persistence.

## Success UX

On success:

- `GPXRouteAttachmentService` persists the route.
- The service clears `routeMissingReason` to `.none`.
- `UnifiedWorkoutDetailDestination` refreshes `persistedRoute`.
- Route-derived detail values are rebuilt.
- Activity Detail can switch to the existing route-backed map presentation without requiring a full app restart.
- User feedback: `경로가 추가되었습니다.`

## Failure UX

Mapped failure copy:

- unsupported file: `GPX 파일만 가져올 수 있습니다.`
- file read failure: `GPX 파일을 읽을 수 없습니다.`
- invalid GPX: `GPX 파일을 읽을 수 없습니다.`
- route too short: `경로 좌표가 충분하지 않습니다.`
- already has route: `이미 경로가 있는 운동입니다.`
- unsupported source: `이 운동에는 GPX 경로를 추가할 수 없습니다.`
- persistence failure: `경로를 저장하지 못했습니다.`
- missing workout: `운동 기록을 찾을 수 없습니다.`

Summary import is not modified on failure. Existing route replacement is still guarded by the Phase 2 service and is not exposed through this entry point.

## Tests Added

`ActivityDetailGPXRouteImportTests` covers:

- HealthKit imported missing-route workout is eligible.
- Local Record missing-route workout is not eligible.
- Route-backed imported workout is not eligible by default.
- Non-actionable route state is not eligible.
- `.gpx` and `.GPX` extension validation.
- Non-GPX extensions are rejected.
- `GPXRouteAttachmentError` maps to display-safe import errors.
- Korean error copy for key failure states.

## Verification

Focused test command:

```sh
xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SOOMTests/ActivityDetailGPXRouteImportTests -only-testing:SOOMTests/GPXRouteAttachmentServiceTests -only-testing:SOOMTests/GPXRouteParserTests
```

Result:

- Test target compiled.
- Test execution was blocked by CoreSimulator infrastructure:
  - `Failed to clone device named 'iPhone 17 Pro'.`
  - `Device was allocated but was stuck in creation state.`
- Xcode also reported a connected device was passcode protected while preparing destinations.

Build-for-testing command:

```sh
xcodebuild build-for-testing -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'
```

Result:

- Passed.

Required build command:

```sh
xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'
```

Result:

- Passed.

## Next Recommended Step

Run physical-device QA for GPX attachment:

1. Import a HealthKit cycling workout with missing route.
2. Export a GPX file from the original source app.
3. Open Activity Detail.
4. Tap `GPX 경로 가져오기`.
5. Select the GPX file.
6. Confirm the route appears immediately on the detail map.
7. Confirm Share uses the attached route.
8. Confirm local Record workouts do not show the GPX attachment action.
