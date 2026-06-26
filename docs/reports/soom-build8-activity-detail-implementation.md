# SOOM Build 8 Activity Detail Implementation

Date: 2026-06-26

Status: implemented and locally build-verified

## Files Changed

- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOMTests/ShareableWorkoutCardRendererTests.swift`
- `docs/reports/soom-build8-activity-detail-implementation.md`

## Implementation Summary

Implemented the conservative Build 8 Activity Detail UI refinement from `docs/reports/soom-build8-activity-detail-implementation-plan.md`.

Changes made:

- Preserved the existing routed/no-route Activity Detail shell behavior.
- Kept `WorkoutMapSheetScaffold`, `WorkoutDetailMapView`, `SOOMMapboxConfiguration`, static route preview generation, and Record map behavior untouched.
- Replaced the visible top rhythm card treatment with a single one-line SOOM insight rendered from existing `ActivityDetailRhythmInterpreter` data.
- Added `ActivityDetailRhythmInterpreter.primaryMessage(...)` so the UI can use one calm primary sentence without deleting the existing multi-message helper.
- Converted the Activity Detail summary metrics into four fixed core tiles:
  - distance,
  - duration,
  - average pace or speed,
  - recovery impact when available, average heart rate fallback when recovery impact is missing, or a neutral "준비 중" placeholder when neither exists.
- Added `ActivityDetailSummaryMetrics` to centralize four-tile selection and make it testable.
- Added a small local `ActivityDetailStatTile` to improve label/value hierarchy without changing shared Feed or Share metric components.
- Added `ActivityDetailVisibilityPolicy.showsComparisonInsight(...)` so rhythm/comparison UI is shown only when existing comparison data has real rows and is not `.insufficientData`.
- Updated targeted tests for:
  - four core stat tile selection,
  - heart-rate fallback when recovery impact is missing,
  - one-line rhythm insight behavior,
  - comparison gating when baseline support is missing.

## Rhythm Comparison Decision

Build 8 does not add new rhythm baseline modeling.

The implementation uses the existing `WorkoutComparisonInsight` model only when it already has meaningful comparison rows and is not `.insufficientData`. If no baseline exists, Activity Detail omits the comparison card rather than reserving fake or placeholder comparison content.

This keeps Build 8 inside the conservative scope and avoids inventing new baseline data.

## Map Behavior Preservation

Map behavior was intentionally preserved:

- `SOOM/Features/Workout/SOOMMapboxConfiguration.swift` was not changed.
- `SOOM/Features/Workout/WorkoutDetailMapView.swift` was not changed.
- `SOOM/Features/Activity/WorkoutMapSheetScaffold.swift` was not changed.
- `SOOM/Features/Activity/RecordMapView.swift` was not changed.
- Static route URL generation and route privacy masking were not changed.

Build 7 Mapbox style URI and static style ID remain untouched.

## Intentionally Not Implemented

Not implemented in this task:

- New rhythm baseline modeling.
- New chart architecture or reusable chart template.
- Feed redesign.
- Share card redesign.
- Mapbox style or camera behavior changes.
- Record map behavior changes.
- Social, competitive, leaderboard, segment, likes-first, or comments-first features.
- Repeated AI cards.
- TestFlight upload or release automation.

## Verification Results

Commands run:

- `git status --short`
- `xcodebuild -list -project SOOM.xcodeproj`
- `xcodebuild test -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SOOMTests/ShareableWorkoutCardRendererTests`
- `xcrun simctl list devices available`
- `xcodebuild build -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
- `xcodebuild test -project SOOM.xcodeproj -scheme SOOM -destination 'id=B5E2FFBE-D302-4791-88F0-BE0B077045EA' -only-testing:SOOMTests/ShareableWorkoutCardRendererTests`
- `git diff --check`

Results:

- App build succeeded with `xcodebuild build -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`.
- Focused test target built and linked, but both test execution attempts failed before running tests because CoreSimulator could not clone the `iPhone 17 Pro` device:
  - `Failed to clone device named 'iPhone 17 Pro'.`
  - Underlying error: device was allocated but stuck in creation state.
- `git diff --check` passed.

Residual risk:

- The changed test cases were compiled but not executed because of the simulator clone failure.
- A follow-up test run should be performed once CoreSimulator is healthy.

## Follow-Up Recommendations

- Re-run the focused Activity Detail/share rendering tests after resetting or replacing the stuck simulator.
- Consider a later Build 9 task for a reusable detail chart template if the product direction still needs deeper metric progressive disclosure.
- Consider a later copy pass for `WorkoutComparisonInsightBuilder` if the product wants all comparison language to fully move from growth framing to rhythm framing.
