# Project Goals

## Purpose

This document tracks active goals for SOOM, JAFOM, and the SOOM Instagram Dashboard.

Use it with `docs/ops/MULTI_PROJECT_OPERATIONS.md` to keep daily work, blocked goals, deployment targets, and verification expectations explicit across all active projects.

## 1. Current Operating Status

| Project | Status | Current note |
| --- | --- | --- |
| SOOM | Active | Product implementation and release-readiness work are both active. Current focus is Record Detail Content Lock based on the Strava Frame Lock direction. |
| JAFOM | Active | External production/staging stability needs verification before deeper release or rollback planning. |
| SOOM Instagram Dashboard | Active | Static dashboard is ready for external review, but persistent backend/storage remains undesigned. |

## 2. Active Goal

| Project | Active Goal | Expected outcome |
| --- | --- | --- |
| SOOM | Record Detail Content Lock based on Strava Frame Lock | Record detail content behavior is locked against the Strava-inspired frame direction and ready for focused QA. |
| JAFOM | External production/staging stability check | Production and staging availability, key workflows, and deploy state are confirmed or documented as blocked. |
| SOOM Instagram Dashboard | Static dashboard external review | Static dashboard can be reviewed externally with clear access path, scope, and review criteria. |

## 3. Next Goal

| Project | Next Goal | Trigger to start |
| --- | --- | --- |
| SOOM | TestFlight QA checklist | Start after Record Detail Content Lock has a documented implementation state and verification method. |
| JAFOM | Backup/rollback checklist | Start after external production/staging stability is confirmed or specific gaps are documented. |
| SOOM Instagram Dashboard | Harness/Hermes automation planning | Start after static dashboard review path and feedback loop are confirmed. |

## 4. Blocked Goal

| Project | Blocked Goal | Blocker | Unblock condition |
| --- | --- | --- | --- |
| SOOM | Fastlane archive signing issue investigation | Apple signing, provisioning, or account/session state needs focused investigation. | Confirm signing inputs, reproduce the archive failure, and document the exact remediation path. |
| JAFOM | None | No blocked goal currently tracked. | Add one when a concrete blocker is identified. |
| SOOM Instagram Dashboard | Persistent backend/storage not yet designed | Storage model, backend runtime, authentication, and persistence boundaries are not defined. | Produce a backend/storage design with ownership, hosting, data model, and rollback implications. |

## 5. Priority

Initial priority order:

1. SOOM: Record Detail Content Lock based on Strava Frame Lock.
2. JAFOM: External production/staging stability check.
3. SOOM Instagram Dashboard: Static dashboard external review.
4. SOOM: TestFlight QA checklist.
5. JAFOM: Backup/rollback checklist.
6. SOOM Instagram Dashboard: Harness/Hermes automation planning.
7. SOOM: Fastlane archive signing issue investigation.
8. SOOM Instagram Dashboard: Persistent backend/storage design.

Priority rationale:

- SOOM content locking is the most concrete active product task and unblocks focused QA.
- JAFOM stability verification reduces operational uncertainty before rollback planning.
- Instagram Dashboard external review is executable while backend/storage design remains separate.
- Fastlane signing is blocked until the signing/account state can be investigated directly.

## 6. Owner/Tool

| Project | Primary owner/tool | Supporting tools | Notes |
| --- | --- | --- | --- |
| SOOM | Codex for implementation and documentation tasks | Xcode, Simulator, Fastlane, GitHub, TestFlight | Use Codex from `/Volumes/Platinum1TB/SOOM`; do not mix release signing work with unrelated UI changes. |
| JAFOM | Harness for stability checklist execution | Codex, GitHub, hosting dashboard, browser smoke tests | Identify exact project root, repository, and deploy target before deeper work. |
| SOOM Instagram Dashboard | Hermes for review coordination | Harness, Codex, browser review, static hosting or share target | Keep review scope separate from backend/storage design. |

## 7. Deployment Target

| Project | Deployment target | Current target state | Release rule |
| --- | --- | --- | --- |
| SOOM | TestFlight | Known target, but signing/archive path has a blocked investigation item. | Do not upload until archive signing and QA checklist are verified. |
| JAFOM | Production/staging web URL | Target exists conceptually, exact hosting state must be checked. | Do not deploy until current production/staging state and rollback path are known. |
| SOOM Instagram Dashboard | Static external review target | Static review is active; persistent backend/storage is not designed. | Do not introduce persistent backend or storage during static review work. |

## 8. Verification Method

| Project | Active Goal verification | Evidence to capture |
| --- | --- | --- |
| SOOM | Compare Record Detail behavior against the Strava Frame Lock direction; run focused simulator review and any relevant build check for touched code. | Screenshots or notes from simulator review, changed file list, build or no-build rationale, unresolved gaps. |
| JAFOM | Open production and staging targets, test key workflows, confirm deploy metadata, and document any failures. | URLs checked, timestamp, workflow results, errors, deployment IDs or commit SHAs if available. |
| SOOM Instagram Dashboard | Open the static dashboard review target, verify visible content, links, responsive layout, and review instructions. | Review URL or file path, screenshots if useful, feedback items, unresolved access or rendering issues. |

## 9. Definition of Done

### SOOM: Record Detail Content Lock

Done when:

- The intended Record Detail content structure is documented or implemented.
- Behavior is checked against the Strava Frame Lock direction.
- Verification evidence is recorded.
- Any remaining gaps are converted into follow-up tasks.
- No unrelated app code changes are included.

### JAFOM: External Production/Staging Stability Check

Done when:

- Production and staging targets are identified.
- Key workflows are smoke tested.
- Current deploy state is recorded.
- Any outage, broken workflow, or missing access is documented as a blocker.
- The backup/rollback checklist can start with concrete target information.

### SOOM Instagram Dashboard: Static Dashboard External Review

Done when:

- Static review target is accessible externally or the access blocker is documented.
- Dashboard content and layout are verified for review.
- Feedback collection path is defined.
- Backend/storage design remains explicitly out of scope for the static review.
- Follow-up items are added for Harness/Hermes automation planning and persistent storage design.

## Recommended First Executable Task

Start with SOOM:

```text
Create or update a focused task for Record Detail Content Lock based on Strava Frame Lock, including exact screens/files to inspect, acceptance criteria, simulator verification steps, and a no-deploy/no-commit constraint unless explicitly changed.
```

Reason:

- It is the highest-priority active goal.
- It has the clearest implementation and verification path.
- It unblocks the TestFlight QA checklist more directly than the currently blocked Fastlane signing investigation.
