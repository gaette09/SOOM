# SOOM Build 8 Follow-up Route Fitting Patch

Date: 2026-07-06

## Issue Addressed

Physical device QA confirmed the Build 8 follow-up route style, share rendering, and sheet snapping fixes, but Activity Detail route fitting still needed work:

- On first Activity Detail presentation, route-backed maps could appear clipped or not fully fit within the visible map area.
- At the bottom sheet snap state, the route needed to remain fully visible and centered within the area not covered by the sheet.

## Files Changed

- `SOOM/Features/Activity/WorkoutMapControls.swift`
- `SOOM/Features/Activity/WorkoutMapSheetScaffold.swift`
- `SOOM/Features/Workout/WorkoutDetailMapView.swift`
- `SOOMTests/WorkoutDetailSectionGroupTests.swift`

## Route Fitting Behavior

- Replaced the rough center-plus-zoom camera estimate for the primary Mapbox route map path with Mapbox coordinate fitting.
- The route camera now fits the full route coordinate set with route padding, instead of relying on span buckets.
- The fallback center-plus-zoom path remains only as an error fallback if Mapbox camera fitting fails.
- The camera signature includes route coordinates, stroke width, camera padding, and rendered map size so the first non-zero layout pass can refit the route.

## Initial Camera Behavior

- The initial Activity Detail middle sheet state now passes camera padding derived from the actual sheet height and safe area.
- That padding reserves the visible area occupied by the sheet and top controls, so the route fit is calculated for the useful map area rather than the full screen.
- No-route workouts keep the existing fallback background behavior.

## Bottom Snap Visible-Area Centering

- Bottom snap state now uses sheet-height-based bottom padding, so the route is fit and centered above/around the lowered sheet.
- Sheet snap changes trigger one camera refit through the existing Mapbox route map update path.
- After the first camera set, subsequent snap-state route fits use Mapbox camera easing with the existing detail sheet map animation duration.

## Middle and Top Behavior

- Middle state remains the expected initial layout and uses dynamic visible-area padding.
- Top state uses capped bottom padding so it does not try to fit the route into an impossible offscreen area.
- Normal detail content scrolling does not change camera padding and should not cause repeated camera refits.
- Manual map pan/zoom is not continuously overridden; the route camera is recalculated on initial load, layout size change, or sheet snap padding change.

## Non-goals Preserved

- Mapbox style URI was not changed.
- Record map behavior was not changed.
- Feed route style was not changed in this patch.
- Share rendering was not changed in this patch.
- Activity Detail hierarchy, stat tiles, and insight copy were not changed.
- Build number and TestFlight upload were not touched.

## Verification

- `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`: passed.
- Focused test attempt:
  - Command: `xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/WorkoutDetailSectionGroupTests`
  - Result: test target compiled, but execution failed before tests ran because CoreSimulator could not clone/create `iPhone 17e`.
  - Error: `Device was allocated but was stuck in creation state`.
  - Classification: simulator infrastructure issue, not an app test failure.
- `git diff --check`: passed.

## Device QA Checklist

| Area | Check | Result | Notes |
| --- | --- | --- | --- |
| Activity Detail | Route-backed workout opens with full route visible on first presentation |  |  |
| Activity Detail | Route is not clipped on left, right, top, or bottom in initial middle state |  |  |
| Activity Detail | Dragging sheet to bottom keeps full route visible |  |  |
| Activity Detail | Bottom snap centers route in visible map area, not full screen |  |  |
| Activity Detail | Bottom-to-middle and middle-to-bottom transitions do not feel abrupt |  |  |
| Activity Detail | Top snap does not fight normal detail scrolling |  |  |
| Activity Detail | Manual map pan/zoom is not repeatedly overridden without a sheet snap change |  |  |
| Activity Detail | No-route workout fallback remains coherent |  |  |
| Regression | Feed route preview still looks good |  |  |
| Regression | Share image/card still renders correctly |  |  |
| Regression | Record map behavior remains unchanged |  |  |

## Recommendation

The route fitting patch is narrow and build-clean. TestFlight should remain pending physical device QA for Activity Detail route fitting because this patch addresses a device-visible map centering issue that simulator execution could not validate.
