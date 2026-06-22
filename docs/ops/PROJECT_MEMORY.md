# Project Memory

Purpose: single source of truth for current SOOM, JAFOM, and SOOM Instagram Dashboard project facts.

Last updated: 2026-06-22

## SOOM

| Field | Value |
| --- | --- |
| Local path | `/Volumes/Platinum1TB/SOOM` |
| GitHub | `https://github.com/gaette09/SOOM` |
| Primary branch | `main` |
| TestFlight status | Target known, not yet verified as TestFlight-ready. Fastlane archive/upload readiness is still blocked by signing/provisioning/account verification. |
| Current active goal | Record Detail Content Lock based on Strava Frame Lock |
| Current task | `tasks/soom/0009-record-detail-content-lock.md` |
| Last verified | 2026-06-22 |

## JAFOM

| Field | Value |
| --- | --- |
| Local path | `/Volumes/Platinum1TB/UserData/Documents/블로그` |
| GitHub | `https://github.com/gaette09/jafom-offline-crm` |
| Primary branch | `master` |
| Vercel URL | Not recorded yet |
| Deployment status | Vercel deployed and login verified |
| Current active goal | External production/staging stability check |
| Current task | `tasks/jafom/0001-external-production-staging-stability-check.md` |
| Last verified | 2026-06-22 |

## Instagram

| Field | Value |
| --- | --- |
| Local path | `/Users/jihwanchung/Documents/Marketing/SOOM_Instagram` |
| GitHub | `https://github.com/gaette09/soom-instagram-dashboard` |
| Primary branch | `main` |
| Vercel URL | Not recorded yet |
| Deployment status | Vercel deployed as static dashboard |
| Current active goal | Static dashboard external review |
| Current task | `tasks/instagram/0001-static-dashboard-external-review.md` |
| Last verified | 2026-06-22 |

## Deployment Inventory

| Project | Target | Current status | Verification source |
| --- | --- | --- | --- |
| SOOM | App Store Connect / TestFlight | Build target exists, but archive/upload readiness remains blocked by signing/provisioning/account verification. | Local Xcode/Fastlane inspection and SOOM task reports |
| JAFOM | Vercel | Deployed; login verified. Exact production URL and deployment ID still need to be recorded. | User-provided project facts and JAFOM task report |
| Instagram | Vercel static dashboard | Deployed as static dashboard. Exact production URL and deployment ID still need to be recorded. | User-provided project facts and Instagram task report |

## Access Inventory

| Project | Local access | GitHub access | Deployment access | Notes |
| --- | --- | --- | --- | --- |
| SOOM | Available in current workspace | Repository known | App Store Connect/TestFlight access required for release verification | Fastlane lane exists; signing/account state requires follow-up. |
| JAFOM | External local path known | Repository known | Vercel deployment exists and login has been verified | Exact Vercel URL should be added before the next stability pass. |
| Instagram | External local path known | Repository known | Vercel static deployment exists | Exact Vercel URL should be added before the next external review pass. |

## Known Blockers

| Project | Blocker | Impact | Current next action |
| --- | --- | --- | --- |
| SOOM | Record Detail production content lock has not yet been verified against the Strava Frame Lock behavior. | Active product goal cannot be closed. | Inspect current Record Detail behavior and produce implementation/QA recommendation without changing code. |
| SOOM | Fastlane archive signing issue investigation remains blocked. | TestFlight release flow is not fully executable. | Confirm signing identity, provisioning profile, Apple account state, and archive/export settings. |
| JAFOM | Exact Vercel production URL, deployment ID, deployed SHA, and route smoke results are not recorded. | Stability check cannot be considered fully evidence-backed. | Record deployment metadata and run route/auth smoke checks. |
| Instagram | Exact Vercel production URL, deployment ID, and external desktop/mobile review results are not recorded. | External static dashboard review is incomplete. | Record deployment metadata and run desktop/mobile external review. |
| Instagram | Persistent backend/storage is not yet designed. | Automation and long-term dashboard state are limited to static output. | Define storage requirements before backend implementation. |

## Recent Major Decisions

| Date | Decision | Rationale |
| --- | --- | --- |
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
