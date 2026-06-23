# Project Goals

## Purpose

This document tracks active goals for SOOM, JAFOM, and the SOOM Instagram Dashboard.

Use it with `docs/ops/MULTI_PROJECT_OPERATIONS.md` to keep daily work, blocked goals, deployment targets, and verification expectations explicit across all active projects.

## 1. Current Operating Status

| Project | Status | Current note |
| --- | --- | --- |
| SOOM | Active | SOOM 0009 Record Detail Content Lock passed verification; recommended next active task is TestFlight QA checklist. |
| JAFOM | Blocked | JAFOM 0001 production verification is blocked by missing authenticated session/admin credentials and Vercel project access. |
| SOOM Instagram Dashboard | Blocked | Instagram 0001 static dashboard verification is blocked by missing external browser review, screenshots, console capture, and deployment metadata. |

## 2. Active Goal

| Project | Active Goal | Task file | Expected outcome |
| --- | --- | --- | --- |
| SOOM | TestFlight QA checklist | `tasks/soom/0010-testflight-qa-checklist.md` | QA scope, devices, build/install path, pass/fail criteria, and release blockers are documented. |
| JAFOM | Backup/rollback checklist, access-limited | `tasks/jafom/0002-backup-rollback-checklist.md` | Draft backup and rollback responsibilities from known facts while preserving the JAFOM 0001 access blocker. |
| SOOM Instagram Dashboard | Automation planning or static review unblock | `tasks/instagram/0002-harness-hermes-automation-planning.md` | Plan Harness/Hermes review automation, or first unblock external static review evidence if deployment/browser access becomes available. |

## 3. Next Goal

| Project | Next Goal | Task file | Trigger to start |
| --- | --- | --- | --- |
| SOOM | Fastlane archive signing issue investigation | `tasks/soom/0011-fastlane-archive-signing-issue-investigation.md` | Start after TestFlight QA checklist identifies the build/install path or confirms signing remains the release blocker. |
| JAFOM | External production verification unblock | `tasks/jafom/0001-external-production-staging-stability-check.md` | Resume when authenticated browser session/admin credentials and Vercel project access are available. |
| SOOM Instagram Dashboard | Static dashboard external review unblock | `tasks/instagram/0001-static-dashboard-external-review.md` | Resume when external browser review, screenshot/console capture, and Vercel deployment metadata are available. |

## 4. Blocked Goal

| Project | Blocked Goal | Task file | Blocker | Unblock condition |
| --- | --- | --- | --- | --- |
| SOOM | Fastlane archive signing issue investigation | `tasks/soom/0011-fastlane-archive-signing-issue-investigation.md` | Apple signing, provisioning, or account/session state needs focused investigation. | Confirm signing inputs, reproduce the archive failure, and document the exact remediation path. |
| JAFOM | External production/staging stability check | `tasks/jafom/0001-external-production-staging-stability-check.md` | Missing authenticated session/admin credentials and Vercel project access. | Provide authenticated browser/admin access plus Vercel project access, then verify post-login smoke checks and deployment metadata. |
| SOOM Instagram Dashboard | Static dashboard external review | `tasks/instagram/0001-static-dashboard-external-review.md` | Missing external browser review, screenshots, console/runtime capture, production URL, deployment ID, and deployed commit. | Provide deployed review target and browser capture path, then record desktop/mobile evidence and deployment metadata. |
| SOOM Instagram Dashboard | Persistent backend/storage not yet designed | `tasks/instagram/0003-persistent-backend-storage-design.md` | Storage model, backend runtime, authentication, and persistence boundaries are not defined. | Produce a backend/storage design with ownership, hosting, data model, and rollback implications. |

## 5. Priority

Recommended priority order after active task verification:

