# SOOM Build 8 Share Card Typography Patch

Date: 2026-07-08

## Issue Addressed

Physical device QA confirmed that carousel overlap was fixed, but the card design still felt too dense and clipped:

- Large Korean/English text could clip at the left or right edge.
- Metric boxes made the card feel crowded and more like a stats panel than a story image.
- Workout and Course cards trapped useful information inside translucent stat boxes.
- Text needed stronger safe-area treatment over the route/map background.

## Files Changed

- `SOOM/Components/ShareableWorkoutCardView.swift`

## Removed Boxed Stat Treatment

- Removed the rounded translucent metric box strip from standard share cards.
- Removed the separate transparent metric line branch.
- Workout, Condition, Course, and Club cards now use one text-first story stack:
  - large headline
  - short interpretation phrase
  - compact supporting line
  - quiet SOOM footer
- Supporting workout/course stats remain as text, not boxed panels.

## Text Safe-area Strategy

- Added a share-card-specific `storySafePadding` so the card text has stronger side insets without changing unrelated weekly share cards.
- Reduced oversized headline and interpretation font sizes.
- Increased line limits for large story text from two lines to three where needed.
- Lowered minimum scale factors and enabled text tightening for large Korean/English copy.
- Allowed supporting text to wrap to two lines instead of forcing one-line clipping.
- Added layout priority and fixed vertical sizing to the story stack so text resolves inside the card bounds.

## Route/Map Background Behavior

- Route/map background remains the visual backdrop.
- The bottom gradient was strengthened slightly so text reads over map imagery.
- No Activity Detail route fitting, Feed route style, Record map behavior, or Mapbox style URI was changed.
- No duplicate route overlay behavior was introduced.

## Preview and Export Behavior

- Preview and export still use the same `ShareableWorkoutCardView` composition.
- Export rendering path remains aligned with the preview.
- Transparent export remains transparent.
- Preview-only checkerboard remains preview-only.
- Carousel isolation from the previous patch remains unchanged.

## Card Type Coverage

Device QA should re-check all four card types:

- Workout card: large distance/title, phrase, text-only stat line.
- Condition card: large rhythm/recovery phrase and supporting number/line.
- Course card: route/course title, distance/supporting line, rhythm phrase.
- Club card: club name, rank/contribution line, community/rhythm phrase.

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
| Workout card | No boxed metric/stat panels appear |  |  |
| Workout card | Distance/title is fully readable and not clipped |  |  |
| Workout card | Supporting stat line is readable as text |  |  |
| Condition card | Large phrase is not clipped |  |  |
| Course card | Route/map remains background only and text is readable |  |  |
| Course card | Distance/course line wraps or scales without edge clipping |  |  |
| Club card | Club name and rank/contribution line stay inside safe area |  |  |
| Transparent card | Text remains readable and checkerboard stays preview-only |  |  |
| Export | Exported image matches preview composition |  |  |
| Regression | Carousel still shows one isolated active card |  |  |
| Regression | Activity Detail route fitting remains unchanged |  |  |
| Regression | Record and Feed behavior remain unchanged |  |  |

## Recommendation

The patch is narrow and build-clean, but TestFlight should remain blocked until physical device QA confirms that all four share card types are readable and free of text clipping in both preview and exported image.
