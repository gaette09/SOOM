# SOOM Build 8 Share Export Layout and Confirmation Patch

Date: 2026-07-08

## Issue Addressed

Physical device QA confirmed that transparent PNG export and Save to Photos improved, but three issues remained:

- The `TRANSPARENT` label was still included in the saved/exported image.
- The four carousel cards used layouts that were too similar.
- Save wrote to Photos immediately, without a confirmation step.

## Files Changed

- `SOOM/Components/ShareableWorkoutCardView.swift`
- `SOOM/Features/Activity/WorkoutDetailContent.swift`

## TRANSPARENT Label Export Fix

- Removed the `TRANSPARENT` text from `ShareableWorkoutCardView` export content.
- Preview-only transparency indication remains outside the export path through the composer preview badge/checkerboard.
- Exported and saved PNG content is limited to route line, distance, total time, pace/speed, and a small SOOM mark.
- Checkerboard and preview contrast background remain preview-only.

## Four Layout Variants

The four carousel card types now map to distinct transparent workout-story layouts while using the same core metrics:

- Workout: route-first layout with a large upper route line and grouped metrics below.
- Condition: metric-stack layout with large distance near the top, time and pace/speed stacked below, and a smaller route line lower on the card.
- Course: compact center cluster with centered route and three compact metric columns.
- Club: minimal route + metrics layout with prominent route, generous spacing, large distance, and compact time/pace stack.

All variants avoid card titles, slogans, club/rank copy, stat boxes, and long marketing phrases in export.

## Save Confirmation UX

- Tapping Save now opens a confirmation alert:
  - Title: `이미지를 저장할까요?`
  - Message: `선택한 공유 이미지를 사진 앱에 저장합니다.`
  - Buttons: `취소`, `저장`
- PhotoKit save runs only after the user taps `저장`.
- The previous bottom text-only saved feedback is no longer used after successful Save.
- Save failure still surfaces through the existing error alert.

## Export and Preview Separation

- Save, Instagram, and More continue to use the export renderer.
- The export renderer renders only selected card content.
- Preview-only dark contrast surface and checkerboard are not rendered into saved/exported images.
- No background selection UI was reintroduced.

## Verification

- `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`: passed.
- Focused test attempt:
  - Command: `xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/ShareableWorkoutCardRendererTests -only-testing:SOOMTests/ShareableWorkoutCardBuilderTests`
  - Result: test target compiled, but execution failed before tests ran because CoreSimulator could not clone/create `iPhone 17e`.
  - Error: `Device was allocated but was stuck in creation state`.
  - Classification: simulator infrastructure issue, not an app test failure.
- `git diff --check`: passed.

## Remaining Physical Device QA Checklist

| Area | Check | Result | Notes |
| --- | --- | --- | --- |
| Export | Saved PNG does not include `TRANSPARENT` text |  |  |
| Export | Saved PNG includes no checkerboard or preview background |  |  |
| Export | Saved PNG includes only route, distance, time, pace/speed, SOOM |  |  |
| Layout A | Route-first layout is visually distinct and readable |  |  |
| Layout B | Metric-stack layout is visually distinct and readable |  |  |
| Layout C | Compact center cluster is visually distinct and readable |  |  |
| Layout D | Minimal route + metrics layout is visually distinct and readable |  |  |
| Save | Tapping Save shows confirmation before writing to Photos |  |  |
| Save | Cancel does not save |  |  |
| Save | Save writes the currently selected card |  |  |
| Regression | Background selector remains removed |  |  |
| Regression | Activity Detail, Record, Feed, and Mapbox style remain unchanged |  |  |

## Recommendation

The patch is build-clean and directly addresses the export label, layout variation, and Save confirmation issues. TestFlight should remain blocked until physical device QA verifies the four saved layouts and confirmation flow.
