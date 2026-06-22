# Harness Phase 1 Implementation Plan

## Purpose

Define the Phase 1 Harness proof of concept without installing Harness, modifying app code, deploying, or committing.

Phase 1 goal:

- Add a read-only local Harness layer that can inspect the current multi-project queue.
- Validate that Active goals, Today Queue entries, and task files agree.
- Confirm project roots, Git remotes, branches, and worktree status before execution.
- Produce a dry-run checklist for SOOM, JAFOM, and Instagram without mutating app code or deployment state.

## Scope

Included:

- Installation plan.
- Recommended repo location.
- Integration points with `docs/ops/PROJECT_GOALS.md`.
- Integration points with `docs/ops/TODAY_QUEUE.md`.
- Integration points with `tasks/`.
- Read-only execution architecture.
- Rollback plan.
- Setup time estimate.

Excluded:

- Installing Harness.
- Installing Hermes.
- Creating automation scripts.
- Modifying app code.
- Running builds.
- Running deploys.
- Running commits.

## 1. Exact Install Steps

These steps are the proposed later install procedure. Do not run them until the user explicitly approves Phase 1 installation.

### Step 1: Confirm Current State

Run from the SOOM repository root:

```sh
cd /Volumes/Platinum1TB/SOOM
git status --short
git log --oneline -5
test -f docs/ops/PROJECT_GOALS.md
test -f docs/ops/TODAY_QUEUE.md
test -f docs/ops/PROJECT_MEMORY.md
test -d tasks/soom
test -d tasks/jafom
test -d tasks/instagram
```

Expected result:

- Worktree state is known before any install.
- Required ops files exist.
- Required task folders exist.

### Step 2: Choose Harness Repo Location

Recommended location:

```text
/Volumes/Platinum1TB/SOOM/tools/harness-poc
```

Reason:

- Keeps Phase 1 close to the operating docs it reads.
- Keeps Harness versioned with the SOOM ops repository if later committed.
- Avoids writing into JAFOM or Instagram app repositories.
- Keeps all Phase 1 work inside the current writable workspace.

Alternative location:

```text
/Volumes/Platinum1TB/SOOM/.agents/harness-poc
```

Use only if the POC should stay agent-local and not become normal project documentation or tooling.

### Step 3: Create Harness POC Directory

Proposed later command:

```sh
mkdir -p /Volumes/Platinum1TB/SOOM/tools/harness-poc
```

Initial planned structure:

```text
tools/harness-poc/
  README.md
  harness.config.json
  checks/
    queue-map.md
    root-checks.md
    report-checks.md
  output/
    .gitkeep
```

Phase 1 should start with Markdown check definitions before any executable script is added.

### Step 4: Add Read-Only Harness Config

Proposed config path:

```text
tools/harness-poc/harness.config.json
```

Planned contents:

```json
{
  "mode": "read-only",
  "allowWrites": false,
  "allowDeploys": false,
  "allowInstalls": false,
  "allowCommits": false,
  "sources": {
    "projectGoals": "docs/ops/PROJECT_GOALS.md",
    "todayQueue": "docs/ops/TODAY_QUEUE.md",
    "projectMemory": "docs/ops/PROJECT_MEMORY.md",
    "tasksRoot": "tasks",
    "reportsRoot": "docs/reports"
  },
  "projects": {
    "soom": {
      "root": "/Volumes/Platinum1TB/SOOM",
      "expectedRemote": "https://github.com/gaette09/SOOM.git",
      "expectedBranch": "main"
    },
    "jafom": {
      "root": "/Volumes/Platinum1TB/UserData/Documents/블로그",
      "expectedRemote": "https://github.com/gaette09/jafom-offline-crm.git",
      "expectedBranch": "master"
    },
    "instagram": {
      "root": "/Users/jihwanchung/Documents/Marketing/SOOM_Instagram",
      "expectedRemote": "https://github.com/gaette09/soom-instagram-dashboard.git",
      "expectedBranch": "main"
    }
  }
}
```

No secrets should be stored in Harness config.

### Step 5: Run Manual Dry-Run Checklist

Before any script exists, Phase 1 should manually verify:

```sh
cd /Volumes/Platinum1TB/SOOM
git status --short
sed -n '1,220p' docs/ops/PROJECT_GOALS.md
sed -n '1,220p' docs/ops/TODAY_QUEUE.md
find tasks -maxdepth 2 -type f | sort
find docs/reports -maxdepth 1 -type f | sort
```

Then run per-project read-only checks:

```sh
cd /Volumes/Platinum1TB/SOOM
pwd
git remote -v
git branch --show-current
git status --short
```

