# Harness/Hermes Phase 0 Audit

Date: 2026-06-22

## Purpose

Execute Phase 0 from `docs/ops/HARNESS_HERMES_ROADMAP.md`: audit the current operating system before installing or building Harness/Hermes.

No Harness or Hermes tooling was installed. No app code was modified. No commits were made.

## 1. Current Mac Mini Environment

Observed environment:

```text
Host: jihwanui-Macmini.local
User: jihwanchung
OS: macOS 26.5.1
Kernel: Darwin 25.5.0 arm64
Date: 2026-06-22 14:17 KST
Primary SOOM root: /Volumes/Platinum1TB/SOOM
```

Available tools:

| Tool | Observed version/path | Current use |
| --- | --- | --- |
| Git | `/opt/homebrew/bin/git`, `2.47.1` | Source control and repo state checks |
| Xcodebuild | `/usr/bin/xcodebuild`, Xcode `26.5` | SOOM iOS builds |
| Node | `/opt/homebrew/bin/node`, `v23.11.0` | Web tooling |
| npm | `/opt/homebrew/bin/npm`, `10.9.2` | JAFOM and Instagram scripts |
| Fastlane | `/opt/homebrew/bin/fastlane`, `2.236.0` | SOOM archive path |

Current Mac mini capabilities:

- Can host multiple local project roots.
- Can run iOS build tooling.
- Can run Node/npm-based web projects.
- Can inspect Git state across SOOM, JAFOM, and Instagram.
- Can support docs-first multi-project operations without new installs.

Environment gaps:

- No single stable project memory file currently owns roots, repos, deployment URLs, and last-verified state.
- Deployment URLs and deployment IDs are not consistently recorded in ops docs.
- Older docs still contain unknown placeholders for JAFOM and Instagram even though newer facts are known.

## 2. Current Codex Environment

Current Codex behavior:

- Reads operating docs and task files before work when instructed.
- Executes shell inspections from specific project roots.
- Creates and updates Markdown documentation.
- Uses `git status --short`, `git remote -v`, and branch checks for repo context.
- Commits only when explicitly requested.
- Does not deploy unless explicitly requested.
- Does not install tools unless explicitly requested.

Current Codex constraints:

- App code can be avoided when the user scopes work to docs/reports.
- Multi-project work depends on explicit local paths and careful root selection.
- Cross-project status is manual and report-driven.

Current Codex worktree state in SOOM:

```text
?? docs/ops/HARNESS_HERMES_ARCHITECTURE.md
?? docs/ops/HARNESS_HERMES_ROADMAP.md
?? docs/ops/TODAY_QUEUE.md
?? docs/reports/
```

Codex environment gaps:

- No automatic stale-report detection.
- No automatic check that every Active task has current evidence.
- No durable memory file separating stable facts from daily queue state.
- No automatic guardrail that validates all project roots before a parallel task run.

## 3. Existing Task System

Current task folders:

```text
tasks/soom
tasks/jafom
tasks/instagram
```

Current task files:

```text
tasks/soom/0005-feed-home-v1.md
tasks/soom/0006-record-detail-v1.md
tasks/soom/0007-record-detail-map-sheet-rework.md
tasks/soom/0008-strava-detail-clone-prototype.md
tasks/soom/0009-record-detail-content-lock.md
tasks/soom/0010-testflight-qa-checklist.md
tasks/soom/0011-fastlane-archive-signing-issue-investigation.md
tasks/jafom/0001-external-production-staging-stability-check.md
tasks/jafom/0002-backup-rollback-checklist.md
tasks/jafom/0003-no-blocked-goal.md
tasks/instagram/0001-static-dashboard-external-review.md
tasks/instagram/0002-harness-hermes-automation-planning.md
tasks/instagram/0003-persistent-backend-storage-design.md
```

Task system strengths:

- Tasks are separated by project.
- Numbering continuity exists.
- Active, Next, and Blocked queues are represented.
- Task files include goal, status, acceptance criteria, verification method, blockers, and priority.
- README files exist for each project task folder.

