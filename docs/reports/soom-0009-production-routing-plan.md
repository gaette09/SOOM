# SOOM 0009 Production Routing Plan

Date: 2026-06-22

Task:

- `tasks/soom/0009-record-detail-content-lock.md`

Inputs inspected:

- `docs/reports/soom-0009-report.md`
- `docs/specs/STRAVA_ACTIVITY_DETAIL_LAYOUT_SPEC.md`
- `SOOM/Features/Activity/DetailViews.swift`
- `SOOM/Features/Activity/WorkoutMapSheetScaffold.swift`
- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOM/Features/Activity/StravaDetailFrameLockView.swift`

## 1. Current WorkoutDetailView Routing

`WorkoutDetailView` currently always routes through the standalone page path:

```text
WorkoutDetailView
  -> SOOMScreen
  -> WorkoutDetailContent
```

Current behavior:

- `WorkoutDetailView.body` wraps `WorkoutDetailContent` in `SOOMScreen`.
- `WorkoutDetailContent` defaults to `presentationStyle: .standalone`.
- In `.standalone`, `WorkoutDetailContent` renders `ActivityDetailHeroMap`.
- Production Record Detail does not yet use `WorkoutMapSheetScaffold`.
- Production Record Detail therefore still behaves like a normal pushed detail page, not a map-first sheet detail.

Relevant files:

- `SOOM/Features/Activity/DetailViews.swift`
- `SOOM/Features/Activity/WorkoutDetailContent.swift`

## 2. Route-Data Availability Condition

The safe routing condition should use the same route source already computed by `WorkoutDetailView`:

```swift
private var detailMapRoute: WorkoutRoute? {
    detailRouteOverride ?? route(for: workout)
}
```

Recommended production condition:

```swift
if detailMapRoute != nil {
    // map-sheet path
} else {
    // standalone fallback
}
```

Reason:

- `detailMapRoute` already respects `detailRouteOverride`.
- `route(for:)` already returns `nil` when `workout.route` is empty.
- The map-sheet path should only be used when a route exists, because the frame-lock target depends on a route map as the first visual anchor.

Do not use only `!workout.route.isEmpty` for final routing, because it would ignore `detailRouteOverride`.

## 3. Proposed Map-Sheet Path

For workouts with route data:

```text
WorkoutDetailView
  -> WorkoutMapSheetScaffold
  -> WorkoutDetailContent(presentationStyle: .mapSheet)
```

Recommended shape:

```swift
if detailMapRoute != nil {
    WorkoutMapSheetScaffold(workout: workout, navigationTitle: "운동 상세") {
        WorkoutDetailContent(
            workout: workout,
            showsHeader: false,
            presentationStyle: .mapSheet,
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            growthMetrics: growthMetrics,
            comparisonInsight: comparisonInsightOverride ?? comparisonInsight,
            courseRecord: courseRecordOverride ?? courseRecord,
            courseProgression: courseProgressionOverride ?? courseProgression,
            terrainInsight: terrainInsightOverride ?? terrainInsight,
            splitInsight: splitInsight,
            climbInsight: climbInsightOverride ?? climbInsight,
            weaknessInsight: weaknessInsight,
            recoveryImpact: recoveryImpact,
            shareableCard: shareableCard,
            mapRoute: detailMapRoute,
            healthKitWorkout: healthKitWorkout,
            zoneDataProvider: zoneDataProvider,
            splitDataProvider: splitDataProvider
        )
    }
} else {
    // fallback standalone path
}
```

Key points:

- `showsHeader` should be `false` in map-sheet mode to avoid duplicating the fixed top nav/title.
- `presentationStyle` should be `.mapSheet` to suppress the inline `ActivityDetailHeroMap`.
- The existing data builders can remain unchanged for the first routing commit.
- This is a routing-only step. It should not change sheet physics or content pruning yet.

## 4. Fallback Standalone Path

For workouts without route data:

```text
WorkoutDetailView
  -> SOOMScreen
  -> WorkoutDetailContent(presentationStyle: .standalone)
