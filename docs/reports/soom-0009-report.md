# SOOM 0009 Report: Record Detail Content Lock

Date: 2026-06-22

Task file:

- `tasks/soom/0009-record-detail-content-lock.md`

## Current State

Inspected:

- `docs/ops/TODAY_QUEUE.md`
- `tasks/soom/0009-record-detail-content-lock.md`
- `docs/specs/SOOM_RECORD_DETAIL_MOTION_STUDY.md`
- `docs/specs/STRAVA_ACTIVITY_DETAIL_FRAMELOCK_EXTRACT.md`
- `SOOM/Features/Activity/DetailViews.swift`
- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOM/Features/Activity/StravaDetailFrameLockView.swift`
- `SOOM/Features/Settings/SettingsView.swift`

Repository state:

- Root: `/Volumes/Platinum1TB/SOOM`
- Branch: `main`
- Remote: `origin https://github.com/gaette09/SOOM.git`
- Worktree has untracked documentation/report files only:
  - `docs/ops/TODAY_QUEUE.md`
  - `docs/reports/`
- No app code was modified during this task execution.

Implementation state:

- Production Record Detail enters through `WorkoutDetailView`.
- Production detail content is still rendered by `WorkoutDetailContent` as a stacked page flow:
  - header
  - hero map
  - summary card
  - rhythm card
  - core/growth/sensor/recovery sections
  - actions card
- `StravaDetailFrameLockView` exists as an isolated prototype and is reachable from the Settings prototype area.
- The frame-lock prototype implements the intended structural model:
  - full-screen map layer
  - movable bottom sheet
  - fixed top nav outside the sheet
  - `previewSheetTopRatio = 0.64`
  - `expandedSheetTop = 0`
  - handle-owned preview/expanded drag behavior
- The prototype still has placeholder English copy: `Ride`, `Morning Ride`, `Distance`, `Time`, and `Speed`.

## Findings

1. Record Detail is not locked yet.

   The production screen still uses the existing stacked `WorkoutDetailContent` structure. The Strava frame-lock behavior is present only in a prototype.

2. The desired behavior is documented clearly enough to implement.

   The motion study and frame-lock extract agree that the target is map-first, sheet-next, fixed top nav, and scan-first metrics.

3. The production content hierarchy needs pruning before QA.

   The motion study says the main page should not become a coaching, recovery, weakness, or growth report. Current production content still includes heavier growth/recovery/weakness sections on the main detail page.

4. Korean label cleanup is part of the lock.

   The target requires Korean labels for user-facing metric and action names. The prototype still contains English placeholders.

5. Simulator verification was not run.

   This pass was inspection/reporting only and made no app-code changes.

## Blockers

- Production lock requires an implementation decision: whether to migrate the existing `WorkoutDetailContent` into a frame-lock scaffold or promote/adapt `StravaDetailFrameLockView` into production detail.
- The exact production content set needs to be locked before coding:
  - what stays on main Record Detail
  - what moves to drill-down/later work
  - what gets removed from the first QA target
- Simulator verification cannot be completed until production behavior is implemented or a testable integration branch exists.

## Next Action

Create the implementation task for production Record Detail lock.

Recommended next task scope:

```text
SOOM Record Detail Production Frame Lock

Inputs:
- docs/specs/SOOM_RECORD_DETAIL_MOTION_STUDY.md
- docs/specs/STRAVA_ACTIVITY_DETAIL_FRAMELOCK_EXTRACT.md
- SOOM/Features/Activity/DetailViews.swift
- SOOM/Features/Activity/WorkoutDetailContent.swift
- SOOM/Features/Activity/StravaDetailFrameLockView.swift

Acceptance:
- production detail opens map-first
- summary behaves as sheet content
- fixed top nav behavior matches frame-lock extract
- main content uses Korean labels
- heavy analysis sections are moved out or deferred
- simulator screenshots cover preview, expanded, scrolled, and collapse states
```