Task system gaps:

- Task files do not consistently include project root, GitHub repo, report file path, allowed commands, or forbidden actions.
- Task state is not automatically synchronized with report evidence.
- There is no script or checklist that validates task/report mappings.

## 4. Existing Goal System

Current goal source:

```text
docs/ops/PROJECT_GOALS.md
```

Current Active goals:

| Project | Active goal | Task |
| --- | --- | --- |
| SOOM | Record Detail Content Lock based on Strava Frame Lock | `tasks/soom/0009-record-detail-content-lock.md` |
| JAFOM | External production/staging stability check | `tasks/jafom/0001-external-production-staging-stability-check.md` |
| Instagram | Static dashboard external review | `tasks/instagram/0001-static-dashboard-external-review.md` |

Current Next goals:

| Project | Next goal | Task |
| --- | --- | --- |
| SOOM | TestFlight QA checklist | `tasks/soom/0010-testflight-qa-checklist.md` |
| JAFOM | Backup/rollback checklist | `tasks/jafom/0002-backup-rollback-checklist.md` |
| Instagram | Harness/Hermes automation planning | `tasks/instagram/0002-harness-hermes-automation-planning.md` |

Current Blocked goals:

| Project | Blocked goal | Task |
| --- | --- | --- |
| SOOM | Fastlane archive signing issue investigation | `tasks/soom/0011-fastlane-archive-signing-issue-investigation.md` |
| JAFOM | None | `tasks/jafom/0003-no-blocked-goal.md` |
| Instagram | Persistent backend/storage not yet designed | `tasks/instagram/0003-persistent-backend-storage-design.md` |

Goal system strengths:

- Active, Next, and Blocked queues are visible.
- Goals map to task files.
- Priority order is explicit.
- Verification method and definition of done exist.

Goal system gaps:

- Goal status does not automatically change after a report is produced.
- Priority ordering is manual.
- Stable project roots are not embedded in the goal rows.
- Older deployment docs can conflict with newer known facts.

## 5. Existing Deployment System

Current deployment docs:

- `docs/ops/PROJECT_DEPLOYMENT_STATUS.md`
- `docs/ops/MULTI_PROJECT_OPERATIONS.md`
- `docs/reports/jafom-0001-report.md`
- `docs/reports/instagram-0001-report.md`

Current known deployment facts:

| Project | Deployment target | Current state |
| --- | --- | --- |
| SOOM | TestFlight | Target known; archive/signing investigation remains blocked |
| JAFOM | Vercel CRM | Deployed and login verified |
| Instagram | Vercel static dashboard | Deployed as static dashboard |

Observed project roots and repos:

| Project | Root | Branch | GitHub remote |
| --- | --- | --- | --- |
| SOOM | `/Volumes/Platinum1TB/SOOM` | `main` | `https://github.com/gaette09/SOOM.git` |
| JAFOM | `/Volumes/Platinum1TB/UserData/Documents/블로그` | `master` | `https://github.com/gaette09/jafom-offline-crm.git` |
| Instagram | `/Users/jihwanchung/Documents/Marketing/SOOM_Instagram` | `main` | `https://github.com/gaette09/soom-instagram-dashboard.git` |

Deployment system strengths:

- SOOM has documented Fastlane/Xcode context.
- JAFOM has known Vercel deployment and verified login.
- Instagram has known Vercel static dashboard deployment and local `vercel.json`.
- Reports now record current deployment evidence gaps.

Deployment system gaps:

- `PROJECT_DEPLOYMENT_STATUS.md` still contains stale `Unknown` values for JAFOM and Instagram.
- Exact Vercel URLs are not recorded in committed ops docs.
- Vercel deployment IDs are not recorded.
- Rollback methods for JAFOM and Instagram are not fully documented.
- SOOM TestFlight archive/upload readiness remains blocked by signing/account verification.

## 6. Existing Project Inventory

Current inventory:

