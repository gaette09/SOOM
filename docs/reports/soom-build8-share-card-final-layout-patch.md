# SOOM Build 8 Share Card Final Layout Patch

## Issue Addressed

Physical device QA confirmed the transparent card variants were functional, but the compositions needed final refinement:

- Card 1 text was too close to the edge and too small.
- Card 2 over-emphasized distance and needed a SOOM-led route poster hierarchy.
- Card 3 kept a good text layout but distorted the route in a narrow side area.
- Card 4 was too similar to Card 1 and needed to become a route-free stat summary.

## Files Changed

- `SOOM/Components/ShareableWorkoutCardView.swift`
- `SOOM/Features/Workout/ShareableWorkoutCardBuilder.swift`
- `SOOM/Features/Workout/ShareableWorkoutCardModel.swift`
- `SOOMTests/ShareableWorkoutCardBuilderTests.swift`
- `docs/reports/soom-build8-share-card-final-layout-patch.md`

## Card 1 Changes

- Increased horizontal safe inset.
- Moderately increased metric text size.
- Kept the existing route-over-bottom-metrics structure.
- Reduced route width slightly so the larger metrics have more visual breathing room.

## Card 2 Changes

- Replaced the dominant distance-first layout with a larger SOOM mark near the top.
- Moved the route below SOOM.
- Moved distance, pace/speed, and total time below the route.
- Increased metric text size and reordered metrics to distance, pace/speed, time.

## Card 3 Changes

- Preserved the left-side metric stack.
- Removed the tall narrow route placement that made the route feel distorted.
- Repositioned the route lower with a wider, more natural aspect ratio.
- Kept metrics and route separated to avoid overlap.

## Card 4 Changes

- Removed route rendering entirely.
- Replaced the route layout with a stat-only transparent summary.
- Added sport icon plus SOOM mark near the top.
- Added a clean metric summary using existing share-card data:
  - distance
  - total time
  - pace/speed
  - elevation
  - average heart rate
  - calories
- Added optional formatted average heart-rate and calorie fields to the share card model and populated them from existing `WorkoutGrowthInput` data.

## Export and Preview Behavior

- Export remains transparent.
- Export does not include checkerboard.
- Export does not include the transparent preview label.
- Export does not include a black full-card background.
- Preview-only checkerboard and transparent badge behavior remains separated in the composer.

## Save Behavior

- Existing Save confirmation dialog is preserved.
- Save continues to use the export renderer and PhotoKit save path.
- No Save-to-Photos behavior was changed in this patch.

## Verification Results

- Passed: `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
- Attempted focused tests:
  - `xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:SOOMTests/ShareableWorkoutCardBuilderTests -only-testing:SOOMTests/ShareableWorkoutCardRendererTests`
  - Result: target built, but tests could not execute because CoreSimulator failed to clone iPhone 17 and left the device stuck in creation state. This matches the known simulator infrastructure issue and is not treated as an app test failure.
- Passed: `git diff --check`

## Remaining Device QA Checklist

- Card 1: text sits farther inside the safe area and reads larger.
- Card 2: SOOM appears near the top, route below it, metrics below route.
- Card 3: route looks natural and no longer vertically stretched.
- Card 4: no route appears; sport icon, SOOM, and six stat metrics render cleanly.
- All cards: text stays inside safe bounds.
- Saved image: transparent PNG contains no checkerboard, no preview label, and no black full-card background.
- Save: confirmation dialog appears before writing to Photos.

## TestFlight Status

TestFlight remains blocked pending physical device QA of the final transparent share card layouts.
