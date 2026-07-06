# SOOM Build 8 Device QA Checklist

Date: 2026-07-06

Build under QA:

- `29d0ded feat(activity): refine workout detail hierarchy`
- `0ee831b docs(qa): add build 8 activity detail qa report`

Purpose: run this checklist on iPhone before deciding whether Build 8 needs a patch or can move to TestFlight preparation.

Result options:

- PASS
- FAIL
- NEEDS PATCH

## Device And Build

| Item | Result | Notes |
| --- | --- | --- |
| iPhone model and iOS version recorded |  |  |
| Installed app build opens successfully |  |  |
| No launch crash after cold start |  |  |

## Activity Detail Entry

| Check | Result | Notes |
| --- | --- | --- |
| Activity Detail opens from Activity list / workout library |  |  |
| Route-backed workout detail opens correctly |  |  |
| Detail navigation does not crash when opening, closing, and reopening |  |  |
| UI density feels improved, not more crowded than Build 7 |  |  |

## Route And Map

| Check | Result | Notes |
| --- | --- | --- |
| Route-backed detail uses the shared SOOM Mapbox style |  |  |
| Route line is visible and framed coherently |  |  |
| Map sheet opens/collapses without broken layout |  |  |
| Map style does not look reverted or mismatched |  |  |

## Top Detail Hierarchy

| Check | Result | Notes |
| --- | --- | --- |
| One-line SOOM rhythm insight appears near the top |  |  |
| Rhythm insight copy feels calm and recovery-first |  |  |
| Rhythm insight is not repeated as multiple AI cards |  |  |
| Four core stat tiles display correctly |  |  |
| Distance tile is correct or shows a sensible pending state |  |  |
| Duration tile is correct |  |  |
| Average pace/speed tile is correct for the sport |  |  |
| Recovery-impact stat displays when available |  |  |
| Heart-rate fallback stat displays when recovery impact is unavailable |  |  |
| Tile labels and values fit without awkward clipping |  |  |

## Comparison And Data States

| Check | Result | Notes |
| --- | --- | --- |
| Comparison area appears only when meaningful baseline data exists |  |  |
| Comparison area is omitted when data is insufficient |  |  |
| Comparison copy avoids competitive/ranking language |  |  |
| Sparse workout does not show empty charts, splits, or metric dumps |  |  |
| No-route workout fallback remains coherent and intentional |  |  |

## Regression Checks

| Check | Result | Notes |
| --- | --- | --- |
| Record map behavior is not affected |  |  |
| Feed opens normally |  |  |
| Feed workout cards look unchanged |  |  |
| Share composer opens from Activity Detail |  |  |
| Share card preview renders normally |  |  |
| No crash during Activity Detail to Feed to Share navigation |  |  |

## Accessibility And Layout Spot Check

| Check | Result | Notes |
| --- | --- | --- |
| Larger text size remains readable in the top stat area |  |  |
| VoiceOver reads rhythm insight and stat summary coherently |  |  |
| Buttons and sheet controls remain tappable |  |  |
| Korean copy wraps cleanly on the test device |  |  |

## Decision Rule

- If Activity Detail, Record, Feed, and Share pass on device, proceed to Build 8 TestFlight preparation.
- If Activity Detail has visual, copy, or layout issues, create a Build 8 follow-up patch before TestFlight.
- If Record, Feed, or Share regressions appear, block TestFlight.

## Final Decision

| Decision | Result | Notes |
| --- | --- | --- |
| Ready for TestFlight preparation |  |  |
| Needs Build 8 Activity Detail patch |  |  |
| Blocked by Record/Feed/Share regression |  |  |
