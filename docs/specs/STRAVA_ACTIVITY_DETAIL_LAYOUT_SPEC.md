# Strava Activity Detail Layout Spec

## Purpose

This document converts Strava Activity Detail screenshot observations into measurable layout specifications for a SOOM frame-lock prototype.

This is not a SOOM redesign spec. It is a layout and interaction reference. The goal is to lock the large frame before implementing content, typography, graphs, or SOOM-specific analysis.

All numbers below are first-pass frame-lock constants unless explicitly marked as device-dependent. Do not replace them with ranges during implementation. Adjust only after screenshot comparison proves a specific constant is wrong.

## 0. Coordinate System And Source Of Truth

Coordinate rules:

- All sheet offsets are measured from the absolute screen top, not from the safe-area top.
- Map ignores all safe areas.
- `safeAreaTop` is read exactly once via `GeometryReader` at the root `ZStack` level.
- `safeAreaTop` is passed down explicitly to all child views.
- No child view may independently read `safeAreaInsets.top`.
- `screenHeight = UIScreen.main.bounds.height`.
- `screenHeight` is read once at the root.
- `previewSheetTop = screenHeight * 0.64`.
- No child view may compute its own local screen height for sheet anchors.
- Top nav receives `safeAreaTop` but is positioned by the root `ZStack`.
- Sheet offset is applied only to `BottomSheetContainer`.
- `ScrollView` never receives a sheet offset.

Shared constants:

- `navHeight`: `56`
- `handleWidth`: `40`
- `handleHeight`: `4`
- `sheetPreviewCornerRadius`: `14`
- `sheetExpandedCornerRadius`: `0`
- `contentHorizontalPadding`: `32`
- `expandedContentTopPaddingBelowNav`: `36`
- `sectionTopSpacing`: `36`
- `chartHeight`: `140`
- `previewSheetTopRatio`: `0.64`
- `expandedSheetTop`: `0`

## 1. Screen Hierarchy

The screen is organized as layered UI, not as a normal vertical page.

Hierarchy:

1. Full-screen route map
2. Fixed top controls / navigation
3. Movable bottom sheet
4. Scrollable sheet content

The route map is the first visual anchor. The sheet then introduces activity facts and details.

The important structural distinction:

- Preview state: map-first, sheet-low, compact summary.
- Expanded state: white page, fixed nav, scrollable activity detail.

## 2. Safe Area Behavior

Preview:

- Map extends behind the status bar and fills the full screen.
- Top controls float over the map near the safe-area top.
- Status bar background is visually map-backed.

Expanded:

- Status bar background becomes white.
- Map must not show behind the status bar or top navigation.
- The top safe area and nav bar should read as one continuous white region.
- No visible map strip should appear between status bar, nav bar, and sheet content.

Fixed first-pass values for iPhone portrait:

- Safe area top: device-dependent and read from `GeometryProxy.safeAreaInsets.top`.
- `safeAreaTop` is read exactly once via `GeometryReader` at the root `ZStack` level.
- `safeAreaTop` is passed down explicitly to all child views.
- No child view may independently read `safeAreaInsets.top`.
- Content starts after nav plus additional breathing room.
- `navHeight`: `56`
- There is no independent detached white nav box.
- In expanded state, `BottomSheetContainer` starts at absolute Y = 0.
- The sheet's own white background covers the status bar, nav area, breathing space, and all content behind it.
- The phrase "white top cover" refers only to the visual result of the expanded white sheet behind the fixed nav, not a separate layout card.
- If an opacity helper is used, it must be full-width and aligned to top, and must not create a detached nav rectangle.

## 3. Header Position

Preview:

- Header floats over the map.
- Header is fixed relative to the screen, not attached to the sheet.
- Header top should sit close to the iOS status area, not low in the screen.

Expanded:

- Header remains fixed at the top.
- Header background becomes white.
- Header does not move with the sheet.
- Header should sit directly below the status bar.
- Activity type title is centered.
- Back/down control is left.
- Save/bookmark and more controls are right.

Fixed first-pass values:

- Header top Y: `safeAreaTop`
- Header horizontal padding: 16 pt
- Header control touch target: 44 pt
- `TopNavView` height: `navHeight` = `56`
- Header divider Y: `safeAreaTop + navHeight`
- Header title center aligned to screen, not to remaining space between buttons
- `navTouchTargetHeight`: `44`
- Nav content is vertically centered within the 56 pt nav band.
- Nav content top Y = `safeAreaTop + ((navHeight - navTouchTargetHeight) / 2)`.
- Nav content bottom Y = `safeAreaTop + ((navHeight + navTouchTargetHeight) / 2)`.
- Divider Y = `safeAreaTop + navHeight`.

