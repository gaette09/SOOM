# SOOM Build 8 Transparent Export Patch

Date: 2026-07-08

## Issue Addressed

Physical device QA confirmed that Save to Photos works, but the saved transparent share image still included the dark preview background. That meant the exported PNG was not actually transparent.

This patch separates preview readability from export content and simplifies the saved image to a metric-only transparent workout story card.

## Files Changed

- `SOOM/Components/ShareableWorkoutCardView.swift`
- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOMTests/ShareableWorkoutCardRendererTests.swift`

## Preview and Export Background Separation

- Removed the dark rounded rectangle and dark gradient from `ShareableWorkoutCardView` when rendering transparent cards.
- Added the dark contrast surface only inside `ShareCardCarouselPreview`, behind the transparent card preview.
- The checkerboard remains preview-only.
- `ShareableWorkoutCardRenderer` still renders transparent cards with `.clear` background and `isOpaque = false`.

## Metric-only Export Content

Transparent exported cards now include only:

- `TRANSPARENT` label
- route line visual
- distance
- total time
- pace/speed field
- small SOOM mark

Removed from transparent export:

- card titles
- marketing/rhythm slogans
- club rank/contribution copy
- condition copy
- long Korean phrases
- dark background rectangle
- rhythm-pattern decorative layer

All carousel card types now use the same reliable metric-only transparent export structure for this Build 8 patch.

## Text and Layout Strategy

- White text remains readable through subtle text shadow/glow rather than a baked black rectangle.
- Route line stays in the upper/middle visual area.
- Metrics are grouped in the lower half with clear labels and values.
- Content stays inside the existing 9:16 frame and rounded preview clipping remains in the composer only.

## Save-to-Photos Behavior

- Save continues to render the selected card through the export renderer, not the preview wrapper.
- Saved image remains a PNG.
- Preview-only checkerboard and preview-only dark contrast surface are not included in the saved image.
- iOS Photos may display transparency over its own viewer background; that is viewer behavior, not a baked export background.

## Verification

- `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`: passed.
- Focused test attempt:
  - Command: `xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/ShareableWorkoutCardRendererTests -only-testing:SOOMTests/ShareableWorkoutCardBuilderTests`
  - Result: test target compiled, but execution failed before tests ran because CoreSimulator could not clone/create `iPhone 17e`.
  - Error: `Device was allocated but was stuck in creation state`.
  - Classification: simulator infrastructure issue, not an app test failure.
- `git diff --check`: passed.
- Added renderer coverage that asserts a transparent export corner pixel remains transparent.

## Remaining Device QA Checklist

| Area | Check | Result | Notes |
| --- | --- | --- | --- |
| Preview | Composer still shows readable dark/checkerboard preview |  |  |
| Export | Saved PNG has no baked black rectangle |  |  |
| Export | Saved PNG has no checkerboard |  |  |
| Export | Export contains route line, distance, time, pace/speed, SOOM only |  |  |
| Export | No card titles or marketing phrases appear in saved image |  |  |
| Export | Text is not clipped on iPhone |  |  |
| Save | Save writes the currently selected card |  |  |
| Share | Instagram/More still export the selected transparent image |  |  |
| Regression | Background selector does not return |  |  |
| Regression | Activity Detail route fitting remains unchanged |  |  |
| Regression | Record and Feed behavior remain unchanged |  |  |

## Recommendation

The patch is build-clean and removes the baked preview background from transparent export. TestFlight should remain blocked until physical device QA confirms the saved PNG is visually transparent and contains only the simplified metric content.
