# SOOM Build 8 Activity Detail Implementation Plan

Date: 2026-06-26

Status: planning complete; implementation not started

Source handoff:

- `/Volumes/Platinum1TB/SOOM-OS/HANDOFFS/SOOM_ACTIVITY_DETAIL_BUILD8_IMPLEMENTATION.md`
- `/Volumes/Platinum1TB/SOOM-OS/DESIGN/SPECS/SOOM_ACTIVITY_DETAIL_SPEC_DRAFT.md`
- `/Volumes/Platinum1TB/SOOM-OS/REFERENCE/Strava/ActivityDetail/adopt-adapt-reject.md`

## Summary Recommendation

Build 8 can proceed as one focused Activity Detail implementation task if the scope stays conservative:

- Preserve Build 7 Mapbox style behavior.
- Refine the current Activity Detail hierarchy and visible density.
- Convert the existing multi-message rhythm card into a one-line SOOM insight area, or prepare that slot without fake content.
- Standardize the visible core stats around four calm label/value tiles.
- Use existing comparison/recovery builders only where their data already supports rhythm context.
- Keep Feed and Share changes to compatibility checks and narrowly required shared-component adjustments.

Split the work if the implementation expands into Feed redesign, share-card redesign, chart architecture, new baseline modeling, Mapbox configuration, or TestFlight release work.

## Current SOOM Activity Detail Structure

`WorkoutDetailView` is the entry point for workout detail presentation. It chooses between two shells:

- Routed workouts use `WorkoutMapSheetScaffold` with the map as the background and `WorkoutDetailContent` in the bottom sheet.
- No-route workouts use `SOOMScreen`, show `DetailHeader`, and let `WorkoutDetailContent` render an inline `ActivityDetailHeroMap` fallback.

`WorkoutDetailContent` currently renders the detail body in this order:

1. Optional `DetailHeader`.
2. Inline `ActivityDetailHeroMap` only for standalone presentation.
3. `ActivityDetailSummaryCard`.
4. `ActivityDetailRhythmCard`.
5. Optional terrain cue.
6. `WorkoutDetailSectionGroup.core` with `WorkoutSessionSummaryCard`.
7. `WorkoutDetailSectionGroup.growth` with growth metrics, growth summary, comparison insight, course record/progression, split insight, and climb insight.
8. Optional `WorkoutDetailSectionGroup.sensorData` with heart-rate zones, charts, and splits.
9. `WorkoutDetailSectionGroup.recovery` with recovery impact, weakness insight, and an `AI 해석` card using `workout.aiSummary`.
10. `ActivityDetailActionsCard` for feed draft and image share.

Important current behavior:

- `ActivityDetailRhythmCard` already provides SOOM-native insight copy, but it can display up to three messages.
- `ActivityDetailSummaryCard` currently uses three columns and includes distance, duration, pace/speed, and optional average heart rate.
- `ActivityDetailVisibilityPolicy` already suppresses empty splits, charts, heart-rate effort, and insufficient split insights.
- `WorkoutComparisonInsightBuilder` already compares against a recent/similar baseline, but the title and summary still include some growth/performance language such as "좋아졌어요".
- `WorkoutRecoveryImpactBuilder` already provides recovery-first short messages that can support a one-line insight without new modeling.
- `WorkoutDetailSectionGroup` already defines a reusable reading order, but collapse is explicitly not enabled.

## Mapbox And Route Structure

Build 7 Mapbox behavior is centralized and should be treated as protected:

- `SOOMMapboxConfiguration.styleURIString` is `mapbox://styles/gaette09/cmqtub3xc004m01rg7s331tq2`.
- `SOOMMapboxConfiguration.staticImagesStyleID` is `gaette09/cmqtub3xc004m01rg7s331tq2`.
- `SOOMMapboxRouteMap` initializes Mapbox with `SOOMMapboxConfiguration.styleURI`.
- The map coordinator reloads the expected SOOM style if the Mapbox view drifts from it.
- `MapboxStaticRouteURLBuilder` defaults static route images to `SOOMMapboxConfiguration.staticImagesStyleID`.
- Feed preview cards and share cards ultimately rely on `WorkoutDetailMapView`, `StaticRoutePreviewBuilder`, or static Mapbox route URLs.

Build 8 should only adjust map layout, surrounding copy, or fallback presentation. It should not change style URI, style ID, access token handling, static route URL generation, route privacy masking, or Mapbox camera/style-loading behavior.

## Files Inspected

SOOM-OS source documents:

- `/Volumes/Platinum1TB/SOOM-OS/HANDOFFS/SOOM_ACTIVITY_DETAIL_BUILD8_IMPLEMENTATION.md`
- `/Volumes/Platinum1TB/SOOM-OS/DESIGN/SPECS/SOOM_ACTIVITY_DETAIL_SPEC_DRAFT.md`
- `/Volumes/Platinum1TB/SOOM-OS/REFERENCE/Strava/ActivityDetail/adopt-adapt-reject.md`

