# Task 0008: Strava Activity Detail Clone Prototype

## Goal

Build a Strava Activity Detail clone prototype focused only on interaction behavior.

This prototype is for studying the interaction model before applying any ideas back to SOOM.

## Important Direction

- Do not make this SOOM.
- Do not add AI.
- Do not add Recovery.
- Do not add Coaching.
- Do not add growth reports, training advice, or SOOM-specific analysis.
- Do not modify the current Record Detail implementation.
- Do not replace existing Record Detail navigation.

## Required Reading

- `docs/specs/SOOM_MASTER_SPEC.md`
- `docs/specs/SOOM_RECORD_DETAIL_MOTION_STUDY.md`

## Prototype Scope

Create a separate mocked prototype screen for a Strava-like activity detail interaction.

The prototype should be isolated from the production Record Detail screen. It may be reachable only through a debug or prototype-only entry point if needed during implementation.

Use mocked/local data only.

## Interaction To Replicate

### Map Behavior

- Large route map is the visual anchor.
- Route is immediately understandable.
- Map remains visually stable while the sheet moves.
- Map should not feel like a normal first item in a vertical page.
- Avoid SOOM-specific map styling or analysis overlays.

### Sheet Behavior

- Detail content behaves like a bottom sheet over the map.
- Initial state shows map-dominant preview.
- Sheet can expand into a detail-reading state.
- Expanded content scrolls normally.
- Sheet movement should feel deterministic and stable.
- Avoid fragile gesture competition between map, sheet, and internal scroll.

### Header Behavior

- Header controls float over the map in the preview state.
- Use a Strava-like structure:
  - back/down control
  - activity type/title
  - save/bookmark
  - more menu
- Header should stay lightweight as the sheet expands.

### Metric Layout

- Replicate Strava-like activity detail hierarchy.
- Include mocked athlete/activity header.
- Include simple metric grid:
  - distance
  - elevation gain
  - moving time
  - average speed or pace
  - heart rate
  - calories
  - power if mocked
  - cadence if mocked
- Keep metric presentation plain and scan-first.

### Scrolling Structure

- User first understands the route visually.
- User then scrolls into details.
- Sections should be graph-first and metric-first, not text-heavy.
- Include mocked sections such as:
  - heart rate
  - speed or pace
  - cadence
  - elevation
  - power
  - splits

## Explicit Non-Goals

- No SOOM AI summary.
- No Athlete Intelligence.
- No Recovery section.
- No Coaching section.
- No growth report.
- No backend work.
- No Supabase.
- No OpenAI/API calls.
- No Fastlane/TestFlight work.
- No changes to Feed.
- No changes to the current Record Detail screen.

## Acceptance

- A separate Strava Activity Detail clone prototype exists.
- Prototype uses mocked/local activity data.
- Prototype demonstrates:
  - map-first entry
  - bottom-sheet-like detail behavior
  - floating header behavior
  - Strava-like metric layout
  - scrollable detail structure
- Current Record Detail remains unchanged.
- Existing Feed and Recovery flows remain unchanged.
- Build succeeds.
- Do not commit.
