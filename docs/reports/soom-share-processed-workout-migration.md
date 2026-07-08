# SOOM Share Processed Workout Migration

Date: 2026-07-08

## Commit Under Work

- Target commit message: `feat(share): use processed workout metrics`
- Read-model base: `d9f2435 feat(data): add processed workout read model`
- Activity Detail migration base: `1254a63 feat(activity): use processed workout metrics`

## Issue Addressed

Share card model building still formatted workout metrics from `WorkoutGrowthInput` or legacy `Workout` adapters. That left Share on a separate display-metric path from Activity Detail and the normalized `ProcessedWorkout` read model.

This patch migrates Share card model building to use `ProcessedWorkout` / `WorkoutDisplaySnapshot` for display-ready workout metrics while preserving the current transparent share card v2 layouts, export transparency, Save confirmation, and route rendering behavior.

## Files Changed

- `SOOM/Features/Workout/ShareableWorkoutCardBuilder.swift`
- `SOOM/Features/Workout/ShareableWorkoutCardModel.swift`
- `SOOM/Components/ShareableWorkoutCardView.swift`
- `SOOMTests/ShareableWorkoutCardBuilderTests.swift`
- `docs/reports/soom-share-processed-workout-migration.md`

## Share Fields Now Using ProcessedWorkout

`ShareableWorkoutCardBuilder` now accepts a `ProcessedWorkout` directly and adapts existing `WorkoutGrowthInput` / legacy `Workout` entry points through `ProcessedWorkoutBuilder`.

The following share card fields now come from `WorkoutDisplaySnapshot`:

- `distanceText`
- `durationText`
- primary movement metric:
  - pace for Running and Hiking
  - speed for Cycling and Walking
- `elevationGainText`
- `averageHeartRateText`
- `activeEnergyText`

The existing card model shape is preserved so preview/export rendering remains compatible.

## Missing-Data Behavior

Required workout fields use read-model display fallbacks:

- Missing distance: `거리 준비 중`
- Missing pace/speed: `움직임 준비 중`

Optional stat-summary metrics keep the existing Share card contract:

- Missing elevation, average heart rate, or calories remain `nil` in the card model.
- The transparent stat-summary layout continues to render the stable placeholder `—`.

## Sport-Specific Metric Behavior

- Running cards use pace.
- Cycling cards use speed.
- Walking cards now use speed consistently in the share metric set and transparent card label.
- Time-only or incomplete workouts do not crash and render read-model fallback copy.

## Route / Export Preservation

No route drawing, transparent export renderer, Save-to-Photos, Save confirmation, carousel, or Mapbox style code was changed.

Route-backed share cards still build the same `StaticRoutePreview` payload through the existing privacy masking path. When route data is passed into the builder, `ProcessedWorkoutBuilder` also receives the route so route-derived distance can be used when source distance is missing.

Transparent export rules remain unchanged:

- no checkerboard in export
- no transparent badge/label in export
- no black full-card background in export
- selected card only

## Tests / Build Results

- Focused share test command:
  - `xcodebuild test -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/ShareableWorkoutCardBuilderTests -only-testing:SOOMTests/ShareableWorkoutCardRendererTests`
  - Result: built and linked, then failed during simulator execution with CoreSimulator infrastructure error: `Failed to clone device named 'iPhone 17e'`. This was not treated as an app/test failure.
- Build command:
  - `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
  - Result: passed.

## Added / Updated Test Coverage

- Added direct `ProcessedWorkout` share builder coverage.
- Added missing-metric fallback coverage for required and optional share metrics.
- Updated running expectations to use derived read-model pace.
- Updated Cycling and Walking share metric expectations to use speed.
- Existing renderer tests continue to cover transparent export behavior and selected-card export boundaries.

## Not Changed

- No Activity Detail changes.
- No Profile migration.
- No Recovery migration.
- No Record save-flow change.
- No Share renderer/export rewrite.
- No Save confirmation change.
- No Mapbox style URI change.
- No build number bump.
- No TestFlight upload.

## Next Recommended Migration Target

Migrate Profile aggregation to `ProcessedWorkout` next if data correctness remains the priority. Profile totals and summaries have higher cross-surface consistency risk than further Share UI polish, and they should benefit from the same missing-data and sport-specific metric rules.