```

Recommended shape:

```swift
SOOMScreen {
    WorkoutDetailContent(
        workout: workout,
        showsHeader: true,
        presentationStyle: .standalone,
        sessionSummary: sessionSummary,
        growthSummary: growthSummary,
        growthMetrics: growthMetrics,
        comparisonInsight: comparisonInsightOverride ?? comparisonInsight,
        courseRecord: courseRecordOverride ?? courseRecord,
        courseProgression: courseProgressionOverride ?? courseProgression,
        terrainInsight: terrainInsightOverride ?? terrainInsight,
        splitInsight: splitInsight,
        climbInsight: climbInsightOverride ?? climbInsight,
        weaknessInsight: weaknessInsight,
        recoveryImpact: recoveryImpact,
        shareableCard: shareableCard,
        mapRoute: detailMapRoute,
        healthKitWorkout: healthKitWorkout,
        zoneDataProvider: zoneDataProvider,
        splitDataProvider: splitDataProvider
    )
}
.navigationTitle("운동 상세")
.navigationBarTitleDisplayMode(.inline)
```

Why fallback remains important:

- Some workouts may not have route samples.
- The standalone path keeps the existing non-route detail behavior stable.
- The fallback path avoids forcing a map-first layout when the map is not the reliable visual anchor.

## 5. Scaffold Gaps Vs Frame-Lock Spec

`WorkoutMapSheetScaffold` is the closest production entry point, but it is not fully frame-lock compliant yet.

Current scaffold strengths:

- It renders a full-screen map layer behind the sheet.
- It hides the system navigation and tab bars.
- It already separates map controls from sheet content.
- It supports expanded sheet content and scroll disabling.

Gaps versus `docs/specs/STRAVA_ACTIVITY_DETAIL_LAYOUT_SPEC.md`:

| Spec area | Frame-lock target | Current scaffold gap |
| --- | --- | --- |
| Sheet states | Two states: preview and expanded | Current `WorkoutSheetPosition` has `minimized`, `standard`, and `expanded`. |
| Preview anchor | `previewSheetTop = screenHeight * 0.64` | Current standard height is based on `standardRatio = 0.56`, not an absolute sheet-top anchor. |
| Coordinate source | Sheet offsets measured from absolute screen top | Current scaffold is height/bottom-aligned rather than top-offset anchored. |
| Top nav | Fixed top nav remains visible and changes background | Current map controls disappear in expanded state; expanded header is inside the sheet. |
| Header ownership | Top nav is outside the sheet and never offset | Current expanded `WorkoutSheetHeader` is part of `WorkoutBottomSheet`. |
| Drag ownership | Handle-owned preview/expanded transition; no overscroll collapse first pass | Current expanded drag can begin from scroll offset at top and collapse via downward drag. |
| Map camera | Keep map camera stable until sheet motion is solved | Current scaffold animates map camera when `sheetPosition` changes. |
| Expanded shape | Expanded radius `0`, no floating-card feeling | Current radius is controlled by `WorkoutSheetMetrics`; close but tied to position/drag thresholds. |
| Content top padding | Expanded content starts below `safeAreaTop + navHeight + 36` | Current sheet content starts under the sheet header, not from the spec formula. |

Conclusion:

- Use `WorkoutMapSheetScaffold` for the next safe routing commit.
- Do not claim frame-lock completion after routing.
- Treat scaffold physics/top-nav cleanup as follow-up commits after production routing is testable.

## 6. Minimum Safe Code Change For Next Commit

Recommended next commit scope:

- Modify only `SOOM/Features/Activity/DetailViews.swift`.
- Route `WorkoutDetailView` through `WorkoutMapSheetScaffold` only when `detailMapRoute != nil`.
- Pass `presentationStyle: .mapSheet` and `showsHeader: false` to `WorkoutDetailContent` in the map-sheet path.
- Keep the existing `SOOMScreen` standalone path for `detailMapRoute == nil`.
- Do not change `WorkoutMapSheetScaffold` behavior yet.
- Do not prune content yet.
- Do not change copy, chart sections, AI sections, or recovery/growth sections yet.

Expected effect:

- Route-backed workouts start exercising the map-sheet presentation path.
- Non-route workouts keep existing standalone behavior.
- Duplicate inline map is avoided because `WorkoutDetailContent(.mapSheet)` already suppresses `ActivityDetailHeroMap`.

Non-goals for the next commit:

- No scaffold physics refactor.
- No two-state frame-lock implementation.
- No fixed top nav refactor.
- No content pruning.
- No deployment.

## 7. Verification Command

After the routing change, run:

```sh
xcodebuild -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Recommended manual simulator checks after a successful build:

- Open a workout with route data.
- Confirm it enters the map-sheet path.
- Confirm the sheet content does not render a second inline hero map.
- Open or simulate a workout without route data.
- Confirm it stays in the standalone detail path.
- Confirm no scaffold physics changes were included in the routing commit.

