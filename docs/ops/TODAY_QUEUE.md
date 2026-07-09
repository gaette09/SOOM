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
| P0 | SOOM | GPX Import v1 physical-device QA | `docs/reports/soom-gpx-import-v1-activity-detail-entry.md` | Validate GPX route attachment from Activity Detail on device, including imported cycling workout with missing HealthKit route |
| P0 | SOOM | FIT import planning | `docs/reports/soom-file-import-format-roadmap.md` | Plan cycling-first FIT support for route attachment and full workout import before implementation |
| P1 | SOOM | FIT parser feasibility | `docs/reports/soom-file-import-format-roadmap.md` | Choose parser strategy and validate sample cycling computer FIT files |
| P1 | SOOM | FIT route attach/full workout import design | `docs/reports/soom-file-import-format-roadmap.md` | Define route-only attachment, full workout import, duplicate guardrails, storage metadata, and deferred sampled streams |
| P2 | SOOM | TCX import planning | `docs/reports/soom-file-import-format-roadmap.md` | Plan TCX as a fallback richer than GPX but secondary to cycling FIT |
| P2 | SOOM | Strava/Wahoo feasibility | `docs/reports/soom-external-route-provider-matrix.md` | OAuth/API research only after file import priorities are clear; no scraping/login automation |
| P2 | SOOM | Garmin/Komoot/RideWithGPS/TrainingPeaks/Decathlon provider research | `docs/reports/soom-external-route-provider-matrix.md` | Research only after file import and first OAuth feasibility spikes are understood |
| 2 | JAFOM | 0002 Backup/Rollback Checklist | `tasks/jafom/0002-backup-rollback-checklist.md` | Recommended only if JAFOM 0001 access blocker remains |
| 3 | Instagram | 0002 Harness/Hermes Automation Planning | `tasks/instagram/0002-harness-hermes-automation-planning.md` | Recommended, or replace with static review unblock if external browser/deployment access is available |

## Verification Results From Previous Active Queue

| Project | Verified task | Task file | Result | Evidence |
| --- | --- | --- | --- | --- |
| SOOM | 0009 Record Detail Content Lock | `tasks/soom/0009-record-detail-content-lock.md` | PASS | `docs/reports/soom-0009-verification.md` |
| JAFOM | 0001 External Production Stability Check | `tasks/jafom/0001-external-production-staging-stability-check.md` | BLOCKED | `docs/reports/jafom-0001-verification.md` |
| Instagram | 0001 Static Dashboard External Review | `tasks/instagram/0001-static-dashboard-external-review.md` | BLOCKED | External project report: `/Users/jihwanchung/Documents/Marketing/SOOM_Instagram/docs/reports/instagram-0001-verification.md` |

## SOOM: File Import Roadmap

Goal:

- Prioritize SOOM file import work after GPX Import v1 implementation, with FIT as the next cycling-first format.

Verification:

- Run GPX Import v1 physical-device QA before expanding the importer surface.
- Treat GPX as route-first attachment.
- Treat FIT as activity-original and especially important for cycling computers.
- Plan FIT route attachment and full workout import before implementation.
- Keep TCX as a later fallback.
- Keep Strava/Wahoo/Garmin and other provider work behind user-controlled file import.

Expected outcome:

- A documented format roadmap exists, with GPX, FIT, and TCX roles clearly separated and FIT prioritized for cycling.

Completion criteria:

- GPX route attachment remains the active device QA task.
- FIT planning is P0.
- FIT parser feasibility and route/full workout import design are P1.
- TCX planning and Strava/Wahoo feasibility are P2.
- No implementation begins until FIT parser/import scope is documented.

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