```sh
cd /Volumes/Platinum1TB/UserData/Documents/블로그
pwd
git remote -v
git branch --show-current
git status --short
```

```sh
cd /Users/jihwanchung/Documents/Marketing/SOOM_Instagram
pwd
git remote -v
git branch --show-current
git status --short
```

Expected result:

- Harness can prove it is looking at the correct roots.
- Harness can detect dirty worktrees before task execution.
- Harness can report missing or stale evidence without changing files.

### Step 6: Optional Later Scripted Checker

Only after the manual checklist is accepted, add a local read-only checker.

Proposed command:

```sh
node tools/harness-poc/check-queue.mjs
```

Allowed behavior:

- Read Markdown and JSON files.
- List Active tasks.
- Confirm task files exist.
- Confirm report files exist.
- Confirm roots, remotes, branches, and worktree state.
- Print a summary to stdout.

Forbidden behavior:

- Modify files.
- Install dependencies.
- Run builds.
- Run deploys.
- Create commits.
- Read or print secrets.

## 2. Mac Mini Requirements

Already present from Phase 0 audit:

| Requirement | Status |
| --- | --- |
| macOS host | Present: `jihwanui-Macmini.local` |
| SOOM workspace | Present: `/Volumes/Platinum1TB/SOOM` |
| Git | Present: `/opt/homebrew/bin/git`, version `2.47.1` |
| Node | Present: `/opt/homebrew/bin/node`, version `v23.11.0` |
| npm | Present: `/opt/homebrew/bin/npm`, version `10.9.2` |
| Xcodebuild | Present for SOOM build context, not required for Phase 1 |
| Fastlane | Present for SOOM release context, not required for Phase 1 |

Phase 1 requirements:

- Read access to all three project roots.
- Write access only to the selected Harness POC location if installation is approved later.
- No network access required for the manual Phase 1 dry run.
- No package installation required for the manual Phase 1 dry run.
- No Vercel, App Store Connect, Supabase, or GitHub authentication required for the first read-only checklist.

Recommended safety constraints:

- Run Harness from `/Volumes/Platinum1TB/SOOM`.
- Treat `docs/ops/PROJECT_MEMORY.md` as the stable project fact source.
- Treat `docs/ops/TODAY_QUEUE.md` as the daily execution queue.
- Treat `tasks/` as the task contract source.
- Treat `docs/reports/` as evidence output from prior task execution.

## 3. Integration Architecture

### Current Sources

Harness reads:

| Source | Role |
| --- | --- |
| `docs/ops/PROJECT_MEMORY.md` | Stable project roots, repositories, deployment targets, blockers, and last verified state |
| `docs/ops/PROJECT_GOALS.md` | Active, Next, and Blocked goal hierarchy |
| `docs/ops/TODAY_QUEUE.md` | Current active parallel queue |
| `tasks/<project>/*.md` | Task-level acceptance criteria, verification method, blockers, and priority |
| `docs/reports/*.md` | Existing task findings and evidence |

Harness does not read:

- Secrets.
- Local credential stores.
- Production databases.
- Deployment dashboards unless explicitly approved in a later phase.

### PROJECT_GOALS Integration

Harness checks:

- Every Active goal has a mapped task file.
- Every Next goal has a mapped task file.
- Every Blocked goal has a mapped task file or an explicit no-blocked-goal placeholder.
- Active goal names match the current project memory where applicable.
- Priority order is present and readable.

Expected Phase 1 output:

```text
PROJECT_GOALS check:
- SOOM Active -> tasks/soom/0009-record-detail-content-lock.md
- JAFOM Active -> tasks/jafom/0001-external-production-staging-stability-check.md
- Instagram Active -> tasks/instagram/0001-static-dashboard-external-review.md
- Missing mappings: none
- Warnings: list stale or ambiguous entries
```

### TODAY_QUEUE Integration

Harness checks:

- Today Queue contains one Active task per project unless intentionally changed.
- Each queue entry maps to a task file.
- Each queue entry maps to a report file.
- Queue priority order is explicit.
- Queue entries do not require deploy, install, commit, or app-code mutation unless explicitly marked.

Expected Phase 1 output:

```text
TODAY_QUEUE check:
- SOOM 0009 -> task exists -> report exists
- JAFOM 0001 -> task exists -> report exists
- Instagram 0001 -> task exists -> report exists
- Unsafe requested actions: none
```

### TASKS Integration

Harness checks each Active task for required sections:

- goal
- current status
- acceptance criteria
- verification method
- blockers
- priority

Harness also checks:

- Task number continuity within each project.
- Task file naming consistency.
- Whether each task has a matching report when Active.
- Whether blockers are reflected in `PROJECT_MEMORY.md` or reports.