Source of truth:

- `navHeight` is one shared constant.
- `TopNavView` height = `navHeight`.
- Header divider sits at `safeAreaTop + navHeight`.

## 4. Header Height

Fixed first-pass header dimensions:

- Nav height: 56 pt
- Nav touch target height: 44 pt
- Divider height in expanded state: 1 pt

Rules:

- Header must not overlap the activity title.
- Activity content must start below `safeAreaTop + navHeight`.
- In preview, header can be visually transparent.
- In expanded state, header should not look like a detached floating rectangle.
- Nav content is vertically centered in the 56 pt nav band using the formula in Section 3.

## 5. Map Visible Ratio

Preview map visibility is the most important frame metric.

Target:

- Visible map ratio in preview: 64% of screen height.
- `previewSheetTopRatio`: `0.64`.
- `screenHeight = UIScreen.main.bounds.height`.
- `screenHeight` is read once at the root.
- `previewSheetTop = screenHeight * 0.64`.
- No child view may compute its own local screen height for sheet anchors.

For an iPhone portrait screen with 852 pt height:

- Map-dominant visible area: 545 pt.
- Sheet top Y: 545 pt.

Rules:

- Map should feel like the background layer.
- Map should not feel like a component placed inside a page.
- Route line must remain readable in the visible map area.
- Bottom sheet should not start so high that the map loses dominance.

## 6. Preview Sheet Position

Preview sheet should start low.

Target:

- `previewSheetTopRatio`: `0.64`.
- `screenHeight = UIScreen.main.bounds.height`.
- `screenHeight` is read once at the root.
- `previewSheetTop = screenHeight * previewSheetTopRatio`.
- Preview sheet visible height = `screenHeight - previewSheetTop`.
- Preview summary must fit inside preview visible height.
- Preview content must not resize the preview anchor.

Preview sheet content:

- Activity title
- Date/location
- Three key metrics

Do not show in preview:

- Athlete block
- Graphs
- Extended metric grid
- PR cards
- Long descriptions
- AI/coaching/recovery content

## 7. Expanded Sheet Position

Expanded state should become a white detail page.

Target:

- `expandedSheetTop = 0`
- The sheet starts at absolute Y = 0 when expanded.
- In expanded state, `BottomSheetContainer` offset = 0.
- Expanded sheet covers map fully behind status/nav.
- Sheet/content begins below fixed nav.
- No map visible behind top safe area or nav.
- The top nav remains above the sheet in `ZStack`.
- `TopNavView` is over the sheet in the `ZStack` but does not consume sheet layout.
- The sheet's own white background covers the status bar, nav area, breathing space, and all content behind it.

Content start target:

- Sheet internal content must add top padding equal to `safeAreaTop + navHeight + expandedContentTopPaddingBelowNav`.
- First-pass formula: `safeAreaTop + 56 + 36`.

Rules:

- Top nav stays fixed outside the sheet.
- Sheet movement must not push the nav.
- Internal `ScrollView` must not receive the sheet offset.
- Expanded state should not look like a card floating over a map.
- There is no independent detached white nav box.

## 8. Sheet Corner Radius

Preview:

- Sheet top radius: 14 pt.
- Radius should be small enough to feel attached to the map, not like a large floating card.

Expanded:

- Radius: 0 pt.
- Expanded state should feel like a full white page.

Anti-pattern:

- Any radius above 16 pt makes the sheet feel like a custom SOOM card instead of a Strava-like activity page.

## 9. Handle Size And Placement

Handle should be subtle and functional.

Fixed first-pass values:

- Width: 40 pt
- Height: 4 pt
- Corner radius: 2 pt
- Top padding: 10 pt
- Bottom padding before content: 12 pt

Preview:

- Handle can be visible.
- Handle sits centered at the top of the sheet.

Expanded:

- Handle can be hidden or extremely subtle.
- If kept for prototype stability, it should not create a separate card header.
- Handle region should not push content into a visibly detached summary block.

## 10. Content Padding

Horizontal padding:

- Activity detail content: 32 pt.
- Header horizontal padding: 16 pt.

Vertical padding:

- Preview sheet internal top after handle: 16 pt.
- Activity title to metadata: 8 pt.
- Metadata to key metrics: 28 pt.
- Major section top spacing: 36 pt.
- Section title to chart/content: 16 pt.

Rules:

- Use consistent content rails.
- Avoid mixing 16 pt, 24 pt, 32 pt, and custom offsets without reason.
- Content should not sit under the fixed nav.

## 11. Section Spacing

Strava-style sections are long but scan-friendly because they are graph-first and metric-first.

Fixed first-pass spacing:

