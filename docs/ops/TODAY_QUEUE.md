# Today Queue

## Purpose

This document defines the active parallel work queue for today.

Source of truth:

- `docs/ops/PROJECT_GOALS.md`
- `docs/ops/MULTI_PROJECT_OPERATIONS.md`

Operating rules:

- Work only from the listed task files.
- Keep each project in its own context.
- Do not modify app code unless a task explicitly requires implementation.
- Do not deploy.
- Do not commit unless explicitly requested.

## Active Parallel Queue

| Priority | Project | Task | Task file | Status |
| --- | --- | --- | --- | --- |
| P0 | SOOM | Route missing detection and external route fallback plan | `docs/reports/soom-external-route-source-fallback-plan.md` | Documentation/plan only; next implementation should start with route missing detection, then GPX import v1 |
| P1 | SOOM | GPX import v1 planning/implementation | `docs/reports/soom-external-route-source-fallback-plan.md` | User-selected file import; attach parsed route to imported workout through existing route persistence |
| P1 | SOOM | Strava OAuth feasibility spike | `docs/reports/soom-external-route-source-fallback-plan.md` | OAuth only; no scraping/login automation; validate API tier, scopes, route/polyline/streams access, and policy constraints |
| P2 | SOOM | FIT/TCX import research | `docs/reports/soom-external-route-source-fallback-plan.md` | File-based route import after GPX v1 stabilizes |
| P2 | SOOM | Garmin/Wahoo direct integration research | `docs/reports/soom-external-route-source-fallback-plan.md` | Research only after file import and Strava feasibility are understood |
| 2 | JAFOM | 0002 Backup/Rollback Checklist | `tasks/jafom/0002-backup-rollback-checklist.md` | Recommended only if JAFOM 0001 access blocker remains |
| 3 | Instagram | 0002 Harness/Hermes Automation Planning | `tasks/instagram/0002-harness-hermes-automation-planning.md` | Recommended, or replace with static review unblock if external browser/deployment access is available |

## Verification Results From Previous Active Queue

| Project | Verified task | Task file | Result | Evidence |
| --- | --- | --- | --- | --- |
| SOOM | 0009 Record Detail Content Lock | `tasks/soom/0009-record-detail-content-lock.md` | PASS | `docs/reports/soom-0009-verification.md` |
| JAFOM | 0001 External Production Stability Check | `tasks/jafom/0001-external-production-staging-stability-check.md` | BLOCKED | `docs/reports/jafom-0001-verification.md` |
| Instagram | 0001 Static Dashboard External Review | `tasks/instagram/0001-static-dashboard-external-review.md` | BLOCKED | External project report: `/Users/jihwanchung/Documents/Marketing/SOOM_Instagram/docs/reports/instagram-0001-verification.md` |

## SOOM: External Route Source Fallback

Goal:

- Define a compliant route-source fallback strategy for external workouts whose HealthKit summaries import but whose routes are not available through `HKWorkoutRoute`.

Verification:

- Keep HealthKit `HKWorkoutRoute` as the first route source.
- Plan GPX import v1 as the next user-controlled route fallback.
- Plan FIT/TCX import as a later file-based route source.
- Keep Strava to an OAuth/API-policy feasibility spike with no scraping or login automation.
- Keep Garmin/Wahoo direct integration as research only.
- Preserve privacy, route deletion, and no-public-display constraints for external route data.

Expected outcome:

- A documented fallback strategy exists for route-missing external workouts, with clear route source priority and a recommended GPX v1 implementation path.

Completion criteria:

- HealthKit route limitations are documented.
- Route source priority is documented.
- `routeMissingReason` recommendation is documented.
- GPX import v1 scope and validation rules are documented.
- Strava OAuth feasibility constraints and non-goals are documented.
- Supabase/local storage implications are documented.

## JAFOM: 0002 Backup/Rollback Checklist

Goal:

- Create a JAFOM backup and rollback checklist using known facts while preserving the JAFOM 0001 access blocker.

Verification:

- Review known hosting and project metadata without deploying.
- Record missing authenticated session/admin credentials and Vercel project access as assumptions or blockers.
- Identify database, storage, environment, and rollback ownership questions.
- Confirm which parts of rollback planning cannot be completed until access is available.

Expected outcome:

- A rollback checklist exists, or the remaining access gaps are explicit enough to unblock once credentials/access are available.

Completion criteria:

- Production and staging targets are recorded where known.
- Hosting provider rollback method is documented or explicitly blocked by missing Vercel access.
- Database, storage, and environment variable backup responsibilities are identified or listed as access-blocked.
- Rollback authority and approval path are defined.
- A release rollback checklist exists and can be executed without guessing project details, or the remaining guesses are isolated.

## Instagram: 0002 Harness/Hermes Automation Planning

Goal:

- Plan Harness/Hermes automation for the SOOM Instagram Dashboard, or use this slot to unblock static review evidence if external browser/deployment access becomes available.

Verification:

- Review the Instagram 0001 blocked verification state.
- Define Harness/Hermes inputs, outputs, owners, review cadence, and handoff format.
- Keep missing external browser review, screenshots, console capture, production URL, deployment ID, and deployed commit as explicit blockers.
- Keep persistent backend/storage assumptions separate from static review automation.

Expected outcome:

- A practical automation plan exists, or the static external review blocker is removed with concrete browser/deployment evidence.

Completion criteria:

- Automation goals are defined separately for Harness and Hermes.
- Inputs, outputs, owners, and review cadence are documented.
- Static dashboard review feedback flow is incorporated.
- Persistent backend/storage assumptions are explicitly separated from automation planning.
- Follow-up implementation tasks are created if automation work is approved.
