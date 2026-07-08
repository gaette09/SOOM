# SOOM Record Active HUD Device QA Checklist

## Scope

Physical device QA for `53029e7 feat(record): add compact active workout hud`.

Use a real iPhone. Do not upload TestFlight until this checklist is complete.

## Result Fields

For each item, mark one:

- PASS
- FAIL
- NEEDS PATCH

Add notes for any visual issue, crash, lag, overlap, or unexpected behavior.

## Checklist

| Area | Check | Result | Notes |
| --- | --- | --- | --- |
| Record launch | Record screen opens normally. |  |  |
| READY | READY drag-select-release still works. |  |  |
| Sport selection | Cycling selection starts a cycling workout. |  |  |
| Sport selection | Running selection starts a running workout. |  |  |
| Sport selection | Walking selection starts a walking workout. |  |  |
| Compact default | Compact HUD appears by default after workout starts. |  |  |
| Compact placement | Compact HUD sits above pause/end/cancel controls. |  |  |
| Compact placement | Compact HUD does not overlap map controls. |  |  |
| Compact readability | Elapsed time is centered and readable. |  |  |
| Cycling metric | Cycling compact HUD shows current speed. |  |  |
| Running metric | Running compact HUD shows current pace. |  |  |
| Walking metric | Walking compact HUD shows current speed. |  |  |
| Expand | Expand button opens full HUD. |  |  |
| Expanded HUD | Full HUD shows the existing sport-specific metric grid. |  |  |
| Collapse | Collapse button returns to compact HUD. |  |  |
| Pause/resume | Pause and resume do not break HUD state or layout. |  |  |
| End/save | End/save flow remains unchanged. |  |  |
| Map behavior | Heading follow/navigation cone behavior remains unchanged. |  |  |
| Route recommendation | Route recommendation remains hidden. |  |  |
| Stability | No crash during start, pause, resume, end, or save. |  |  |

## Decision Rule

- If Record HUD passes on Cycling, Running, and Walking, proceed toward TestFlight readiness review.
- If HUD layout or overlap issues remain, create a focused Record HUD patch before TestFlight.
- If save flow or heading follow regresses, block TestFlight.

## QA Focus

- Compact HUD default behavior.
- Bottom-layer spacing between HUD and pause/end/cancel controls.
- Map control depth and visual separation.
- Sport-specific live metric mapping.
- Preserve existing lifecycle and save behavior.