| Project | Type | Root | Main repo | Primary operations |
| --- | --- | --- | --- | --- |
| SOOM | iOS app | `/Volumes/Platinum1TB/SOOM` | `gaette09/SOOM` | Xcode build, Simulator QA, TestFlight, docs/tasks |
| JAFOM | Next.js/Supabase CRM | `/Volumes/Platinum1TB/UserData/Documents/블로그` | `gaette09/jafom-offline-crm` | Vercel CRM, login, Supabase health, route smoke |
| Instagram | Static dashboard/content ops | `/Users/jihwanchung/Documents/Marketing/SOOM_Instagram` | `gaette09/soom-instagram-dashboard` | Static dashboard build, Vercel review, content assets |

Inventory strengths:

- All three active project roots are known.
- All three GitHub remotes are known.
- Each project has active task/report coverage.

Inventory gaps:

- The authoritative inventory is spread across chat, reports, ops docs, and task files.
- No `PROJECT_MEMORY.md` exists yet.
- Project inventory has not been normalized into one stable table with `Last verified`.

## What Is Already Present

Already present:

- Markdown-based operating system.
- Goal hierarchy.
- Task hierarchy.
- Today Queue.
- Per-task reports for the active queue.
- Multi-project operating rules.
- Basic deployment status documentation.
- Git repositories for all three projects.
- Local roots for all three projects.
- Build/runtime tools on the Mac mini.
- Clear human approval boundaries for deploy, install, and commit.

Already functioning without Harness/Hermes:

- Codex can inspect and update docs.
- Codex can execute read-only task inspections.
- Codex can create reports.
- User can request scoped commits.
- Project separation can be maintained manually.

## What Harness Would Replace

Harness would replace or reduce manual execution work:

- Manually reading `TODAY_QUEUE.md` to list Active tasks.
- Manually checking task/report mappings.
- Manually running root, remote, branch, and worktree checks.
- Manually confirming report files exist.
- Manually creating repetitive inspection checklists.
- Manually detecting missing evidence fields.

Harness would not replace:

- Product judgment.
- Priority setting.
- Deployment approval.
- Secret handling.
- Git commits.
- Codex implementation work.

Harness would become:

- the read-only execution checklist layer,
- the task evidence collector,
- the stale/missing report detector,
- the preflight guard against wrong-root work.

## What Hermes Would Replace

Hermes would replace or reduce manual coordination work:

- Manually summarizing daily status from multiple reports.
- Manually tracking blockers across projects.
- Manually remembering stable roots, repos, deployments, and last verified dates.
- Manually identifying which Next goal is ready to promote.
- Manually producing weekly review summaries.

Hermes would not replace:

- User decisions.
- Deployment execution.
- Validation execution.
- Code changes.
- Secure secret storage.

Hermes would become:

- the stable project memory layer,
- the daily/weekly handoff layer,
- the blocker and decision summary layer,
- the cross-project risk tracker.

## What New Capabilities Would Be Added

New Harness capabilities:

- Active queue validation.
- Task/report mapping validation.
- Project-root verification.
- Cross-project worktree status check.
- Read-only evidence checklist generation.
- Missing report detection.
- Stale report detection.

New Hermes capabilities:

- Stable project memory with `Last verified`.
- Daily multi-project status summaries.
- Weekly multi-project review summaries.
- Decision log.
- Cross-project blocker tracking.
- Promotion readiness signals for Next goals.

New combined capabilities:

- Safer multi-project parallel execution.
- Less reliance on chat memory.
- Better distinction between inspected, verified, blocked, and done.
- Faster handoff after interrupted work.
- Clearer deploy readiness versus deploy approval.

## Phase 0 Result

Phase 0 status:

- Complete for audit purposes.

Phase 0 conclusion:

- The current system is strong enough to support Harness/Hermes later without installing anything now.
- The most important next step is not automation. It is consolidating stable project memory into `docs/ops/PROJECT_MEMORY.md`.
- Harness should begin as read-only queue validation.
- Hermes should begin as stable memory plus daily summary generation.
- No app-code, deployment, install, or commit capability should be added in the first rollout.
