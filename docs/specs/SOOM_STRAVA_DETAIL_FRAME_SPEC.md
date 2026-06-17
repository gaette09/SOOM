# SOOM Strava Detail Frame Spec

## Purpose

This document converts Strava activity-detail screenshot observations into fixed layout rules before further implementation.

The goal is to lock the frame first, then add content, then tune typography and graphs.

## 1. Core Principle

Do not start from content.

Start from the frame:

- Map
- Status bar
- Top navigation
- Bottom sheet
- Scroll content

Content, graphs, typography, and visual polish come later. If the frame is unstable, content tuning will only hide the actual layout problem.

## 2. Layer Model

The activity detail prototype should use clear, separate layers:

1. Layer 1: full-screen map
2. Layer 2: fixed top controls/nav
3. Layer 3: movable bottom sheet
4. Layer 4: sheet scroll content

The top nav must not be implemented as part of the sheet. The sheet must not control the nav position.

## 3. Preview State Rules

Preview state is map-first.

- Map is dominant.
- Top controls float over the map.
- Sheet starts low.
- Preview sheet shows only:
  - Activity title
  - Date/location
  - 3 key metrics
- Do not show athlete block in preview.
- Do not show graphs in preview.
- Do not show extended metrics in preview.

The user should understand the route first, then decide to expand for detail.

## 4. Expanded State Rules

Expanded state should feel like a full white activity detail page.

- Status bar background is white.
- Top nav is fixed directly below the status bar.
- Top nav does not move with the sheet.
- Map must not show behind the status/nav area.
- Sheet/content starts below nav.
- Expanded state feels like one continuous white page.

The nav belongs to the page frame, not to the scroll content and not to the sheet surface.

## 5. Required Approximate Numbers For iPhone Portrait

Use these as frame-lock targets before tuning content:

- Preview map visible ratio: 60-70%
- Preview sheet top: around 62-68% of screen height
- Expanded sheet top: 0
- Expanded content start: `safeAreaTop + navHeight + 32-44`
- Nav height: 52-60
- Sheet corner radius: 12-16 in preview, 0-8 when expanded
- Handle height: 4
- Handle width: 36-44
- Horizontal content padding: 28-36

These values are approximate, but they should be explicit constants rather than scattered spacers.

## 6. Motion Rules

- Top nav is fixed.
- Sheet moves.
- Content scrolls only after expanded.
- Nav must not move with the sheet.
- Content must not be pushed by nav during sheet movement.
- In expanded state, no map strip should appear behind the status/nav area.
- Preview-to-expanded motion should feel like the sheet becomes the white page.

The map can remain visually stable for the first prototype. Camera animation can come later.

## 7. Anti-Patterns

Avoid these patterns:

- Do not create a detached white nav box.
- Do not make nav part of sheet content.
- Do not patch safe area with random spacers.
- Do not duplicate preview content and expanded content in a confusing way.
- Do not tune graph/font before the frame is locked.
- Do not let the sheet own normal content scrolling until it is expanded.
- Do not let the nav shift vertically because the sheet is moving.

## 8. Implementation Plan

Create a new prototype file:

- `StravaDetailFrameLockView.swift`

Do not keep patching `StravaDetailClonePrototypeView`.

Implementation order:

1. Implement only the frame lock:
   - Full-screen map
   - Fixed top nav/status region
   - Movable bottom sheet
   - Preview and expanded states
2. Compare screenshots against Strava references.
3. Adjust only frame constants until the structure matches.
4. After the frame passes, add content.
5. After content passes, tune typography and graphs.

The next implementation should prove the frame first, with minimal placeholder content only.