Expected Phase 1 output:

```text
TASKS check:
- tasks/soom/0009-record-detail-content-lock.md -> required sections present
- tasks/jafom/0001-external-production-staging-stability-check.md -> required sections present
- tasks/instagram/0001-static-dashboard-external-review.md -> required sections present
- Missing required sections: none
```

### Reports Integration

Harness checks:

- Active task report exists.
- Report includes current state, findings, blockers, and next action.
- Report date is compatible with the current operating day or explicitly marked historical.
- Report conclusions do not contradict known project memory.

Expected Phase 1 output:

```text
REPORTS check:
- docs/reports/soom-0009-report.md -> present
- docs/reports/jafom-0001-report.md -> present
- docs/reports/instagram-0001-report.md -> present
- Stale reports: list if any
```

### Execution Boundary

Harness Phase 1 is a guardrail and checklist layer.

Allowed:

- Read files.
- Run Git status checks.
- Run branch checks.
- Run remote checks.
- Produce dry-run summaries.

Not allowed:

- Modify app code.
- Modify docs unless explicitly requested.
- Install packages.
- Deploy.
- Commit.
- Push.
- Run destructive commands.

## 4. Expected Benefits

Immediate benefits:

- Reduces wrong-root risk across SOOM, JAFOM, and Instagram.
- Makes Active task execution safer before Codex begins inspection work.
- Catches missing task/report mappings.
- Catches stale reports before daily summaries.
- Separates queue validation from product judgment.

Operational benefits:

- Faster daily start because queue readiness can be checked first.
- Cleaner handoff between Codex sessions.
- Better evidence discipline for Active tasks.
- Better signal on whether a task is inspected, blocked, verified, or done.

Benefits Harness should not claim in Phase 1:

- It does not prove production stability.
- It does not validate UI behavior.
- It does not resolve signing, deployment, or backend blockers.
- It does not replace manual approval for commits or deploys.

## 5. Rollback Steps

If Phase 1 installation is later approved and needs to be rolled back:

### Rollback Option A: Remove Only Harness POC Files

If Harness is placed at `tools/harness-poc`:

```sh
cd /Volumes/Platinum1TB/SOOM
git status --short
git restore --staged tools/harness-poc
rm -rf tools/harness-poc
git status --short
```

Use only before commit.

### Rollback Option B: Revert Committed Harness POC

If Harness POC was committed:

```sh
cd /Volumes/Platinum1TB/SOOM
git log --oneline -5
git revert <harness-phase-1-commit-sha>
git status --short
```

Use when the POC commit should be undone while preserving history.

### Rollback Option C: Disable Without Deleting

If the files should remain for reference:

- Rename `tools/harness-poc/harness.config.json` to `tools/harness-poc/harness.config.disabled.json`.
- Add a note to `tools/harness-poc/README.md` that Phase 1 is disabled.
- Do not run the checker.

### Rollback Verification

After rollback:

- `docs/ops/PROJECT_GOALS.md` remains unchanged.
- `docs/ops/TODAY_QUEUE.md` remains unchanged.
- `docs/ops/PROJECT_MEMORY.md` remains unchanged.
- `tasks/` remains unchanged.
- App code remains unchanged.
- No deploy state changed.

## 6. Estimated Setup Time

| Work item | Estimate |
| --- | --- |
| Review Phase 0/roadmap and confirm requirements | 30 minutes |
| Create Harness POC directory and README | 15 minutes |
| Create read-only config | 30 minutes |
| Write manual queue/root/report checklist | 45 minutes |
| Run manual dry run across all three projects | 45-90 minutes |
| Review findings and decide whether to script | 30 minutes |

Total manual Phase 1 POC:

```text
3-4 hours
```

Optional scripted checker after manual acceptance:

```text
1-2 days
```

## Phase 1 Success Criteria

Phase 1 is successful when:

- Harness has a documented install location and read-only operating boundary.
- Harness can list all Active tasks from `docs/ops/TODAY_QUEUE.md`.
- Harness can map Active tasks to `tasks/` files.
- Harness can map Active tasks to `docs/reports/` files.
- Harness can confirm project root, Git remote, branch, and worktree status for all three projects.
- Harness identifies missing or stale evidence without modifying files.
- Harness performs no install, deploy, app-code mutation, or commit.

## Recommended Next Action

Do not install Harness yet.

Next executable step:

- Run the Phase 1 manual dry-run checklist once and record the output in a report, such as:

```text
docs/reports/harness-phase1-dry-run-report.md
```

Only after that report is reviewed should the team decide whether to create a scripted checker under `tools/harness-poc`.
