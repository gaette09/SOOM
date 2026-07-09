# SOOM FIT Import v1 Phase D: Activity Detail Entry Point

Date: 2026-07-09

## Summary

Phase D extends the existing Activity Detail route-file fallback so users can attach either GPX or FIT route files to an imported Apple Health workout that is missing route data.

The entry point remains narrow:

- No FIT full workout import.
- No FIT/TCX/Strava/Wahoo/Garmin integration.
- No server upload.
- No HealthKit write.
- No background sync.
- No Mapbox style changes.

## Files Changed

- `SOOM/Features/Activity/ActivityDetailGPXRouteImport.swift`
- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutLibraryView.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutLibraryViewContainer.swift`
- `SOOMTests/ActivityDetailGPXRouteImportTests.swift`
- `docs/reports/soom-fit-import-v1-activity-detail-entry.md`

## Entry Point Behavior

The existing imported-workout no-route fallback now uses generic route-file copy:

- Button: `경로 파일 가져오기`
- Help text: `원본 앱에서 GPX 또는 FIT 파일을 내보내면 이 운동에 경로를 추가할 수 있습니다.`

The action remains eligible only when:

- The workout source is `.appleHealthKit`.
- The detail screen has no persisted route.
- `routeMissingReason` is actionable for route attachment.

Local SOOM Record workouts remain unsupported by this attachment entry point.

## File Importer Behavior

`ActivityDetailGPXRouteFileImport` now recognizes:

- `.gpx`
- `.fit`

The SwiftUI file importer allows GPX/FIT UTTypes when available and retains XML/data fallback for system file-picker compatibility. The selected URL is still validated by extension before parsing.

Dispatch behavior:

- `.gpx` -> `GPXRouteAttachmentService`
- `.fit` -> `FITRouteAttachmentService`
- other extensions -> unsupported file type

## Success UX

On successful route attach:

- The route is persisted by the relevant attachment service.
- Activity Detail reloads persisted route state.
- Route-derived comparison/course/climb state is refreshed.
- The fallback shows `경로가 추가되었습니다.`

The attached route should appear without requiring a full app restart when the detail state refresh succeeds.

## Failure UX

Errors map to calm Korean copy:

- Unsupported file: `GPX 또는 FIT 파일만 가져올 수 있습니다.`
- Unreadable or invalid file: `경로 파일을 읽을 수 없습니다.`
- Too short: `경로 좌표가 충분하지 않습니다.`
- Existing route: `이미 경로가 있는 운동입니다.`
- Unsupported source: `이 운동에는 경로 파일을 추가할 수 없습니다.`
- Persistence failure: `경로를 저장하지 못했습니다.`

Failed imports preserve the existing workout summary and do not create duplicate workouts.

## Tests Updated

`ActivityDetailGPXRouteImportTests` now covers:

- FIT extension acceptance.
- Route file format detection for `.gpx` and `.fit`.
- Unsupported extension rejection.
- FIT attachment error mapping.
- Generic route-file display copy.

## Deferred

- Physical-device file importer QA.
- Real FIT sample compatibility.
- FIT full workout import.
- FIT sensor stream persistence.
- TCX support.
- External provider integrations.

## Verification

Completed for this phase:

```sh
xcodebuild build-for-testing -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator' # passed
xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator' # passed
```

Focused simulator test execution was attempted:

```sh
xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SOOMTests/ActivityDetailGPXRouteImportTests
```

It failed before test execution because CoreSimulator could not clone `iPhone 17 Pro` and reported the device was stuck in creation state. This is treated as infrastructure. Build-for-testing remains the compile and test-build gate until simulator cloning is fixed.

Xcode also emitted existing connected-device passcode warnings and existing renderer/test warnings.

Pending final release hygiene:

```sh
git diff --check
git status --short
```

Physical-device QA is required before claiming real-world FIT import behavior.

## Next Recommended Step

Stop after this phase for FIT file QA:

1. Collect real sample FIT files from target cycling devices/apps.
2. Run physical-device Activity Detail route-file import QA for GPX and FIT.
3. Patch parser compatibility only from observed real FIT failures.
