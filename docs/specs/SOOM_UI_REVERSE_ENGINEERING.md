# SOOM UI Reverse Engineering

## Purpose

This document defines a repeatable process for analyzing and reproducing high-quality mobile app UI in SOOM.

The goal is not to copy a product blindly. The goal is to understand why a reference screen works, extract its frame, motion, typography, components, and measurements, then adapt the right parts into SOOM without losing SOOM's product direction.

First example: Strava Activity Detail.

## 1. Reference App

For each study, define the reference app and the exact screen being analyzed.

Record:

- App name
- Platform
- App version if known
- Screen name
- User state, such as logged in, logged out, own activity, friend activity, empty state, or premium state
- Primary user goal on the screen
- Why this reference matters for SOOM

Example:

- Reference app: Strava
- Platform: iOS
- Screen: Activity Detail
- State: completed ride/run detail
- Primary goal: understand route, effort, and key metrics quickly
- Why it matters: SOOM Record Detail needs to feel familiar to workout users before adding SOOM-specific intelligence

## 2. Screenshot Source

Use consistent screenshot sources so analysis is not based on memory.

Preferred sources:

- Real device screenshots
- Simulator screenshots only when the reference app can run there
- Screen recordings for motion behavior
- Multiple activity types, such as ride, run, walk, and indoor workout
- Multiple scroll positions

Capture at minimum:

- Initial state
- Slight scroll
- Main metrics area
- First chart section
- Splits or lower detail section
- Any expanded/collapsed sheet states
- Navigation transition if relevant

Example for Strava Activity Detail:

- Initial map-first view
- Sheet preview state
- Expanded top state
- Mid-scroll metrics/charts
- Splits section
- Collapse or back transition if visible

## 3. Frame Analysis

Analyze the large layout frame before content.

Do not start by tuning fonts, graphs, colors, or individual metric copy. First identify the frame:

- Status bar behavior
- Top navigation position
- Map or hero area
- Sheet or content start position
- Scroll container
- Safe-area handling
- Bottom controls or tab interference

Questions:

- What fills the screen behind everything?
- Which elements are fixed?
- Which elements move?
- Which elements scroll?
- Where does content begin in each state?
- Does the screen feel like a pushed page, modal, bottom sheet, or full-screen canvas?

Strava Activity Detail frame notes:

- The route map is the visual anchor.
- The top controls float over the map in preview.
- The sheet starts low enough for the map to dominate.
- Expanded state should become a full white detail page.
- The nav must not move with the sheet.
- The sheet/content should start below the fixed nav.

## 4. Motion Analysis

Motion analysis should come before visual polish.

Record:

- Entry transition
- Whether the map remains fixed or scrolls away
- Sheet snap states
- Drag zones
- Scroll ownership rules
- Header transition
- Whether content scrolls independently from the sheet
- Camera movement, if map-based

Questions:

- What happens on first drag?
- What happens on release?
- Does the animation continue from the release point?
- Which gestures are owned by the sheet?
- Which gestures are owned by the internal scroll view?
- Does the map camera move during drag or only after snap?

Strava Activity Detail motion notes:

- The screen should feel like map plus sheet, not a static page with a map at the top.
- Preview state prioritizes route comprehension.
- Expanded state prioritizes detail reading.
- Map camera should be stable before adding complex camera animation.
- Avoid mixing sheet drag, internal scroll, and map gestures until the basic model is stable.

## 5. Typography Analysis

Analyze typography after the frame is stable.

Record:

- Title size and weight
- Metadata size and color
- Metric value size and weight
- Metric label size and color
- Section title size and weight
- Body copy line height
- Use of uppercase, punctuation, and units

Questions:

- What is the largest text on the screen?
- What does the user read first?
- Which labels are intentionally quiet?
- Are units visually attached to numbers or treated as labels?
- How much text is required to understand the screen?

Strava Activity Detail typography notes:

- Activity title should be prominent.
- Metric values should be stronger than metric labels.
- Labels should be compact and low-noise.
- Section titles should be direct.
- Text should be minimal; charts and metrics carry the screen.

