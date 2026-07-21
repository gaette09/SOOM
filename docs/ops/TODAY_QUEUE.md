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
| P0 | SOOM | Collect sample FIT files | `docs/reports/soom-fit-import-planning.md` | Gather representative cycling FIT files from Garmin/Wahoo/Bryton/iGPSPORT/Magene/Coospo/Chinese cycling computers when available |
| P0 | SOOM | FIT parser feasibility spike | `docs/reports/soom-fit-import-planning.md` | Choose parser strategy and validate route + summary extraction against sample cycling FIT files |
| P1 | SOOM | GPX Import v1 physical-device QA | `docs/reports/soom-gpx-import-v1-activity-detail-entry.md` | Validate GPX route attachment from Activity Detail on device, including imported cycling workout with missing HealthKit route |
| P1 | SOOM | FIT route attach design | `docs/reports/soom-fit-import-planning.md` | Design FIT route attachment to existing HealthKit imported workouts with matching and duplicate guardrails |
| P2 | SOOM | TCX import planning | `docs/reports/soom-tcx-import-planning.md` | Plan complete; next gate is pure TCX parser foundation with synthetic fixtures only |
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

## SOOM: FIT Import Planning

Goal:

- Plan SOOM FIT import before implementation, with sample-file collection and parser feasibility as the immediate next work.

Verification:

- Collect cycling FIT samples before adding parser code.
- Validate parser strategy against real device/app files.
- Treat FIT as activity-original and especially important for cycling computers.
- Plan both FIT route attachment and full workout import.
- Keep TCX as a later fallback.
- Keep Strava/Wahoo/Garmin and other provider work behind user-controlled file import.

Expected outcome:

- A documented FIT import plan exists, with implementation phases, mapping rules, sample-file requirements, and dependency/security review criteria.

Completion criteria:

- Sample FIT collection is P0.
- FIT parser feasibility is P0.
- GPX Import v1 physical-device QA remains P1.
- FIT route attach design is P1.
- TCX planning is complete; TCX parser implementation and Strava/Wahoo feasibility remain separately gated P2 work.
- No FIT implementation begins until sample files and parser strategy are documented.

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