1. SOOM: TestFlight QA checklist (`tasks/soom/0010-testflight-qa-checklist.md`).
2. JAFOM: Backup/rollback checklist only if the JAFOM 0001 access blocker remains (`tasks/jafom/0002-backup-rollback-checklist.md`).
3. SOOM Instagram Dashboard: Harness/Hermes automation planning or static review unblock task (`tasks/instagram/0002-harness-hermes-automation-planning.md`).
4. JAFOM: Resume external production/staging stability check when access is available (`tasks/jafom/0001-external-production-staging-stability-check.md`).
5. SOOM Instagram Dashboard: Resume static dashboard external review when external browser/deployment evidence is available (`tasks/instagram/0001-static-dashboard-external-review.md`).
6. SOOM: Fastlane archive signing issue investigation (`tasks/soom/0011-fastlane-archive-signing-issue-investigation.md`).
7. SOOM Instagram Dashboard: Persistent backend/storage design (`tasks/instagram/0003-persistent-backend-storage-design.md`).

Priority rationale:

- SOOM 0009 passed and directly unblocks TestFlight QA checklist work.
- JAFOM stability verification is blocked on access, so backup/rollback planning can proceed only as an access-limited checklist until Vercel/auth access is available.
- Instagram external review is blocked on browser/deployment evidence, so Harness/Hermes planning can proceed only if it explicitly tracks that unblock path and does not assume production readiness.
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
| JAFOM | Production/staging web URL | Production URL is known from verification, but authenticated workflows, staging/preview, deployment ID, and deployed commit are blocked by missing access. | Do not deploy until current production/staging state and rollback path are known. |
| SOOM Instagram Dashboard | Static external review target | Static build passes, but external review URL, deployment ID, deployed commit, screenshots, and console capture are missing. | Do not introduce persistent backend/storage during static review work. |

## 8. Verification Method

| Project | Active Goal verification | Evidence to capture |
| --- | --- | --- |
| SOOM | Run TestFlight QA checklist after SOOM 0009 pass. | Build/install path, device/OS matrix, pass/fail checklist, screenshots if useful, unresolved release blockers. |
| JAFOM | Draft backup/rollback checklist from known facts while preserving the blocked production verification state. | Known production URL, missing Vercel/auth access, backup ownership gaps, rollback assumptions, unblock requirements. |
| SOOM Instagram Dashboard | Plan Harness/Hermes automation or unblock static review evidence. | External review URL/deployment metadata if available, or automation plan with explicit screenshot/console/deployment evidence gaps. |

## 9. Definition of Done

### SOOM: Record Detail Content Lock

Done when:

- The intended Record Detail content structure is documented or implemented.
- Behavior is checked against the Strava Frame Lock direction.
- Verification evidence is recorded.
- Any remaining gaps are converted into follow-up tasks.
- No unrelated app code changes are included.

Current result: PASS for `tasks/soom/0009-record-detail-content-lock.md` in `docs/reports/soom-0009-verification.md`.

### JAFOM: External Production/Staging Stability Check

Done when:

- Production and staging targets are identified.
- Key workflows are smoke tested.
- Current deploy state is recorded.
- Any outage, broken workflow, or missing access is documented as a blocker.
- The backup/rollback checklist can start with concrete target information.

Current result: BLOCKED in `docs/reports/jafom-0001-verification.md`; unauthenticated public checks passed, but authenticated smoke checks and Vercel deployment metadata are blocked by missing access.

### SOOM Instagram Dashboard: Static Dashboard External Review

Done when:

- Static review target is accessible externally or the access blocker is documented.
- Dashboard content and layout are verified for review.
- Feedback collection path is defined.
- Backend/storage design remains explicitly out of scope for the static review.
- Follow-up items are added for Harness/Hermes automation planning and persistent storage design.

Current result: BLOCKED in the Instagram verification report; build/static output passed, but external browser review, screenshots, console capture, and deployment metadata are missing.

## Recommended First Executable Task

Start with SOOM:

```text
Start tasks/soom/0010-testflight-qa-checklist.md.
```

Reason:

- It is the highest-priority active goal.
- SOOM 0009 has passed verification.
- JAFOM and Instagram active verification tasks are blocked on external access/evidence.
