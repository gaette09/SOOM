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
| 1 | SOOM | 0009 Record Detail Content Lock | `tasks/soom/0009-record-detail-content-lock.md` | Active |
| 2 | JAFOM | 0001 External Production Stability Check | `tasks/jafom/0001-external-production-staging-stability-check.md` | Active |
| 3 | Instagram | 0001 Static Dashboard External Review | `tasks/instagram/0001-static-dashboard-external-review.md` | Active |

## SOOM: 0009 Record Detail Content Lock

Goal:

- Lock SOOM Record Detail content behavior based on the Strava Frame Lock direction so the screen is ready for focused QA and the TestFlight QA checklist.

Verification:

- Compare Record Detail behavior against the Strava Frame Lock direction.
- Run focused simulator review for the affected Record Detail path.
- Run any relevant build check if implementation code is changed.
- Capture screenshots, notes, changed file list, build output, or no-build rationale.

Expected outcome:

- Record detail content behavior is locked against the Strava-inspired frame direction and ready for focused QA.

Completion criteria:

- Intended Record Detail content structure is documented or implemented.
- Behavior is checked against the Strava Frame Lock direction.
- Verification evidence is recorded.
- Remaining gaps are converted into follow-up tasks.
- No unrelated app code changes are included.

## JAFOM: 0001 External Production Stability Check

Goal:

- Confirm JAFOM external production and staging stability, including availability, key workflow health, and current deploy state.

Verification:

- Identify the JAFOM project root.
- Confirm repository and branch with `pwd`, `git remote -v`, `git status --short`, and `git branch --show-current`.
- Open production and staging targets.
- Smoke test key workflows.
- Record URLs checked, timestamp, workflow results, errors, and deployment IDs or commit SHAs if available.

Expected outcome:

- Production and staging availability, key workflows, and deploy state are confirmed or documented as blocked.

Completion criteria:

- Production and staging targets are identified.
- Key workflows are smoke tested.
- Current deploy state is recorded.
- Any outage, broken workflow, or missing access is documented as a blocker.
- The backup/rollback checklist can start with concrete target information.

## Instagram: 0001 Static Dashboard External Review

Goal:

- Prepare and verify the SOOM Instagram Dashboard static review path so the dashboard can be reviewed externally with clear scope, access, and feedback expectations.

Verification:

- Identify the dashboard project root or static review target.
- If a project root is available, confirm repository and branch with `pwd`, `git remote -v`, `git status --short`, and `git branch --show-current`.
- Open the static dashboard review target.
- Verify visible content, links, responsive layout, and review instructions.
- Capture review URL or file path, screenshots if useful, feedback items, and unresolved access or rendering issues.

Expected outcome:

- Static dashboard can be reviewed externally with clear access path, scope, and review criteria.

Completion criteria:

- Static review target is accessible externally or the access blocker is documented.
- Dashboard content and layout are verified for review.
- Feedback collection path is defined.
- Backend/storage design remains explicitly out of scope for the static review.
- Follow-up items are added for Harness/Hermes automation planning and persistent storage design.