- Section top margin: 36 pt
- Section title bottom margin: 16 pt
- Chart height: 140 pt
- Chart to stats row: 16 pt
- Section separator top/bottom padding: 28 pt

Rules:

- Use separators sparingly.
- Avoid card stacks.
- Let graph, values, and labels define each section.
- Do not create heavy SOOM report blocks.

## 12. Metric Grid Structure

Main metric grid should feel like data, not cards.

Structure:

- 2-column or 3-column grid depending on available width and content.
- No heavy card backgrounds for each metric.
- Values are visually stronger than labels.
- Labels are compact and subdued.

Fixed first-pass values:

- Grid columns: 2 for dense detail, 3 for preview/key metrics.
- Column gap: 24 pt.
- Row gap: 24 pt.
- Metric value size target: 28 pt.
- Metric label size target: 12 pt.
- Unit treatment: close to value, smaller if separated.

Preview metrics:

- Exactly three key facts.
- Typical set: distance, time, pace/speed.

Expanded metrics:

- Distance
- Elevation gain
- Moving time
- Avg speed / pace
- Avg heart rate
- Calories
- Power if available
- Cadence if available

## 13. Profile Block Structure

Profile block appears in expanded content, not preview.

Structure:

- Small avatar left
- User name
- Date/time
- Location
- Activity title below or near metadata depending reference state

Fixed first-pass values:

- Avatar size: 36 pt.
- Text stack spacing: 3 pt.
- Profile block bottom spacing before title/metrics: 28 pt.

Rules:

- Avatar should not dominate the screen.
- Profile block supports attribution; it is not the hero.
- Route map and activity metrics remain primary.

## 14. PR Card Placement

PR or achievement cards are secondary.

Placement:

- After the primary activity facts and before deeper lower sections, if present.
- Should not appear in preview.
- Should not interrupt the map-first read.
- Should be visually quieter than route, title, and metrics.

Fixed first-pass structure:

- Compact row or small module.
- Height: 72 pt.
- Horizontal padding aligns to content rail.

SOOM rule:

- Do not add PR cards until the frame, metric hierarchy, and scroll behavior are stable.
- If added later, keep them separate from recovery/coaching analysis.

## 15. Scroll Behavior

Preview:

- Sheet is positioned low.
- User can drag sheet up to expanded.
- Content inside preview is minimal; internal scrolling is not primary.

Expanded:

- Sheet becomes full-page white surface.
- Internal content scrolls normally.
- Header remains fixed.
- Map is covered behind status/nav and sheet.

Gesture ownership:

- Sheet drag owns preview-to-expanded transition.
- Internal `ScrollView` owns content scrolling after expanded.
- Avoid overscroll-based collapse until core behavior is stable.
- Avoid making the entire content area both scroll and sheet-drag owner in the first pass.

Frame Lock phase gesture rule:

- In preview state, the full sheet header region is draggable.
- The draggable region includes handle plus compact summary area.
- In expanded state, only the visible handle/top drag target controls collapse.
- Internal `ScrollView` scrolling is disabled in preview and enabled in expanded.
- Do not implement overscroll-to-collapse in Frame Lock phase.
- Internal `ScrollView` never controls sheet collapse during Frame Lock phase.

## 16. Expanded-State Behavior

Expanded state should feel like native full-page detail.

Required behavior:

- White status bar background.
- White fixed nav.
- Thin divider below nav if needed.
- Content starts below nav.
- No map visible above content.
- No detached white nav box.
- No duplicated header/title stack.
- No sheet shadow that makes the expanded page feel like a card.

Fixed first-pass top layout:

- `0...safeAreaTop`: painted by expanded sheet background
- `safeAreaTop...safeAreaTop + 56`: fixed nav over expanded sheet background
- `safeAreaTop + 56...contentStart`: white breathing space painted by expanded sheet background
- `contentStart...`: scroll content

Expanded offset rule:

- `expandedSheetTop = 0`.
- Expanded sheet absolute Y = 0.
- In expanded state, `BottomSheetContainer` offset = 0.
- The top nav remains above the sheet in `ZStack`.
- `TopNavView` is over the sheet in the `ZStack` but does not consume sheet layout.
- Sheet internal content adds top padding equal to `safeAreaTop + navHeight + expandedContentTopPaddingBelowNav`.
- The sheet's own white background covers status, nav area, breathing space, and all content behind it.
- There is no detached white nav box.

## 17. Motion Observations

Observed target motion:

- Map is the first mental anchor.
- Sheet rises over the map.
- Top controls stay spatially stable.
- Preview-to-expanded should feel like the sheet becomes the page.
- Expanded content scrolls independently after the sheet settles.

First-pass motion rules:

