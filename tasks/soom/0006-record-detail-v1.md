# Task 0006: Record Detail V1

## Goal

Implement Record Detail V1.

## Required Reading

Read both spec files before implementation:

- `docs/specs/SOOM_MASTER_SPEC.md`
- `docs/specs/SOOM_GOLDEN_SCREENS.md`

Implementation must follow SOOM's Record philosophy: record builds trust, familiar workout data comes first, and deeper analysis is available without forcing complexity.

## Purpose

Record Detail is the trust engine of SOOM.

The screen should help users immediately understand the workout record, then expand into analysis when they choose.

## Requirements

### Hero Route Map

- Route map is the hero content.
- Route map should be the largest element on the screen.
- Structure the map area so it can support future overlays:
  - PR markers
  - Segment achievements
  - High intensity sections

### Summary Metrics

Show summary metrics for:

- Distance
- Time
- Average speed
- Heart rate
- Elevation gain
- Power, if available
- Cadence, if available

### Expandable Metric Navigation

Add expandable metric navigation from Record Detail to placeholder detail screens.

Examples:

- Heart Rate -> Heart Rate Detail
- Power -> Power Detail
- Cadence -> Cadence Detail

### Placeholder Metric Detail Screens

Create placeholder metric detail screens with local/static content only.

#### Heart Rate Detail

- Average HR
- Max HR
- HR zones
- HR timeline graph

#### Power Detail

- Average power
- Max power
- Power zones
- Power timeline graph
- Power curve placeholder

#### Cadence Detail

- Average cadence
- Max cadence
- Cadence zones
- Cadence timeline graph

### AI Summary

Add an AI Summary section using local/static copy only.

Example:

> 최근 4주 평균보다 강도가 18% 높았습니다.

## Constraints

- Do not implement backend.
- Do not add Supabase.
- Do not add OpenAI/API calls.
- Keep implementation local/mock-only where new data is needed.
- Do not touch Fastlane/TestFlight.
- Do not commit.

## Acceptance Criteria

- Record Detail V1 is visible in the app.
- Route map is the largest and most prominent element on the screen.
- Summary metrics are visible and aligned.
- Heart Rate, Power, and Cadence navigation paths exist.
- Placeholder Heart Rate Detail, Power Detail, and Cadence Detail screens are reachable.
- AI Summary section is visible.
- Existing Feed and Recovery flows are not broken.
- `xcodebuild` build passes.

## Completion Report

After implementation, report:

- Files changed
- Implementation summary
- Build result
- Remaining risks
