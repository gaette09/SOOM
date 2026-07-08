# SOOM Build 8 Share Layout Variants and Save Confirmation Patch

## Issue Addressed

Physical device QA confirmed that transparent share exports saved correctly after `cd0646d`, but the exported image still needed stricter preview/export separation and stronger layout variation:

- The transparent preview label must remain preview-only and must not be saved/exported.
- The four transparent share cards needed meaningfully different route/metric layouts.
- Save should require explicit confirmation before writing to Photos.

## Files Changed

- `SOOM/Components/ShareableWorkoutCardView.swift`
- `SOOMTests/ShareableWorkoutCardBuilderTests.swift`
- `SOOMTests/ShareableWorkoutCardRendererTests.swift`
- `docs/reports/soom-build8-share-layout-variants-confirmation-patch.md`

## Implementation Summary

- Refactored transparent share card export layout to use the rendered card `GeometryReader` size and proportional positioning.
- Kept export content metric-only:
  - route line
  - distance
  - total time
  - pace or speed
  - small SOOM mark
- Kept preview-only UI outside exported content. The composer can still show the Korean transparent badge in preview, but `ShareableWorkoutCardView` export content does not render the `TRANSPARENT` label, checkerboard, or black preview background.
- Left the existing save confirmation dialog in place:
  - title: `이미지를 저장할까요?`
  - message: `선택한 공유 이미지를 사진 앱에 저장합니다.`
  - buttons: `취소`, `저장`
- Save continues to use the export renderer and PhotoKit add-only save path.

## Four Layout Variants

- Layout 1, Minimal Bottom Bar: large route in the upper/middle area, three metrics in a bottom row, SOOM mark aligned near the bottom.
- Layout 2, Full Route Poster: distance is emphasized near the top, time and pace/speed sit below it, route is the central visual.
- Layout 3, Side Stack: metric stack on the left, route line on the right, SOOM mark aligned with the metric column.
- Layout 4, Minimal Badge: route sits above a compact bottom metric cluster with no filled badge or stat box.

All four layouts use percentage-based width/height placement with safe insets rather than fixed 1080x1920 point coordinates.

## TRANSPARENT Export Removal

Checked current code paths for `TRANSPARENT` / `투명`:

- `WorkoutDetailContent.swift`: preview-only badge text.
- `ShareableWorkoutCardView.swift`: accessibility label only.
- `ShareableWorkoutCardModel.swift`: background option title for UI.

None of these are part of the rendered transparent export card content.

## Verification Results

- Passed: `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
- Attempted focused tests:
  - `xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:SOOMTests/ShareableWorkoutCardBuilderTests -only-testing:SOOMTests/ShareableWorkoutCardRendererTests`
  - Result: test target built, but execution failed before app tests ran because CoreSimulator could not clone iPhone 17 and left the device stuck in creation state. This matches the known simulator infrastructure issue and is not treated as an app test failure.
- Passed: `git diff --check`

## Remaining Physical Device QA Checklist

- Open Share composer from Activity Detail.
- Confirm only one active card is visible in the preview carousel.
- Swipe through all four transparent card layouts.
- Confirm each layout looks structurally different.
- Confirm no exported/saved image contains checkerboard, black background, or transparent preview label.
- Confirm saved image contains only route, distance, time, pace/speed, and small SOOM mark.
- Tap Save and confirm the Cancel / Save dialog appears.
- Tap Cancel and confirm no image is saved.
- Tap Save, confirm Photos save succeeds, and inspect the saved PNG.
- Use Instagram / More and confirm they share the selected card only.

## TestFlight Status

TestFlight remains blocked pending physical device QA of the updated transparent share card export and save confirmation flow.
