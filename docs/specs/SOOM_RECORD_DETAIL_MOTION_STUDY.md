# SOOM Record Detail Motion Study

## Purpose

This document pauses implementation and defines why the current Record Detail direction still does not feel like Strava. The goal is to align the interaction model before more coding.

SOOM Record Detail should be familiar first. It should let users understand the route, effort, and key metrics quickly, then allow deeper analysis through drill-down screens.

## 1. Current Problem

The current Record Detail implementation still feels like a static long report.

Problems:

- The page reads as a sequence of stacked sections instead of a map-led activity detail.
- It does not yet feel like Strava's activity detail interaction.
- The map appears visually important, but the motion model does not make it feel like the anchor of the screen.
- The bottom-sheet feeling is not strong enough. Detail content should feel like it rises from the route map, not like a normal pushed page.
- Graphs feel decorative and unclear. They do not yet communicate scan-friendly workout patterns.
- User-facing labels are mixed between English and Korean.
- English labels must be replaced with Korean labels.
- The page is not communicating the three core questions clearly enough:
  - Where did this person go?
  - How far and how long did they move?
  - How hard was the effort?

The core issue is not only visual polish. It is information architecture and motion. Record Detail needs to start with route comprehension, then move into metrics.

## 2. Strava Detail Behavior

The intended behavior should be close to Strava's activity detail page.

Key behavior:

- The map appears as the visual anchor.
- Activity detail feels like a sheet rising over or under the map.
- The user first understands the route visually.
- After route comprehension, the user scrolls into metrics.
- Charts are visual scanning tools, not decorative UI.
- Sections can be long, but they remain easy to scan because they are graph-first and metric-first.
- Text is minimal.
- Metric labels are direct.
- Section hierarchy is predictable.

The important Strava pattern is not simply "map at the top." It is "map first, sheet next." The route creates spatial trust, then the sheet provides workout facts.

Good Strava-like section behavior:

- A chart should answer one question quickly.
- The values below the chart should explain the chart.
- The section should not require reading a paragraph.
- The user should be able to scan section titles and key values without slowing down.

## 3. SOOM Record Detail Direction

SOOM Record Detail should be Strava-familiar first.

SOOM originality should be restrained on the main detail page. The main page should not become a coaching report, recovery report, or growth analysis page.

Direction:

- Route and metrics come first.
- AI should be short.
- AI should summarize, not coach at length.
- Recovery, coaching, weakness, and growth reports should not be on the main detail page.
- Advanced SOOM analysis should move to separate drill-down pages.
- Record Detail should build trust through familiar workout facts.
- SOOM insight should sit lightly on top of the record, not replace the record.

The main page should answer:

- Route: where did this workout happen?
- Effort: how hard was it?
- Metrics: what are the key numbers?
- Trend: what should I inspect deeper if I care?

## 4. Required Layout Direction

Top to bottom:

1. Map-first entry
2. Bottom-sheet-like activity summary
3. Athlete/activity title
4. Key metric grid
5. Short Korean AI summary
6. Heart Rate section
7. Pace/Speed section
8. Cadence section
9. Elevation section
10. Power section if available
11. Splits
12. Save / Share / Image actions

Main layout rules:

- The route map should be the first visual impression.
- The map should be large enough to understand the route shape.
- The summary sheet should overlap or visually attach to the map.
- The sheet should contain only compact essentials at first.
- Detailed metrics should continue below the sheet.
- The main page should avoid heavy card stacks.
- Section titles should be clear and Korean.
- Graphs should have visible purpose and nearby key values.

## 5. Motion Direction

Future interaction should define the screen as map + sheet, not a standard pushed page.

Motion goals:

- Feed card route map should connect naturally to Record Detail route map.
- Record Detail should feel like map + sheet, not a standard pushed page.
- On entry, the route map should be large.
- As the user scrolls, the sheet content moves over the map.
- Header should simplify while scrolling.
- The map should feel alive and primary.

Expected interaction:

- Feed card route map is tapped.
- Record Detail opens with the same route concept visually preserved.
- The map occupies the top hero area.
- A compact activity summary sheet sits at the bottom edge of the map.
- As the user scrolls, the sheet rises and the map recedes.
- Navigation controls remain lightweight.
- The route remains the mental anchor even after the user enters metrics.

Do not solve this with more copy or more cards. Solve it with hierarchy, motion, and clear metric presentation.

## 6. Korean Label Rules

All user-facing labels should be Korean.

Required replacements:

- Heart Rate -> 심박
- Power -> 파워
- Cadence -> 케이던스
- Pace -> 페이스
- Speed -> 속도
- Elevation -> 고도
- Splits -> 스플릿
- Athlete Intelligence -> 운동 분석
- Save -> 저장
- Share -> 공유
- Image -> 이미지

Additional label rules:

- Prefer short labels.
- Avoid mixed Korean/English labels in the same section.
- Keep technical metric units as standard abbreviations when useful, such as bpm, W, rpm, km/h.
- Do not use long explanatory section headings on the main detail page.

## 7. Implementation Plan

Recommended next steps:

1. Revert or reduce the current over-customized Record Detail sections if needed.
2. Build the map + sheet structure first.
3. Verify the initial screen communicates route-first behavior before rebuilding sections.
4. Rebuild sections one by one in Korean:
   - 심박
   - 페이스 / 속도
   - 케이던스
   - 고도
   - 파워
   - 스플릿
5. Make charts useful scanning tools before styling them.
6. Keep AI to one short Korean summary.
7. Do not add more AI sections.
8. Do not add more text-heavy coaching blocks.
9. Keep recovery, growth, weakness, and coaching analysis out of the main Record Detail page.
10. Move advanced SOOM analysis into separate drill-down pages.
11. Use mock data only until the interaction is correct.

The next implementation should start with interaction structure, not visual ornament. The first milestone is a map-first route detail that feels like a sheet rising from the map and uses Korean labels throughout.
