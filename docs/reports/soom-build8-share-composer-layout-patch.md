# SOOM Build 8 Share Composer Layout Patch

Date: 2026-07-08

## Issue Addressed

Physical device QA showed that the Share composer still blocked TestFlight:

- Adjacent carousel cards bled into the active preview.
- Text and large stat/title copy clipped at the left and right edges.
- Route/map background appeared behind multiple overlapping card panels.
- Workout, Condition, Course, and Club cards appeared visually stacked or partially visible together.
- The main preview did not feel isolated inside a single card frame.

## Files Changed

- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOM/Components/ShareableWorkoutCardView.swift`
- `SOOMTests/ShareableWorkoutCardRendererTests.swift`

## Carousel Isolation Fix

- Replaced the peeking horizontal `ScrollView`/`HStack` carousel with a clipped single-page `TabView`.
- The active preview now uses a fixed card viewport and hides adjacent pages.
- Removed the previous peek-width layout that allowed neighboring cards to enter the main preview area.
- Each preview card is clipped to its own rounded frame.

## Card Frame and Export Fix

- The preview card now uses a fixed 9:16 frame based on `ShareableWorkoutCardLayout.aspectRatio`.
- Internal share card content now fills its own frame instead of depending on loose max-width sizing.
- Increased internal horizontal padding and reduced vertical breathing slightly so large Korean text has safer bounds.
- Relaxed headline/body minimum scale factors and enabled tightening for large share copy.
- Export rendering remains separate through `ShareableWorkoutCardRenderer` and still renders one selected card only.

## Export and Preview Separation

- Preview-only paging and clipping live in `ShareCardCarousel`/`ShareCardCarouselPreview`.
- Export rendering path was not changed.
- Transparent export behavior remains intact.
- Checkerboard remains preview-only.

## Route and Map Background Behavior

- Route-backed cards still use the existing static route/map background path.
- This patch does not alter Activity Detail map camera fitting, Feed route style, Record map behavior, or Mapbox style URI.
- The preview isolation prevents multiple route/map backgrounds from visually stacking in the composer.

## Card Type Coverage

- Added focused renderer coverage for all composer card types:
  - Workout card
  - Condition card
  - Course card
  - Club card

## Verification

- `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`: passed.
- Focused test attempt:
  - Command: `xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/ShareableWorkoutCardRendererTests`
  - Result: test target compiled, but execution failed before tests ran because CoreSimulator could not clone/create `iPhone 17e`.
  - Error: `Device was allocated but was stuck in creation state`.
  - Classification: simulator infrastructure issue, not an app test failure.
- `git diff --check`: passed.

## Remaining Device QA Checklist

| Area | Check | Result | Notes |
| --- | --- | --- | --- |
| Share Composer | Only one active card is visible in the main preview |  |  |
| Share Composer | Adjacent cards do not bleed into active preview |  |  |
| Share Composer | Workout card text is not clipped |  |  |
| Share Composer | Condition card text is not clipped |  |  |
| Share Composer | Course card route/map background appears once |  |  |
| Share Composer | Club card text and footer stay inside the card frame |  |  |
| Share Composer | Transparent preview shows checkerboard only in composer |  |  |
| Export | Exported image contains one selected card only |  |  |
| Export | Transparent export remains transparent and has no checkerboard |  |  |
| Regression | Activity Detail route fitting remains unchanged |  |  |
| Regression | Record map behavior remains unchanged |  |  |
| Regression | Feed route style remains acceptable |  |  |

## Recommendation

The patch is narrow and build-clean, but TestFlight should remain blocked until physical device QA confirms the Share composer preview and exported image are visually correct.
