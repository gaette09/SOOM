# SOOM Build 8 Transparent Story Share Patch

Date: 2026-07-08

## Issue Addressed

Physical device QA showed that the carousel overlap and basic typography fixes were not enough. The share flow still needed a structural shift:

- Share composer should focus on transparent story-style images only.
- Background selection below the preview added complexity and did not match the intended Build 8 share flow.
- Cards still felt slogan/title-first and too text-heavy.
- Save Image opened the system share sheet instead of directly saving the selected rendered image.

## Files Changed

- `SOOM/Components/ShareableWorkoutCardView.swift`
- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOM/Features/Workout/ShareableWorkoutCardModel.swift`
- `SOOM/Info.plist`
- `SOOMTests/ShareableWorkoutCardBuilderTests.swift`
- `SOOMTests/ShareableWorkoutCardRendererTests.swift`

## Background Section Removal

- Removed the Share composer background selector UI.
- Share composer now configures all cards as `.transparent`.
- The composer flow is now preview carousel, page indicator, and share actions.
- Copy Link remains hidden because there is no public URL backend.

## Dark Transparent Story Card Design

- Transparent cards now render as dark translucent story images with white text.
- Route line is promoted as the main visual layer when route data exists.
- Pale map/photo card treatment is no longer exposed in the composer.
- Card title emphasis was removed from the card surface; only small SOOM/type labeling remains.

## Card Layout Changes

- Cards now use a metric-first hierarchy:
  - route visual
  - primary metric or status
  - secondary metric line
  - compact supporting line
  - small SOOM footer
- Workout and Course cards prioritize distance and existing pace/time/elevation-style metrics.
- Condition and Club cards use existing summary/rank/contribution copy without large slogan-first layouts.
- Text remains inside the existing 9:16 card frame with the previous clipped single-card carousel.

## Share Actions Changes

- Share targets are now concise:
  - Instagram
  - Save
  - More
- Instagram and More continue to use the system share sheet.
- Save is now a direct Photos save action and no longer presents the share sheet.

## Save Image Fix

- Added a `ShareImagePhotoSaver` using PhotoKit add-only authorization.
- Save now renders the currently selected card and writes PNG data to the Photos library.
- Added `NSPhotoLibraryAddUsageDescription` to `Info.plist`.
- PNG data is used so alpha is preserved where iOS Photos supports transparent PNG display.
- If Photos displays transparency over its own background, that is platform presentation behavior rather than checkerboard export.

## Export and Preview Parity

- Preview and export use the same `ShareableWorkoutCardView` composition.
- Preview checkerboard remains preview-only.
- Export still renders one selected card only.
- No adjacent carousel bleed was reintroduced.

## Verification

- `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`: passed.
- Focused test attempt:
  - Command: `xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/ShareableWorkoutCardRendererTests -only-testing:SOOMTests/ShareableWorkoutCardBuilderTests`
  - Result: test targets compiled, but execution failed before tests ran because CoreSimulator could not clone/create `iPhone 17e`.
  - Error: `Device was allocated but was stuck in creation state`.
  - Classification: simulator infrastructure issue, not an app test failure.
- `git diff --check`: passed.

## Remaining Device QA Checklist

| Area | Check | Result | Notes |
| --- | --- | --- | --- |
| Composer | Background selection section is gone |  |  |
| Composer | Carousel still shows one isolated active card |  |  |
| Cards | Cards are transparent/dark story-style, not pale map cards |  |  |
| Cards | Route line is visible and does not dominate text |  |  |
| Cards | Workout card is metric-first and not slogan-first |  |  |
| Cards | Course card is route/distance-first |  |  |
| Cards | Condition card is readable and not clipped |  |  |
| Cards | Club card is readable and not clipped |  |  |
| Export | Export contains one selected card only |  |  |
| Export | Export has no preview checkerboard |  |  |
| Save | Save writes the current selected card to Photos |  |  |
| Save | Save success/failure message is visible |  |  |
| Share | Instagram and More still open the system share sheet |  |  |
| Regression | Activity Detail route fitting remains unchanged |  |  |
| Regression | Record and Feed behavior remain unchanged |  |  |

## Recommendation

The patch is build-clean and directly addresses the transparent-story direction plus the Save Image bug. TestFlight should remain blocked until physical device QA confirms the new card visuals and that Save writes the current selected image to Photos.
