# Strava Activity Detail Frame-Lock Extract

## 1. Coordinate System And Source Of Truth

Coordinate rules:

- All sheet offsets are measured from the absolute screen top, not from the safe-area top.
- Map ignores all safe areas.
- Top nav reads `safeAreaTop` but is positioned by the root `ZStack`.
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

Fixed first-pass values:

- Safe area top: device-dependent and read from `GeometryProxy.safeAreaInsets.top`.
- White expanded top cover height: `safeAreaTop + navHeight`.
- `navHeight`: `56`
- White top cover height: `safeAreaTop + 56`
- White expanded sheet/background covers the status and nav area.

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

Source of truth:

- `navHeight` is one shared constant.
- White top cover height = `safeAreaTop + navHeight`.
- `TopNavView` height = `navHeight`.
- Header divider sits at `safeAreaTop + navHeight`.

## 4. Header Height

Fixed first-pass header dimensions:

- Nav height: 56 pt
- Divider height in expanded state: 1 pt

Rules:

- Header must not overlap the activity title.
- Activity content must start below `safeAreaTop + navHeight`.
- In preview, header can be visually transparent.
- In expanded state, header should not look like a detached floating rectangle.

## 5. Map Visible Ratio

Preview map visibility is the most important frame metric.

Target:

- Visible map ratio in preview: 64% of screen height.
- `previewSheetTopRatio`: `0.64`.

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
- `previewSheetTop = screenHeight * previewSheetTopRatio`.
- Preview sheet visible height = `screenHeight - previewSheetTop`.
- Preview summary must fit inside preview visible height.
- Preview content must not resize the preview anchor.

## 7. Expanded Sheet Position

Expanded state should become a white detail page.

Target:

- `expandedSheetTop = 0`
- The sheet starts at absolute Y = 0 when expanded.
- Expanded sheet covers map fully behind status/nav.
- Sheet/content begins below fixed nav.
- No map visible behind top safe area or nav.
- The top nav remains above the sheet in `ZStack`.
- The white expanded sheet/background covers the status and nav area.

Content start target:

- Sheet internal content must add top padding equal to `safeAreaTop + navHeight + expandedContentTopPaddingBelowNav`.
- First-pass formula: `safeAreaTop + 56 + 36`.

Rules:

- Top nav stays fixed outside the sheet.
- Sheet movement must not push the nav.
- Internal `ScrollView` must not receive the sheet offset.
- Expanded state should not look like a card floating over a map.

## 8. Scroll Behavior

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

- Use visible handle-only drag.
- Internal `ScrollView` scrolling is disabled in preview and enabled in expanded.
- Do not implement overscroll-to-collapse in Frame Lock phase.
- Collapse only through the visible handle for now.

## 9. Expanded-State Behavior

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

- `0...safeAreaTop`: white status background
- `safeAreaTop...safeAreaTop + 56`: fixed white nav
- `safeAreaTop + 56...contentStart`: white breathing space
- `contentStart...`: scroll content

Expanded offset rule:

- `expandedSheetTop = 0`.
- Expanded sheet absolute Y = 0.
- The top nav remains above the sheet in `ZStack`.
- Sheet internal content adds top padding equal to `safeAreaTop + navHeight + expandedContentTopPaddingBelowNav`.
- The white expanded sheet/background covers status and nav area.

## 10. Motion Observations

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
- White top cover opacity follows expansion progress.
- Sheet animation and white cover animation must share timing.

Sheet clamp:

- `sheetOffset` must be clamped between `expandedSheetTop` and `previewSheetTop`.
- User cannot drag above `expandedSheetTop`.
- User cannot drag below `previewSheetTop`.

Future motion:

- Add camera reframing only after sheet/nav/content layers are stable.
- Feed route map to detail route map transition can be considered later.

## 11. Anti-Divergence Checklist

Two engineers should produce the same frame if they follow these checks:

- No `NavigationStack`-owned nav for the prototype.
- No detached nav box.
- No random spacers for safe area.
- No nav inside sheet.
- No offset on `ScrollView`.
- No continuous map camera updates during drag.
- Sheet offset is applied only to `BottomSheetContainer`.
- Top nav is positioned only by the root `ZStack`.
- Expanded sheet starts at absolute Y = 0.
- Preview sheet top is exactly `screenHeight * 0.64`.
- Sheet internal content top padding is exactly `safeAreaTop + 56 + 36`.
- White top cover height is exactly `safeAreaTop + 56`.

## 12. Frame-Lock Constants

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
