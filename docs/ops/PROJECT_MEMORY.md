# Project Memory

Purpose: single source of truth for current SOOM, JAFOM, and SOOM Instagram Dashboard project facts.

Last updated: 2026-06-23

## SOOM

| Field | Value |
| --- | --- |
| Local path | `/Volumes/Platinum1TB/SOOM` |
| GitHub | `https://github.com/gaette09/SOOM` |
| Primary branch | `main` |
| TestFlight status | Target known, not yet verified as TestFlight-ready. Fastlane archive/upload readiness is still blocked by signing/provisioning/account verification. |
| Current active goal | TestFlight QA checklist |
| Current task | `tasks/soom/0010-testflight-qa-checklist.md` |
| Last verified | 2026-06-23: SOOM 0009 PASS in `docs/reports/soom-0009-verification.md` |

## JAFOM

| Field | Value |
| --- | --- |
| Local path | `/Volumes/Platinum1TB/UserData/Documents/블로그` |
| GitHub | `https://github.com/gaette09/jafom-offline-crm` |
| Primary branch | `master` |
| Vercel URL | `https://jafom-offline-crm.vercel.app` production URL identified; staging/preview URL not identified |
| Deployment status | Public unauthenticated production checks passed; authenticated smoke checks and Vercel metadata are blocked |
| Current active goal | Backup/rollback checklist only if access blocker remains |
| Current task | `tasks/jafom/0002-backup-rollback-checklist.md` |
| Last verified | 2026-06-23: JAFOM 0001 BLOCKED in `docs/reports/jafom-0001-verification.md` |

## Instagram

| Field | Value |
| --- | --- |
| Local path | `/Users/jihwanchung/Documents/Marketing/SOOM_Instagram` |
| GitHub | `https://github.com/gaette09/soom-instagram-dashboard` |
| Primary branch | `main` |
| Vercel URL | Not recorded yet |
| Deployment status | Static build passes; external browser review, screenshots, console capture, deployment ID, and deployed commit are blocked/missing |
| Current active goal | Harness/Hermes automation planning or static review unblock |
| Current task | `tasks/instagram/0002-harness-hermes-automation-planning.md` |
| Last verified | 2026-06-23: Instagram 0001 BLOCKED in external report `/Users/jihwanchung/Documents/Marketing/SOOM_Instagram/docs/reports/instagram-0001-verification.md` |

## Deployment Inventory

| Project | Target | Current status | Verification source |
| --- | --- | --- | --- |
| SOOM | App Store Connect / TestFlight | SOOM 0009 passed simulator/build verification; TestFlight readiness still needs QA checklist and signing/upload clarity. | `docs/reports/soom-0009-verification.md` |
| JAFOM | Vercel | Production URL identified and public unauthenticated checks passed; authenticated smoke checks, staging/preview, deployment ID, and deployed SHA are blocked by missing access. | `docs/reports/jafom-0001-verification.md` |
| Instagram | Vercel static dashboard | Static build/output verified; external review URL, screenshots, console capture, deployment ID, and deployed SHA are missing. | External Instagram verification report |

## Access Inventory

| Project | Local access | GitHub access | Deployment access | Notes |
| --- | --- | --- | --- | --- |
| SOOM | Available in current workspace | Repository known | App Store Connect/TestFlight access required for release verification | Fastlane lane exists; signing/account state requires follow-up. |
| JAFOM | External local path known | Repository known | Missing Vercel project access and authenticated browser/admin access | Backup/rollback planning can proceed only with explicit access gaps until JAFOM 0001 is unblocked. |
| Instagram | External local path known | Repository known | Missing production URL/deployment metadata and browser capture path | Harness/Hermes planning can proceed only if static review evidence gaps remain explicit. |

## Known Blockers

| Project | Blocker | Impact | Current next action |
| --- | --- | --- | --- |
| SOOM | Fastlane archive signing issue investigation remains blocked. | TestFlight release flow is not fully executable. | Confirm signing identity, provisioning profile, Apple account state, and archive/export settings. |
| JAFOM | Missing authenticated session/admin credentials and Vercel project access. | JAFOM 0001 cannot pass authenticated smoke checks or record deployment/staging metadata. | Proceed to JAFOM 0002 only as an access-limited backup/rollback checklist, or resume JAFOM 0001 when access is available. |
| Instagram | Missing external browser review, screenshot/console capture, production URL, deployment ID, and deployed SHA. | Instagram 0001 cannot pass external review readiness. | Proceed to Instagram 0002 automation planning only if it explicitly tracks static review unblock requirements. |
| Instagram | Persistent backend/storage is not yet designed. | Automation and long-term dashboard state are limited to static output. | Define storage requirements before backend implementation. |

## Recent Major Decisions

| Date | Decision | Rationale |
| --- | --- | --- |
| 2026-06-23 | Move recommended active queue after verification: SOOM 0010, JAFOM 0002 only if access blocker remains, Instagram 0002 or static review unblock. | SOOM 0009 passed, while JAFOM 0001 and Instagram 0001 are blocked by external access/evidence gaps. |
| 2026-06-22 | Use docs and task files as the operating system for SOOM, JAFOM, and Instagram. | Keeps multi-project work explicit, reviewable, and commit-friendly without requiring new tooling first. |
| 2026-06-22 | Treat `docs/ops/PROJECT_GOALS.md` as the goal map and `tasks/` as the executable task queue. | Separates project-level priorities from task-level acceptance criteria and verification. |
| 2026-06-22 | Maintain `docs/ops/TODAY_QUEUE.md` as the daily active work queue. | Defines the parallel work set for the current operating day. |
| 2026-06-22 | Defer Harness and Hermes installation. | Phase 0 audit found the current Codex/docs/task system is usable now; Harness/Hermes should be introduced later through read-only proof of concept work. |
| 2026-06-22 | Use this file as the stable memory layer before automation. | Harness/Hermes integration needs a durable project fact source before queue automation or memory synchronization. |

## Related Files

- `docs/ops/MULTI_PROJECT_OPERATIONS.md`
- `docs/ops/PROJECT_GOALS.md`
- `docs/ops/TODAY_QUEUE.md`
- `docs/ops/HARNESS_HERMES_ARCHITECTURE.md`
- `docs/ops/HARNESS_HERMES_ROADMAP.md`
- `docs/ops/HARNESS_HERMES_PHASE0_AUDIT.md`
- `tasks/soom/`
- `tasks/jafom/`
- `tasks/instagram/`