Activity Detail and map surfaces:

- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOM/Features/Activity/DetailViews.swift`
- `SOOM/Features/Activity/WorkoutMapSheetScaffold.swift`
- `SOOM/Features/Activity/WorkoutMetricsSection.swift`
- `SOOM/Features/Activity/WorkoutMetricCards.swift`
- `SOOM/Features/Workout/WorkoutDetailMapView.swift`
- `SOOM/Features/Workout/SOOMMapboxConfiguration.swift`
- `SOOM/Features/Workout/WorkoutDetailSectionGroup.swift`
- `SOOM/Features/Workout/StaticRoutePreviewBuilder.swift`
- `SOOM/Features/Workout/MapboxStaticRouteURLBuilder.swift`

Insight, comparison, and recovery builders:

- `SOOM/Features/Workout/WorkoutComparisonInsightBuilder.swift`
- `SOOM/Features/Workout/WorkoutRecoveryImpactBuilder.swift`
- `SOOM/Features/Workout/WorkoutSessionSummaryBuilder.swift`
- `SOOM/Features/Workout/WorkoutGrowthMetricsBuilder.swift`
- `SOOM/Features/Workout/WorkoutGrowthSummaryBuilder.swift`
- `SOOM/Features/Workout/WorkoutSplitInsightBuilder.swift`
- `SOOM/Features/Workout/WorkoutWeaknessInsightBuilder.swift`

Feed and share surfaces:

- `SOOM/Components/FeedItemCard.swift`
- `SOOM/Components/ShareableWorkoutCardView.swift`
- `SOOM/Components/WorkoutShareSheet.swift`
- `SOOM/Features/Feed/FeedView.swift`
- `SOOM/Features/Feed/FeedPostDetailContent.swift`
- `SOOM/Features/Workout/ShareableWorkoutCardBuilder.swift`
- `SOOM/Features/Workout/ShareableWorkoutCardModel.swift`
- `SOOM/Features/Workout/ShareableWorkoutCardRenderer.swift`

Design system components:

- `SOOM/Components/SoomCard.swift`
- `SOOM/Components/SoomMetricPill.swift`
- `SOOM/Components/SoomMetricRow.swift`
- `SOOM/Components/SoomSectionHeader.swift`
- `SOOM/DesignSystem/SoomSpacing.swift`

Relevant tests:

- `SOOMTests/WorkoutDetailSectionGroupTests.swift`
- `SOOMTests/WorkoutDetailRouteContextProviderTests.swift`
- `SOOMTests/WorkoutDetailZoneContextProviderTests.swift`
- `SOOMTests/WorkoutComparisonInsightBuilderTests.swift`
- `SOOMTests/WorkoutRecoveryImpactBuilderTests.swift`
- `SOOMTests/ShareableWorkoutCardBuilderTests.swift`
- `SOOMTests/ShareableWorkoutCardRendererTests.swift`
- `SOOMTests/FeedItemTests.swift`
- `SOOMTests/FeedDataSourceTests.swift`
- `SOOMTests/MapboxStaticRouteURLBuilderTests.swift`
- `SOOMTests/RecordMapFoundationTests.swift`

## Safe Build 8 Scope

Recommended included work:

1. Keep the existing route/no-route presentation split.
2. Refine `ActivityDetailSummaryCard` into four core stat tiles:
   - Distance.
   - Duration.
   - Average pace or speed.
   - Recovery impact, average heart rate, or rhythm status depending on existing data.
3. Replace the current `ActivityDetailRhythmCard` multi-message treatment with a single top insight, or make the first message primary and move/remove secondary messages.
4. Reorder and tighten top hierarchy so title/date/location, insight, and four stats are more immediately scannable.
5. Use `WorkoutRecoveryImpact.shortMessage`, `WorkoutSessionSummary.summaryText`, or a constrained `ActivityDetailRhythmInterpreter` output for insight copy.
6. Keep rhythm comparison only if `comparisonInsight` is not `.insufficientData`, and adapt visible copy away from "improved/better" framing.
7. Reduce default visible density by leaning on `ActivityDetailVisibilityPolicy` and avoiding additional always-visible cards.
8. Add focused tests for any changed copy policy, tile selection, visibility policy, or comparison-language guardrail.

Optional but still conservative:

- Add a tiny reusable stat tile view local to `WorkoutDetailContent.swift` if `SOOMMetricPill` does not fit the desired hierarchy.
- Update `WorkoutDetailSectionGroup` captions if the reading order changes, with tests updated accordingly.
- Add a compact info affordance only for abstract recovery/rhythm copy if it can be done with existing design patterns.

## What Should Not Change

Do not change:

- `SOOMMapboxConfiguration.styleURIString`
- `SOOMMapboxConfiguration.staticImagesStyleID`
- `SOOMMapboxRouteMap` style initialization or style reload behavior.
- `MapboxStaticRouteURLBuilder` default style behavior.
- Route privacy masking policy.
- Record map behavior.
- Feed card interaction model.
- Share card export formats, transparency behavior, or route preview style.
- Chart architecture or chart color system.
- Data models for new rhythm baselines.
- Social, competitive, leaderboard, segment, likes-first, or comments-first features.
- Repeated AI cards.
- TestFlight or deployment flow.

Also avoid broad copy churn outside Activity Detail. Feed and Share should be inspected after the implementation, but only changed if a shared component change creates a concrete regression.

## Recommended Implementation Phases

### Phase 1: Guardrails And Tests First

- Confirm working tree status.
- Add or update focused tests for the intended behavior:
  - one-line insight policy,
  - four-stat tile selection,
  - no empty technical sections,
  - comparison language avoids negative/competitive framing,
  - Mapbox style constants remain unchanged.

### Phase 2: Top Hierarchy

- Adjust `WorkoutDetailContent` top order and visual weight.
- Keep routed workouts inside `WorkoutMapSheetScaffold`.
- Keep standalone/no-route workouts using the existing fallback map/hero path.
- Do not introduce a new screen shell.

### Phase 3: One-Line SOOM Insight

- Refactor `ActivityDetailRhythmInterpreter.messages` or add a small `primaryMessage` helper.
- Render one calm sentence near the top.
- Use existing session summary/recovery/split/weakness data only.
- Do not duplicate `workout.aiSummary` as another top AI card.

### Phase 4: Four Core Stat Tiles

- Replace the current three-column summary with a stable two-by-two or equivalent four-tile layout.
- Keep label small and muted; value prominent; unit readable.
- Prefer existing data in this order:
  - distance,
  - duration,
  - pace/speed,
  - recovery impact or heart-rate/rhythm fallback.

### Phase 5: Rhythm Comparison Gate

- If `comparisonInsight` is available and meaningful, show it as a compact rhythm comparison using existing rows.
- If it is `.insufficientData`, omit the module instead of reserving fake baseline content.
- If copy needs changing, update `WorkoutComparisonInsightBuilder` tests at the same time.

### Phase 6: Density Pass

- Review the default scroll for duplicated AI/recovery language.
- Consider whether `AI 해석` should remain lower in recovery, be collapsed later, or be left unchanged for Build 8.
- Do not expose additional charts, raw metrics, or unstructured text.

### Phase 7: Feed And Share Regression Check

- Verify shared components still render.
- Keep `FeedItemCard`, `ShareableWorkoutCardView`, and builder changes out of scope unless Activity Detail component reuse requires a very small adjustment.

## Risks

- Map regression: route preview, detail map, feed map, and share static maps share style assumptions.
- Density creep: Activity Detail already has many cards, so adding another insight or comparison card without removing/condensing will work against the Build 8 goal.
- Copy mismatch: `WorkoutComparisonInsightBuilder` still has some growth/improvement wording that may not fully match rhythm-first language.
- Data readiness: true rhythm comparison may need baseline data beyond current comparison inputs.
- No-route state: the existing fallback works, but the top hero copy should avoid implying a route exists.
- Feed/share coupling: route preview and card model changes can accidentally alter public share outputs.
- Test style mix: the repo uses both XCTest and Swift Testing-style tests, so new tests should follow the surrounding file style.

## Testing Checklist For Implementation

Minimum local verification after code changes:

- `git status --short`
- `git diff --check`
- Focused unit tests for any touched builders/policies:
  - `WorkoutDetailSectionGroupTests`
  - `WorkoutComparisonInsightBuilderTests`
  - `WorkoutRecoveryImpactBuilderTests`
  - `ShareableWorkoutCardBuilderTests`
  - `ShareableWorkoutCardRendererTests`
  - `MapboxStaticRouteURLBuilderTests` if route/static preview behavior is touched
- A build or focused test command appropriate to the changed files.
- Simulator or preview/screenshot check for:
  - routed workout detail,
  - no-route workout detail,
  - long title/date text,
  - dynamic type,
  - share composer still opening if touched.

Manual QA checklist:

- Build 7 Mapbox style remains intact.
- Activity Detail reads as hero/title/insight/stats/details, not a dense analytics feed.
- Only one top SOOM insight is visible.
- Four core stat tiles are consistent and readable.
- Rhythm comparison appears only with real baseline data.
- No competitive or social ranking language is introduced.
- Empty/no-route state feels intentional.
- Feed and Share are not visually or behaviorally regressed.

## Proceed / Split Decision

Safe to proceed to code in one task:

- Yes, if the next task is limited to `WorkoutDetailContent.swift`, targeted builder copy if needed, and focused tests.

Should split:

- Yes, if the work includes new rhythm baseline modeling, chart/template architecture, shared feed-card redesign, share-card redesign, Mapbox behavior, or release/upload operations.

Recommended next task name:

- `Build 8 Activity Detail conservative hierarchy pass`
