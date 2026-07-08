# SOOM Activity Detail Processed Workout Migration

Date: 2026-07-08

## Commit Under Work

- Target commit message: `feat(activity): use processed workout metrics`
- Base read-model commit: `d9f2435 feat(data): add processed workout read model`

## Issue Addressed

Activity Detail previously formatted its primary summary metrics directly from the legacy `Workout` model. That kept Build 8 UI working, but it left Activity Detail on a different metric path from the new normalized `ProcessedWorkout` / `WorkoutDisplaySnapshot` layer.

This patch moves Activity Detail's display-ready summary metric reads to `ProcessedWorkout` while preserving the existing Activity Detail hierarchy, route-backed map behavior, and no-route fallback behavior.

## Files Changed

- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOMTests/ShareableWorkoutCardRendererTests.swift`
- `docs/reports/soom-activity-detail-processed-workout-migration.md`

## Activity Detail Reads From ProcessedWorkout

Activity Detail now builds a `ProcessedWorkout` from the existing `unifiedWorkoutForDraft` adapter and optional `mapRoute`.

The following display fields now come from `WorkoutDisplaySnapshot` / `ProcessedWorkout`:

- Header distance text
- Header duration text
- Summary tile distance
- Summary tile duration
- Summary tile average pace or speed value
- Summary tile average heart-rate fallback when recovery impact is unavailable
- Summary card date/time display

Sport-specific display behavior is preserved:

- Running prefers average pace.
- Cycling and Walking prefer average speed.
- Missing distance and movement metrics use the processed snapshot's missing-data copy.

## Still Reading Existing Models Directly

The migration is intentionally narrow. These Activity Detail areas still read the existing legacy `Workout`, derived builders, or route data directly:

- Title, sport icon, sport tint, and visible sport label remain from `Workout`.
- Route-backed map, route fitting, sheet behavior, and no-route fallback still use existing `WorkoutRoute` / map components.
- Rhythm insight, terrain insight, splits, recovery cards, and supporting Build 8 detail sections remain on their existing inputs.
- Profile, Share, Recovery, and Record save flow were not migrated in this task.

## Missing-Data Behavior

Missing metrics are represented by the read model and surfaced through display-ready text:

- Missing distance displays the processed distance fallback.
- Missing pace/speed displays the processed movement fallback.
- Missing recovery impact with no heart-rate data displays `준비 중`.
- Missing recovery impact with measured average heart rate displays the processed average heart-rate text.

Time-only workouts remain coherent because duration is still displayed while unavailable distance and movement metrics use read-model fallbacks.

## Route Behavior Preservation

No route fitting, Mapbox style, map camera, or sheet behavior code was changed.

Route-backed workouts still pass `mapRoute` into the existing Activity Detail map surfaces. No-route workouts keep the existing fallback path because this patch only changes display metric sourcing.

## Tests / Build Results

- Focused test command:
  - `xcodebuild test -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/ShareableWorkoutCardRendererTests`
  - Result: built and linked the test target, then failed during simulator execution with CoreSimulator infrastructure error: `Failed to clone device named 'iPhone 17e'`. This was not treated as an app/test failure.
- Build command:
  - `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
  - Result: passed.

## Added Test Coverage

Focused test coverage was added for Activity Detail summary metric generation from `ProcessedWorkout`:

- Cycling uses processed average speed display.
- Running missing distance/movement metrics use processed fallback copy.

Existing Activity Detail summary tests continue to cover recovery impact and heart-rate fallback behavior.

## Not Changed

- No Profile migration.
- No Share migration.
- No Recovery migration.
- No Record save-flow change.
- No Mapbox style URI change.
- No Activity Detail visual hierarchy change.
- No route fitting or sheet behavior change.
- No TestFlight upload.
- No build number bump.

## Next Recommended Migration Target

Move Share card model building or Profile aggregation to `ProcessedWorkout` next. Share is a good candidate because it already depends heavily on display-ready distance, duration, pace/speed, and route presence, but Profile aggregation may be more important if the next priority is data correctness across daily/weekly totals.

Recommended next step: migrate one surface at a time, starting with the surface that has the strongest metric consistency risk, and keep each migration backed by read-model tests.
