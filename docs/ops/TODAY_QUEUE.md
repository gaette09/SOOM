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
| 1 | SOOM | HealthKit read integration Phase 1 planning | `docs/reports/soom-healthkit-read-phase1-plan.md` | Planning only; keep implementation, TestFlight upload, and build bump deferred |
| 2 | JAFOM | 0002 Backup/Rollback Checklist | `tasks/jafom/0002-backup-rollback-checklist.md` | Recommended only if JAFOM 0001 access blocker remains |
| 3 | Instagram | 0002 Harness/Hermes Automation Planning | `tasks/instagram/0002-harness-hermes-automation-planning.md` | Recommended, or replace with static review unblock if external browser/deployment access is available |

## Verification Results From Previous Active Queue

| Project | Verified task | Task file | Result | Evidence |
| --- | --- | --- | --- | --- |
| SOOM | 0009 Record Detail Content Lock | `tasks/soom/0009-record-detail-content-lock.md` | PASS | `docs/reports/soom-0009-verification.md` |
| JAFOM | 0001 External Production Stability Check | `tasks/jafom/0001-external-production-staging-stability-check.md` | BLOCKED | `docs/reports/jafom-0001-verification.md` |
| Instagram | 0001 Static Dashboard External Review | `tasks/instagram/0001-static-dashboard-external-review.md` | BLOCKED | External project report: `/Users/jihwanchung/Documents/Marketing/SOOM_Instagram/docs/reports/instagram-0001-verification.md` |

## SOOM: HealthKit Read Integration Phase 1 Planning

Goal:

- Plan the first HealthKit read integration pass now that the local `ProcessedWorkout` pipeline is stable enough to receive imported workouts.

Verification:

- Audit current HealthKit, permission, Record save, `UnifiedWorkout`, `ProcessedWorkout`, Activity Detail, Profile, Share, and Recovery preview paths.
- Define conservative read-only HealthKit Phase 1 scope.
- Keep HealthKit write, background sync, Garmin/Samsung/Google integrations, sampled stream persistence, and unrelated UI polish deferred.

Expected outcome:

- A documented HealthKit Read Integration Phase 1 plan exists, with the next implementation step focused on manual, read-only Apple Health workout import into the existing `UnifiedWorkout`/`ProcessedWorkout` path.

Completion criteria:

- Current HealthKit foundation status is documented.
- Initial HealthKit workout, permission, sport, and metric mapping rules are documented.
- Duplicate prevention, local-vs-HealthKit priority, privacy UX, and test strategy are documented.
- Phase 1 implementation phases are documented.
- Explicit deferrals are recorded.

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
