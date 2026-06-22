# Harness/Hermes Roadmap

## Purpose

This document turns `docs/ops/HARNESS_HERMES_ARCHITECTURE.md` into an executable rollout plan.

The rollout starts with documentation and dry-run behavior only. No install, deployment, app-code modification, or automatic commit behavior is part of this roadmap until explicitly approved in a later phase.

## Phase 0: Current State

### Objective

Document and stabilize the current Markdown-based operating system before adding automation.

Current system:

- `docs/ops/MULTI_PROJECT_OPERATIONS.md` defines multi-project operating rules.
- `docs/ops/PROJECT_GOALS.md` tracks Active, Next, and Blocked goals.
- `docs/ops/TODAY_QUEUE.md` defines the active parallel queue.
- `tasks/<project>/*.md` defines executable task intent.
- `docs/reports/*.md` records execution evidence, findings, blockers, and next actions.
- Codex performs inspection, documentation, implementation, validation, and commits only when explicitly requested.

### Prerequisites

- Keep all existing ops docs available.
- Keep task files mapped from `PROJECT_GOALS.md`.
- Keep report files tied to active task IDs.
- Confirm no automation has deploy, install, or commit authority.

### Estimated Effort

- 0.5 day for review and cleanup.

### Risks

- Older docs may still contain stale project roots or unknown deployment values.
- Reports may drift from current deployment state.
- Active tasks may be interpreted as complete after inspection only.

### Success Criteria

- Current active queue is readable in one file.
- Every Active goal maps to a task file.
- Every Active task has a report file.
- Reports distinguish inspected, blocked, verified, and done.
- No app code is changed while stabilizing the operating docs.

## Phase 1: Harness Proof Of Concept

### Objective

Create a read-only Harness proof of concept that can execute the daily queue as an inspection workflow.

Harness POC behavior:

- Read `docs/ops/TODAY_QUEUE.md`.
- Resolve each active task to its task file.
- Confirm each project root.
- Confirm Git remote and branch.
- Confirm worktree status.
- Check that the expected report file exists.
- Produce a dry-run checklist or report update.
- Refuse deploy, install, mutation, and commit actions.

### Prerequisites

- Phase 0 success criteria are met.
- Stable project roots are captured in a memory file or equivalent source:
  - SOOM: `/Volumes/Platinum1TB/SOOM`
  - JAFOM: `/Volumes/Platinum1TB/UserData/Documents/블로그`
  - Instagram: `/Users/jihwanchung/Documents/Marketing/SOOM_Instagram`
- Each task file has at least:
  - goal
  - current status
  - acceptance criteria
  - verification method
  - blockers
  - priority

### Estimated Effort

- 0.5-1 day for a manual dry run.
- 1-2 days for a scripted read-only checker, if later approved.

### Risks

- Harness may report false confidence if it checks only file existence.
- Root detection may be wrong if paths move.
- A dry-run report can become stale if not regenerated.

### Success Criteria

- Harness can list all active tasks from `TODAY_QUEUE.md`.
- Harness can confirm root, remote, branch, and worktree status for all three projects.
- Harness can identify missing reports or stale evidence.
- Harness produces no app-code changes.
- Harness performs no deploy, install, or commit.

## Phase 2: Hermes Memory Integration

### Objective

Add a memory layer that separates stable project facts from daily execution notes.

Hermes memory should preserve:

- project roots
- GitHub repositories
- default branches
- deployment targets
- production/staging URLs when known
- primary validation commands
- rollback methods
- last verified dates
- open blockers
- decisions needed

Recommended file:

```text
docs/ops/PROJECT_MEMORY.md
```

Optional future files:

```text
docs/ops/DECISIONS.md
docs/reports/daily-YYYY-MM-DD.md
docs/reports/weekly-YYYY-WW.md
```

### Prerequisites

- Phase 1 has a repeatable read-only queue inspection flow.
- Current project roots and remotes are confirmed.
- Reports use a standard format:
  - Current State
  - Findings
  - Blockers
  - Next Action
  - Evidence

### Estimated Effort

- 0.5 day to create initial memory files.
- 1 day to backfill stable facts and decision log.

### Risks

- Memory can become another stale source if it is not treated as authoritative.
- Sensitive data could leak if secrets are copied into memory files.
- Daily status may be confused with stable facts.

### Success Criteria

- `PROJECT_MEMORY.md` exists and records stable facts for SOOM, JAFOM, and Instagram.
- Secret values are not stored.
- Each project includes `Last verified`.
- Daily reports refer to stable memory instead of repeating or guessing roots.
- Hermes summaries can be generated from memory plus reports.

## Phase 3: Task Queue Automation

### Objective

Automate safe queue maintenance and evidence checks without changing app code or deployment state.

Automation targets:

- Generate or refresh `TODAY_QUEUE.md` from Active goals.
- Verify every Active, Next, and Blocked goal maps to an existing task file.
- Verify every Active task has a report file.
- Flag reports missing current state, findings, blockers, or next action.
- Flag reports older than the current operating day.
- Flag project memory entries without `Last verified`.

### Prerequisites

- Phase 2 memory is in place.
- Task files use consistent naming and numbering.
- Report files use consistent section headings.
- The user approves any script creation before implementation.

### Estimated Effort

- 1 day for a manual checklist version.
- 2-3 days for a local script-based checker, if later approved.

### Risks

- Generated queues may overwrite intentional manual ordering.
- Automation may incorrectly mark tasks stale or complete.
- Scripts may create noisy diffs if formatting is unstable.

### Success Criteria

- Queue validation can run read-only.
- Missing task/report mappings are caught before execution.
- Active queue state is reproducible.
- Manual priority order remains respected.
- Automation writes files only when explicitly requested.

## Phase 4: Multi-Project Orchestration

### Objective

Coordinate SOOM, JAFOM, and Instagram work in parallel while preserving project separation and safety.

Orchestration capabilities:

- Run per-project read-only status checks.
- Produce one combined daily Hermes summary.
- Track cross-project blockers.
- Identify which Next goal is ready to promote.
- Identify whether any Active task is blocked by missing evidence.
- Prepare release or rollback checklists without executing them.

Allowed by default:

- root checks
- Git status checks
- report freshness checks
- task/report mapping checks
- daily summary generation

Requires explicit approval:

- installs
- builds
- simulator runs
- browser automation
- deploys
- database actions
- commits

### Prerequisites

- Phase 3 queue automation is reliable.
- Stable memory includes production/staging URLs where available.
- Each project has a rollback checklist or a documented gap.
- Active task reports include enough evidence for Hermes summaries.

### Estimated Effort

- 2-3 days for manual orchestration templates.
- 1 week for safe scripted orchestration, if later approved.

### Risks

- Parallel work can hide project-specific blockers.
- Git commands can run from the wrong project root.
- Deploy readiness can be mistaken for deploy approval.
- Cross-project reports can get too broad to be actionable.

### Success Criteria

- One daily summary covers all three projects.
- Every project status includes current task, blocker, next action, and evidence link.
- Harness can identify missing evidence before Hermes summarizes.
- No project is deployed or committed without explicit user instruction.
- Multi-project work remains traceable through task files and reports.

## Rollout Gate

Do not move from one phase to the next unless:

- the previous phase has written evidence,
- the worktree state is known,
- no app-code changes were introduced accidentally,
- the user explicitly approves the next phase,
- deploy/install/commit behavior remains opt-in.