## 6. Component Analysis

Break the screen into reusable component roles, not just visual shapes.

Record:

- Navigation controls
- Map/route media
- Preview summary
- Athlete/activity header
- Metric grid
- Chart section
- Zone bars
- Splits table
- Action row

For each component:

- Purpose
- Required content
- Optional content
- Interaction behavior
- Visual priority
- Reuse potential in SOOM

Strava Activity Detail component notes:

- Route map: primary trust element
- Summary sheet: compact first-read activity facts
- Metric grid: fast scan, not a card-heavy report
- Chart sections: graph first, values second
- Splits: table-like, dense, easy to compare
- Actions: save/share/image should be low-noise

## 7. Layout Measurements

Use measurements to validate the frame, not to create false precision.

Measure:

- Screen size
- Safe area top and bottom
- Top nav height
- Map visible ratio
- Sheet start Y
- Sheet corner radius
- Sheet handle size
- Horizontal content padding
- Vertical gaps between major regions
- Metric grid columns and row spacing
- Chart height
- Section separator spacing

For screenshot-only references:

- Use pixel measurements as ratios first.
- Convert ratios into SwiftUI constants later.
- Compare across multiple screenshots before locking a value.

For live web references:

- DOM extraction tools may help with web layout.
- They do not directly extract native iOS layout from screenshots.

Strava Activity Detail starting frame targets:

- Preview map visible ratio: 60-70%
- Preview sheet top: around 62-68% of screen height
- Expanded sheet top: 0
- Expanded content start: `safeAreaTop + navHeight + 32-44`
- Nav height: 52-60
- Sheet corner radius: 12-16 in preview, 0-8 expanded
- Handle height: 4
- Handle width: 36-44
- Horizontal content padding: 28-36

## 8. SwiftUI Architecture Notes

Translate observations into clear SwiftUI ownership rules before coding.

Define:

- Root container
- Fixed layers
- Movable layers
- Scroll containers
- Gesture ownership
- State ownership
- Preview-only content
- Expanded-only content

Preferred architecture for Strava-like Activity Detail prototype:

- Root `ZStack` ignores safe area.
- Layer 1: full-screen map.
- Layer 2: conditional white status/nav cover in expanded state.
- Layer 3: fixed top nav outside the sheet.
- Layer 4: movable bottom sheet.
- Layer 5: sheet internal `ScrollView`.

State ownership:

- Parent view owns snap state.
- Parent view owns numeric sheet offset.
- Sheet does not own nav position.
- `ScrollView` does not receive sheet offset.
- Map camera should not update continuously during sheet drag in the first pass.

Anti-patterns:

- Nav inside sheet content.
- Detached white nav card.
- Random safe-area spacers.
- Duplicate preview and expanded content without hierarchy.
- Overscroll-based collapse before the sheet model is stable.
- Graph or typography tuning before frame lock.

## 9. SOOM Adaptation Notes

After the reference is understood, decide what SOOM should keep, change, or reject.

Keep:

- Proven interaction patterns that users already understand.
- Route-first hierarchy for workout detail.
- Metric-first scanning.
- Minimal text on the main detail page.
- Korean labels for user-facing SOOM screens.

Change:

- Apply SOOM design tokens only after the frame works.
- Use SOOM-specific intelligence lightly.
- Move deeper coaching, recovery, and growth analysis into drill-down screens.

Reject:

- Copying Strava branding or exact visual identity.
- Adding SOOM AI/recovery bubbles into clone/prototype screens.
- Turning Record Detail into a long coaching report.
- Hiding route comprehension behind photos or decorative cards.

Strava Activity Detail SOOM adaptation:

- SOOM Record Detail should be Strava-familiar first.
- The route map should answer where the person went.
- Key metrics should answer how far, how long, and how hard.
- AI should appear as one short Korean `운동 분석` summary, not a full coaching block.
- Recovery, growth, weakness, and coaching sections should not live on the main detail page.
- Advanced SOOM analysis belongs in separate drill-down areas after the base activity detail feels trustworthy.
