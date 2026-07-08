# SOOM Build 8 Share Card v2 Layout Patch

## Issue Addressed

The prior transparent share cards exported correctly, but physical device QA found the compositions still felt unfinished. This patch implements the v2 transparent story-card direction as four clearer SOOM-native variants:

- Route-Centric
- Metric-Centric
- Balanced
- Stat Summary

The patch keeps export transparency, Save confirmation, and preview/export separation intact.

## Files Changed

- `SOOM/Components/ShareableWorkoutCardView.swift`
- `SOOMTests/ShareableWorkoutCardBuilderTests.swift`
- `docs/reports/soom-build8-share-card-v2-layout-patch.md`

## Implementation Summary

- Reworked the four transparent share layouts using `GeometryReader` card size and relative ratios.
- Kept the 9:16 export frame.
- Kept export background transparent.
- Kept export content metric-focused only.
- Preserved existing Save confirmation behavior in the composer.
- Left Activity Detail sheet behavior, route fitting, Record, Feed, Mapbox style URI, build number, and TestFlight untouched.

## Route Aspect-Ratio Preservation

Transparent route rendering now uses an aspect-fit helper:

- The route natural bounding box is represented by `transparentRouteNaturalBoundingBox`.
- Available route container width and height are reduced by route stroke allowance.
- A single scale factor is calculated with `min(availableWidth / bboxWidth, availableHeight / bboxHeight)`.
- The same scale factor is applied to width and height.
- The fitted route is centered inside its assigned route container.

This avoids the previous issue where a route could appear vertically stretched inside a narrow container.

## Four Layout Variants

### Variant 1: Route-Centric

- Header row: sport icon leading, SOOM trailing.
- Route occupies the upper/middle majority of the card.
- Bottom row contains distance, total time, and pace/speed in three equal columns.
- No elevation, heart rate, or calories.

### Variant 2: Metric-Centric

- Small sport icon near the top.
- SOOM mark is prominent near the upper area.
- Distance is centered and readable without dominating the full card.
- Total time and pace/speed sit below distance.
- Route is a thinner secondary visual below the metrics.
- No elevation, heart rate, or calories.

### Variant 3: Balanced

- SOOM header remains subtle.
- Metric stack stays on the left.
- Route is placed lower in a natural, aspect-preserved container.
- No forced tall/narrow route placement.
- Metrics include distance, total time, and pace/speed.

### Variant 4: Stat Summary

- Header row includes sport icon and SOOM.
- No route is rendered.
- Stable 2-column x 3-row metric grid:
  - distance
  - total time
  - pace/speed
  - elevation
  - average heart rate
  - calories
- Missing optional metrics use the stable placeholder `—`.
- No visible stat boxes or capsule backgrounds.

## Preview and Export Separation

- Preview-only checkerboard remains in `WorkoutDetailContent`.
- Preview-only `투명` badge remains outside exported card content.
- `ShareableWorkoutCardView` does not render checkerboard, `TRANSPARENT`, `투명`, or dark full-card background into exported PNG content.
- Existing renderer continues to export only the selected card content.

## Save Confirmation Behavior

- Save confirmation is preserved:
  - title: `이미지를 저장할까요?`
  - message: `선택한 공유 이미지를 사진 앱에 저장합니다.`
  - buttons: `취소`, `저장`
- Save still runs only after the user taps `저장`.
- No first-time-only save behavior was added.
- PhotoKit add-only save behavior remains unchanged.

## Verification Results

- Passed: `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
- Passed: focused share `build-for-testing`:
  - `xcodebuild build-for-testing -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:SOOMTests/ShareableWorkoutCardBuilderTests -only-testing:SOOMTests/ShareableWorkoutCardRendererTests`
- Blocked by simulator infrastructure: focused test execution
  - `xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:SOOMTests/ShareableWorkoutCardBuilderTests -only-testing:SOOMTests/ShareableWorkoutCardRendererTests`
  - Result: target built, but CoreSimulator failed to clone iPhone 17 and left the device stuck in creation state. This is not treated as an app test failure.
- Passed: `git diff --check`

## Remaining Device QA Checklist

- Card 1: route is dominant, metric row sits safely inside bounds.
- Card 2: distance is not oversized; SOOM, metrics, and route hierarchy reads cleanly.
- Card 3: route is not distorted and does not overlap the metric stack.
- Card 4: no route appears; 2-column stat summary remains readable.
- All cards: saved PNG stays transparent with no checkerboard, transparent label, or black background.
- Save: confirmation dialog appears every time before Photos save.

## TestFlight Status

TestFlight remains blocked pending physical device QA of the v2 transparent share card layouts.
