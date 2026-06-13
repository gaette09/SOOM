# Task 0007: Record Detail Map Sheet Rework

## Goal

Rework Record Detail around a Strava-like map-first + bottom-sheet interaction structure.

This task is about interaction structure first, not adding more analysis sections.

## Required Reading

Read these files before implementation:

- `docs/specs/SOOM_MASTER_SPEC.md`
- `docs/specs/SOOM_GOLDEN_SCREENS.md`
- `docs/specs/SOOM_RECORD_DETAIL_MOTION_STUDY.md`
- `tasks/soom/0006-record-detail-v1.md`

Implementation must follow SOOM's Record philosophy: the route and workout facts create trust, and deeper SOOM analysis should be available without making the main detail page feel like a report.

## Purpose

Record Detail should feel like:

1. Route map first
2. Activity summary sheet second
3. Details after scrolling

The first impression should let the user understand the route visually before reading analysis.

## Requirements

### Map-First Entry

- Record Detail must open with a large route map.
- The route map must be the visual anchor.
- Use the existing Mapbox-based route map approach where possible.
- The initial visible state should prioritize:
  - Large route map
  - Compact bottom summary sheet
  - Activity title
  - Distance
  - Time
  - Speed / pace

### Bottom-Sheet-Like Summary

- The activity summary should feel like it rises from the map area.
- The sheet should visually attach to or overlap the map.
- The first sheet state should be compact.
- Do not make the entry feel like a normal static pushed detail page.

### Korean Labels

Use Korean labels for all user-facing text.

Required label rules:

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

Keep metric units where useful, such as bpm, W, rpm, and km/h.

### Main Page Structure

Keep the main page Strava-familiar and ordered as:

1. Map-first entry
2. Compact bottom summary sheet
3. Athlete / activity header
4. Key metric grid
5. Short `운동 분석` summary
6. `심박`
7. `페이스` / `속도`
8. `케이던스`
9. `고도`
10. `파워`, if available
11. `스플릿`
12. `저장` / `공유` / `이미지`

### Analysis Scope

- Keep `운동 분석` short and restrained.
- Do not add more AI sections.
- Do not add recovery report blocks.
- Do not add growth report blocks.
- Do not add coaching report blocks.
- Advanced SOOM analysis should remain in drill-down areas, not the main page.

### Feed Scope

- Do not touch Feed unless absolutely required for navigation continuity.
- If Feed is touched, keep the change limited to maintaining route-map-to-record-detail continuity.

## Constraints

- Use mocked/local data only.
- Do not implement backend.
- Do not add Supabase.
- Do not add OpenAI/API calls.
- Do not touch Fastlane/TestFlight.
- Do not commit.

## Acceptance Criteria

- Record Detail opens with a large route map and compact summary sheet.
- The user can immediately understand the route visually.
- Details scroll naturally after the map-focused entry.
- The sheet feels like it rises from the map area.
- English labels are replaced with Korean.
- The main page remains Strava-familiar and does not become a SOOM report.
- Existing Feed and Recovery flows are not broken.
- `xcodebuild` build succeeds.

## Completion Report

After implementation, report:

- Files changed
- Record Detail interaction changes
- Korean label changes
- Build result
- Remaining risks
