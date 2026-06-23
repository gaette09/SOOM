# Portfolio Status

Date: 2026-06-23

## Summary

| Project | Status | Evidence | Notes |
| --- | --- | --- | --- |
| SOOM | 0009 PASS; 0010 QA PASS on simulator; TestFlight QA pending | `docs/reports/soom-0009-verification.md`, `docs/reports/soom-0010-qa-pass1.md` | Record Detail content lock passed. Critical-path simulator validation passed for build 3 logic, but physical TestFlight build 3 GPS/share QA remains pending. |
| JAFOM | 0001 BLOCKED | `docs/reports/jafom-0001-verification.md` | Public unauthenticated checks passed; authenticated smoke checks and Vercel deployment metadata remain blocked. |
| Instagram | 0001 BLOCKED | `docs/reports/instagram-0001-report.md` | Static dashboard output is coherent, but external Vercel URL review, deployment metadata, screenshots, and feedback path are missing. |
| Harness | Phase 1 PASS | `docs/ops/HARNESS_PHASE2_AUTOMATION_PLAN.md` | Read-only Harness POC is installed at `tools/harness-poc`; current validation result is recorded as PASS. |

## Current Queue

| Priority | Project | Current task | Task file | Status |
| --- | --- | --- | --- | --- |
| 1 | SOOM | Complete TestFlight QA for build 3 on physical device | `tasks/soom/0010-testflight-qa-checklist.md` | Pending physical TestFlight execution |
| 2 | JAFOM | Resume external production/staging stability check when access is available | `tasks/jafom/0001-external-production-staging-stability-check.md` | Blocked |
| 3 | Instagram | Run external static dashboard review or unblock required evidence | `tasks/instagram/0001-static-dashboard-external-review.md` | Blocked |
| 4 | Harness | Move from Phase 1 validation to Phase 2 daily automation planning | `docs/ops/HARNESS_PHASE2_AUTOMATION_PLAN.md` | Ready for explicit implementation request |

## Blockers

| Project | Blocker | Impact |
| --- | --- | --- |
| SOOM | TestFlight build 3 has not been verified on a physical iPhone. Local `build/SOOM.ipa` reports build 2 while the simulator Debug build reports build 3. | Release gate cannot pass; GPS route capture, physical route persistence, and native share sheet remain unverified. |
| SOOM | Physical-device GPS and TestFlight install path are unavailable in the current workspace. | Record, route persistence, and share can only be marked simulator/logic-pass, not release-pass. |
| JAFOM | Missing authenticated browser session/admin credentials. | Dashboard, customers, repairs, workboard, settings, status logs, and Supabase health cannot be verified post-login. |
| JAFOM | Missing Vercel project access. | Deployment ID, deployed commit, staging/preview URL, and rollback metadata cannot be confirmed. |
| Instagram | Exact Vercel URL, deployment ID, deployed commit, desktop/mobile browser evidence, and feedback path are missing. | External static review cannot pass. |
| Harness | Phase 2 automation is planned but not implemented. | Daily report generation, drift checks, freshness checks, and deployment-readiness hooks remain manual. |

## Next Actions

| Project | Next action |
| --- | --- |
| SOOM | Install TestFlight build 3 on a physical iPhone and rerun the D1 critical path: launch, navigation, Record with GPS, save route, reopen route-backed detail, force quit/relaunch, and native share sheet. |
| SOOM | Confirm whether `build/SOOM.ipa` is stale or unrelated to TestFlight build 3; archive/upload/signing state should be reconciled before release-gate QA. |
| JAFOM | Provide authenticated session/admin credentials and Vercel access, then resume 0001 with screenshots, console capture, deployment ID, deployed commit, and staging/preview metadata. |
| Instagram | Record the deployed Vercel URL and run desktop/mobile external review without deploying; capture broken assets, console state, generated image behavior, preview modal behavior, and feedback path. |
| Harness | Implement Phase 2 only after explicit approval: daily report generator, queue freshness check, goal/task drift check, and read-only deployment metadata hooks. |

## Recommended Priority

1. SOOM TestFlight physical QA: highest priority because SOOM has the strongest current pass evidence, and the remaining blocker is specific and release-gating.
2. JAFOM access unblock: next priority because production is reachable but core authenticated verification and deployment metadata cannot progress without credentials/Vercel access.
3. Instagram external review unblock: third priority because static build evidence exists, but external deployment evidence and review artifacts are still missing.
4. Harness Phase 2 automation: useful after the above blockers are either resolved or explicitly accepted, so automation reflects the real operating state instead of stale gaps.

## Operating Decision

Do not deploy.

Do not modify app code.

Keep SOOM active until physical TestFlight QA is either completed or formally blocked with owner/date. Keep JAFOM and Instagram in blocked/evidence-gathering mode until access and external review targets are available.
