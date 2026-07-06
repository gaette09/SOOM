# SOOM Build 8 Follow-up Route, Share, and Detail Sheet Patch

Date: 2026-07-06

## Commit Under Test

Pending commit for follow-up patch after Build 8 Activity Detail refinement.

## QA Issues Addressed

- Feed route previews used sport tint and a heavier route stroke, producing inconsistent route rendering.
- Share image/card rendering could visually double the route line over the static Mapbox route image and had less stable export sizing.
- Activity Detail sheet behavior had two practical positions and relied too heavily on the top control for collapse behavior.

## Files Changed

- `SOOM/DesignSystem/SoomColor.swift`
- `SOOM/DesignSystem/SoomSpacing.swift`
- `SOOM/Components/FeedItemCard.swift`
- `SOOM/Components/ShareableWorkoutCardView.swift`
- `SOOM/Features/Activity/WorkoutMapControls.swift`
- `SOOM/Features/Activity/WorkoutMapSheetScaffold.swift`
- `SOOM/Features/Activity/WorkoutSheetState.swift`
- `SOOM/Features/Workout/MapboxStaticRouteURLBuilder.swift`
- `SOOM/Features/Workout/ShareableWorkoutCardRenderer.swift`
- `SOOM/Features/Workout/WorkoutDetailMapView.swift`
- `SOOMTests/MapboxStaticRouteURLBuilderTests.swift`
- `SOOMTests/ShareableWorkoutCardRendererTests.swift`
- `SOOMTests/WorkoutDetailSectionGroupTests.swift`

## Route Rendering Changes

- Added a shared internal SOOM route rendering style with one route color and width constants for detail, feed, and share surfaces.
- Updated route-backed Feed previews to use the shared SOOM route color and a thinner feed-specific stroke.
- Updated Mapbox static route URL generation to use the shared SOOM route color and detail route stroke width.
- Kept the shared SOOM Mapbox style URI path unchanged through `SOOMMapboxConfiguration.styleURI`.

## Share Rendering Changes

- Stabilized share card rendering by giving the renderer a fixed 9:16 frame before clipping and background application.
- Prevented the synthetic share route overlay from drawing on top of a resolved/static Mapbox route image.
- Kept transparent export behavior intact, including the existing transparent route-line behavior.
- Kept the checkerboard preview behavior preview-only.
- Added a focused renderer test for route share cards with a resolved route image.

## Sheet Snap Behavior Changes

- Activity Detail now uses three explicit sheet positions: bottom, middle, and top.
- Sheet drag advances one snap position at a time:
  - bottom + upward drag moves to middle
  - middle + upward drag moves to top
  - top + downward drag at content top moves to middle
  - middle + downward drag moves to bottom
- Internal detail scrolling is enabled only at the top snap position.
- When the detail content is scrolled away from the top, downward gestures continue to scroll content instead of moving the whole sheet.
- The existing collapse/expand controls now use the same one-step snap model.

## Map Camera and Visible Route Behavior

- Route-backed Activity Detail maps now update camera padding when the sheet position changes.
- Bottom sheet state uses reduced bottom padding so the route is naturally visible above the collapsed sheet.
- Middle and top states retain larger bottom padding so the route remains framed around the sheet.
- Record map behavior was not touched.

## Verification

- `xcrun simctl list devices available`: completed. Stable non-Pro iOS 26.5 options included iPhone 17e, iPhone 17, and iPhone Air.
- `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`: passed.
- Targeted tests attempted on `platform=iOS Simulator,name=iPhone 17e,OS=26.5`.
- Targeted tests compiled but did not execute because CoreSimulator failed to clone/create the iPhone 17e simulator: `Device was allocated but was stuck in creation state`.
- The targeted test failure is treated as simulator infrastructure, not an app/test assertion failure.
- `git diff --check`: passed.

## Known Limitations

- Share and sheet behavior still require physical device QA because simulator execution remains blocked by CoreSimulator clone infrastructure.
- Static route image network loading still depends on Mapbox static image availability; this patch prevents duplicate route overlays when the route image is resolved.
- This patch does not redesign Feed, Share, Record, charting, or Mapbox style configuration.

## Device QA Checklist

| Area | Check | Result | Notes |
| --- | --- | --- | --- |
| Feed | Route preview uses calm SOOM route color |  |  |
| Feed | Route preview stroke is not visually too thick |  |  |
| Share | Route-backed share card renders correctly |  |  |
| Share | Share image export layout is not broken |  |  |
| Share | Transparent export remains transparent |  |  |
| Share | Checkerboard appears only in preview UI |  |  |
| Activity Detail | Route-backed detail opens without crash |  |  |
| Activity Detail | Bottom sheet state leaves route naturally visible |  |  |
| Activity Detail | Upward drag from bottom moves to middle |  |  |
| Activity Detail | Upward drag from middle moves to top |  |  |
| Activity Detail | Internal scroll works only at top |  |  |
| Activity Detail | Downward drag at top content offset moves sheet to middle |  |  |
| Activity Detail | Downward drag while content is scrolled scrolls content only |  |  |
| Activity Detail | Downward drag from middle moves to bottom |  |  |
| Activity Detail | No-route workout fallback remains coherent |  |  |
| Record | Record map behavior is unchanged |  |  |

## Recommendation

The patch has no known compile blocker and addresses the reported Build 8 follow-up issues in a focused way. TestFlight should remain blocked until physical device QA confirms the share export and sheet drag behavior, because those were the original device-found blockers and simulator tests remain unavailable due to CoreSimulator infrastructure.