- Use only two snap states: preview and expanded.
- Use numeric sheet offset.
- Render with `currentOffset + dragTranslation`.
- On release, snap from the current release position.
- Do not animate by first resetting to an old anchor.
- Do not continuously update map camera while dragging.
- Keep map camera stable until sheet motion is solved.

Transition rules:

- Top nav never moves vertically.
- Only nav background/icon color may change between preview and expanded.
- Sheet is the only moving layer.
- `ScrollView` never receives offset.
- If an opacity helper is used, it must be full-width, aligned to top, and must not create a detached nav rectangle.
- White helper opacity follows expansion progress.
- All preview<->expanded transitions use `.spring(response: 0.4, dampingFraction: 0.85)`.
- The same animation applies to `sheetOffset` and any opacity-based visual overlay.
- No other animation curve is used in Frame Lock phase.
- No map camera animation during Frame Lock phase.

Sheet clamp:

- `sheetOffset` must be clamped between `expandedSheetTop` and `previewSheetTop`.
- User cannot drag above `expandedSheetTop`.
- User cannot drag below `previewSheetTop`.

Future motion:

- Add camera reframing only after sheet/nav/content layers are stable.
- Feed route map to detail route map transition can be considered later.

## 18. Anti-Patterns Discovered From Failed SOOM Attempts

Do not repeat these patterns:

- Treating the screen as a normal `ScrollView` with map as the first item.
- Putting the top nav inside the movable sheet.
- Creating a detached white nav rectangle/card.
- Letting nav move vertically with sheet offset.
- Offsetting the internal `ScrollView` instead of only the sheet container.
- Showing map behind the status/nav area in expanded state.
- Using random spacers to patch safe-area gaps.
- Starting preview sheet too high.
- Making the sheet look like a floating card.
- Using a large sheet corner radius.
- Showing athlete block, graphs, or extended metrics in preview.
- Duplicating preview summary and expanded summary without clear hierarchy.
- Mixing sheet drag, internal scroll, and map gestures before the base model is stable.
- Collapsing based on internal scroll offset before gesture ownership is deterministic.
- Updating Mapbox camera continuously during drag, causing jitter.
- Adding SOOM AI, recovery, coaching, or growth blocks before recreating the reference frame.
- Polishing typography and graphs before locking map ratio, nav position, and sheet start position.

## 19. Anti-Divergence Checklist

Two engineers should produce the same frame if they follow these checks:

- No `NavigationStack`-owned nav for the prototype.
- No detached nav box.
- No random spacers for safe area.
- No nav inside sheet.
- No offset on `ScrollView`.
- No continuous map camera updates during drag.
- Sheet offset is applied only to `BottomSheetContainer`.
- Top nav is positioned only by the root `ZStack`.
- `safeAreaTop` is read once at root.
- `screenHeight` is read once at root using `UIScreen.main.bounds.height`.
- Nav content is vertically centered in the `navHeight` band.
- Expanded white background comes from sheet background, not detached nav box.
- Preview drag area is full sheet header.
- Expanded collapse drag area is visible top handle/target.
- Transition animation is fixed `.spring(response: 0.4, dampingFraction: 0.85)`.
- Expanded sheet starts at absolute Y = 0.
- Preview sheet top is exactly `screenHeight * 0.64`.
- Sheet internal content top padding is exactly `safeAreaTop + 56 + 36`.

## Frame-Lock Constants For Next Prototype

Use these as initial constants:

- `previewSheetTopRatio`: `0.64`
- `previewSheetVisibleHeight`: `screenHeight - previewSheetTop`
- `expandedSheetTop`: `0`
- `navHeight`: `56`
- `expandedContentTopPaddingBelowNav`: `36`
- `sheetPreviewCornerRadius`: `14`
- `sheetExpandedCornerRadius`: `0`
- `handleWidth`: `40`
- `handleHeight`: `4`
- `contentHorizontalPadding`: `32`
- `sectionTopSpacing`: `36`
- `chartHeight`: `140`

Acceptance for frame-lock:

- Preview screenshot shows map dominance.
- Expanded screenshot shows a full white top/page with no map strip.
- Header is fixed and not pushed by sheet.
- Content starts below header.
- Preview and expanded feel like the same sheet becoming a page.
- No content/graph/typography tuning happens until these frame checks pass.

## Frame Lock Validation Result

Validated behavior:

- Preview -> Expanded works.
- Expanded -> Preview works.
- TopNav remains fixed.
- Sheet offset works independently.
- Internal `ScrollView` scrolls only in expanded state.

Intentionally deferred:

- Map camera animation is intentionally deferred.
- Overscroll-to-collapse is intentionally deferred.
- Real Mapbox integration is deferred.
- Content, typography, and chart polish are deferred.
