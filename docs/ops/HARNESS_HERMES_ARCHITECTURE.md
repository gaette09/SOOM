# Harness/Hermes Architecture

## Purpose

This document defines how Harness and Hermes would integrate into the current SOOM, JAFOM, and SOOM Instagram Dashboard operating system.

The goal is not to install new tooling yet. The goal is to define clear responsibilities, memory boundaries, and rollout steps so automation can be added without disrupting the current docs-first workflow.

## 1. Current System

The current operating system is Markdown-driven and repository-centered.

Core files:

- `docs/ops/MULTI_PROJECT_OPERATIONS.md`
- `docs/ops/PROJECT_GOALS.md`
- `docs/ops/TODAY_QUEUE.md`
- `tasks/soom/*.md`
- `tasks/jafom/*.md`
- `tasks/instagram/*.md`
- `docs/reports/*.md`

Current flow:

1. `PROJECT_GOALS.md` defines Active, Next, and Blocked goals for each project.
2. Each goal maps to a task file.
3. `TODAY_QUEUE.md` selects the active parallel work queue.
4. Codex reads the relevant docs and task files.
5. Codex executes inspection, implementation, or reporting work inside the correct project context.
6. Evidence is written into report files.
7. Commits happen only when explicitly requested.

Project contexts:

| Project | Current root | Primary target |
| --- | --- | --- |
| SOOM | `/Volumes/Platinum1TB/SOOM` | TestFlight |
| JAFOM | `/Volumes/Platinum1TB/UserData/Documents/블로그` | Vercel CRM |
| SOOM Instagram Dashboard | `/Users/jihwanchung/Documents/Marketing/SOOM_Instagram` | Vercel static dashboard |

Current strengths:

- Durable written state.
- Clear separation between projects.
- Explicit no-deploy and no-commit constraints.
- Task files preserve intent and acceptance criteria.
- Reports preserve findings and next actions.

Current gaps:

- Project roots and deployment facts can drift from older docs.
- Today Queue execution is manual.
- Report freshness is manual.
- No automatic reminder when Active tasks remain incomplete.
- No structured memory layer separates stable facts from daily status.

## 2. Harness Responsibilities

Harness should be the execution and verification layer.

Primary responsibilities:

- Read the active queue.
- Resolve each task to:
  - project root
  - task file
  - required docs
  - expected checks
  - report file
- Confirm the correct project root before running commands.
- Run non-destructive inspection commands.
- Collect evidence.
- Produce or update task reports.
- Refuse deploy, install, or commit actions unless explicitly authorized.

Harness should own:

- Task execution checklists.
- Validation command templates.
- Evidence collection.
- Status transition proposals.
- Report generation structure.

Harness should not own:

- Product decisions.
- Priority decisions.
- Secrets.
- Deployment approval.
- Git commits unless explicitly requested.

Harness input:

```text
docs/ops/TODAY_QUEUE.md
tasks/<project>/<task>.md
docs/ops/PROJECT_GOALS.md
docs/ops/MULTI_PROJECT_OPERATIONS.md
```

Harness output:

```text
docs/reports/<project>-<task-id>-report.md
```

Recommended Harness task state vocabulary:

- `ready`
- `active`
- `waiting`
- `blocked`
- `verified`
- `done`

## 3. Hermes Responsibilities

Hermes should be the communication, handoff, and memory layer.

Primary responsibilities:

- Summarize current status across SOOM, JAFOM, and Instagram.
- Preserve daily handoff state.
- Track blockers and decisions needed.
- Convert report findings into concise operating updates.
- Keep stable project facts separate from daily execution notes.
- Identify cross-project dependencies.

Hermes should own:

- Daily status updates.
- Weekly review summaries.
- Decision logs.
- Blocker summaries.
- Cross-project risk summaries.
- Stable memory updates when roots, repos, deployment targets, or ownership facts change.

Hermes should not own:

- Running validation commands.
- Editing app code.
- Deploying.
- Staging or committing files.

Hermes update format:

```text
Project:
Status:
Today:
Next:
Blocked:
Risk:
Decision needed:
Evidence:
```

Hermes output candidates:

```text
docs/reports/daily-YYYY-MM-DD.md
docs/reports/weekly-YYYY-WW.md
docs/ops/DECISIONS.md
docs/ops/PROJECT_MEMORY.md
```

## 4. Codex Responsibilities

Codex remains the operator and implementation agent.

Primary responsibilities:

- Read the required operating docs before work.
- Execute the user's requested scope.
- Inspect files and current state.
- Modify documentation when requested.
- Modify app code only when explicitly requested or required by an implementation task.
- Run validation when code changes are made.
- Report changed files and residual risks.
- Commit only when explicitly requested.

Codex should enforce:

- correct project root
- no accidental cross-project edits
- no deploy without explicit request
- no install without explicit request
- no app-code changes during docs/report tasks
- no commits unless explicitly requested

Codex should use Harness structure when executing tasks and Hermes structure when summarizing state.

## 5. Goal System Integration

`PROJECT_GOALS.md` is the stable goal index.

Harness integration:

- Parse Active, Next, and Blocked rows.
- Confirm every goal maps to a task file.
- Warn if a task file is missing.
- Propose task status updates based on reports.

Hermes integration:

- Convert goal rows into daily/weekly status.
- Highlight which Active goals are stale.
- Highlight when Next goals are ready to start.
- Highlight Blocked goals that need decisions or access.

Required goal mapping fields:

```text
Project
Goal type: Active | Next | Blocked
Goal name
Task file
Expected outcome
Priority
Owner/tool
Deployment target
Verification method
Definition of Done
```

Goal update rule:

- Goals should change only after report evidence exists or the user explicitly changes priority.

## 6. Task System Integration

Task files are the executable work units.

Current task folders:

```text
tasks/soom
tasks/jafom
tasks/instagram
```

Harness task execution should require:

- goal
- current status
- acceptance criteria
- verification method
- blockers
- priority

Recommended task additions over time:

- project root
- repository
- report file
- allowed commands
- forbidden actions
- evidence checklist
- completion state

Harness should treat each task file as immutable intent during execution unless the user asks to update the task.

Report linkage:

| Task | Report |
| --- | --- |
| `tasks/soom/0009-record-detail-content-lock.md` | `docs/reports/soom-0009-report.md` |
| `tasks/jafom/0001-external-production-staging-stability-check.md` | `docs/reports/jafom-0001-report.md` |
| `tasks/instagram/0001-static-dashboard-external-review.md` | `docs/reports/instagram-0001-report.md` |

## 7. Today Queue Integration

`TODAY_QUEUE.md` is the daily execution queue.

Harness should use it to determine:

- which tasks are active
- execution order
- task file path
- expected verification
- completion criteria

Hermes should use it to determine:

- daily status scope
- which projects need updates
- which active tasks lack reports
- which blockers need escalation

Codex should use it to determine:

- what to read first
- what not to touch
- what reports to create or update

Recommended Today Queue lifecycle:

1. Start day: refresh queue from `PROJECT_GOALS.md`.
2. Execute: Harness runs or guides active task inspections.
3. Report: update `docs/reports`.
4. Handoff: Hermes summarizes status.
5. End day: queue remains as evidence of what was attempted.

## 8. Memory Architecture

Memory should be split into stable facts, task state, daily state, and evidence.

### Stable Project Memory

Stable facts should live in an ops memory file, not only in chat.

Recommended file:

```text
docs/ops/PROJECT_MEMORY.md
```

Suggested fields:

```text
Project:
Local root:
GitHub:
Default branch:
Deployment target:
Production URL:
Staging URL:
Primary commands:
Secret locations:
Rollback method:
Last verified:
```

Initial stable facts to capture:

| Project | Root | GitHub | Deployment |
| --- | --- | --- | --- |
| SOOM | `/Volumes/Platinum1TB/SOOM` | `https://github.com/gaette09/SOOM` | TestFlight target |
| JAFOM | `/Volumes/Platinum1TB/UserData/Documents/블로그` | `https://github.com/gaette09/jafom-offline-crm` | Vercel deployed, login verified |
| Instagram | `/Users/jihwanchung/Documents/Marketing/SOOM_Instagram` | `https://github.com/gaette09/soom-instagram-dashboard` | Vercel static dashboard |

### Task Memory

Task memory lives in:

```text
tasks/<project>/<task-id>.md
```

This should describe what the task means and how to verify it.

### Daily Memory

Daily memory lives in:

```text
docs/ops/TODAY_QUEUE.md
docs/reports/daily-YYYY-MM-DD.md
```

This should describe what is active today and what happened.

### Evidence Memory

Evidence memory lives in:

```text
docs/reports/<project>-<task-id>-report.md
```

This should include current state, findings, blockers, next action, commands run, and validation evidence.

## 9. Automation Opportunities

Low-risk automation:

- Generate `TODAY_QUEUE.md` from Active goals.
- Verify every goal maps to an existing task file.
- Verify every Active task has a report.
- Check that project roots exist.
- Check `git status --short` for each project.
- Check Git remotes match project memory.
- Generate daily Hermes summary from reports.

Medium-risk automation:

- Run read-only smoke commands per project.
- Run local build/lint checks when explicitly requested.
- Capture browser screenshots for static dashboard review.
- Pull Vercel deployment metadata when credentials are available.
- Update report templates with command outputs.

High-risk automation:

- Deploying.
- Modifying production environment variables.
- Running database migrations.
- Uploading TestFlight builds.
- Changing Supabase policies or data.
- Committing across multiple repositories.

Automation should start read-only and report-only.

## 10. Risks

### Stale Memory

Risk:

- Older docs may say a project root is unknown while newer user-provided facts identify it.

Mitigation:

- Add `PROJECT_MEMORY.md` and make it the stable source for roots, repos, and deployments.
- Include `Last verified`.

### Cross-Project Contamination

Risk:

- Commands or commits run from the wrong root.

Mitigation:

- Harness must run `pwd`, `git remote -v`, and `git status --short` before project work.
- Reports must include root and remote.

### False Completion

Risk:

- A task is marked done because inspection happened, even though verification did not.

Mitigation:

- Separate `inspected`, `verified`, and `done`.
- Require evidence for `verified`.

### Secret Exposure

Risk:

- Reports accidentally include `.env.local`, API keys, Supabase service role keys, or account credentials.

Mitigation:

- Never paste secret values.
- Record only secret location and owner.

### Over-Automation

Risk:

- Harness starts deploying or mutating production before the operating model is stable.

Mitigation:

- Automation phases must start read-only.
- Deploy, install, migration, and commit actions require explicit user request.

### Report Drift

Risk:

- Reports become stale and no longer reflect the current deployed state.

Mitigation:

- Reports should include date, root, branch, remote, and evidence status.
- Hermes should flag reports older than the current operating day.

## 11. Recommended Rollout Plan

### Phase 1: Memory Consolidation

Create:

```text
docs/ops/PROJECT_MEMORY.md
```

Capture stable facts for:

- SOOM
- JAFOM
- SOOM Instagram Dashboard

Do not automate yet.

### Phase 2: Report Templates

Standardize report format:

```text
Current State
Findings
Blockers
Next Action
Evidence
```

Apply this to active task reports.

### Phase 3: Harness Dry Run

Create a read-only Harness checklist that:

- reads `TODAY_QUEUE.md`
- verifies task files exist
- verifies roots/remotes
- updates no files unless explicitly requested
- produces a report of what would run

### Phase 4: Hermes Daily Summary

Create a daily Hermes summary from:

- `TODAY_QUEUE.md`
- active task reports
- blockers
- decisions needed

Suggested file:

```text
docs/reports/daily-YYYY-MM-DD.md
```

### Phase 5: Read-Only Automation

Automate safe checks:

- root exists
- Git remote matches memory
- worktree status
- active report exists
- Vercel URL is recorded
- deployment ID is recorded

### Phase 6: Explicit Validation Automation

Only after read-only automation is reliable:

- run local lint/build when requested
- run browser review when requested
- collect screenshots when requested

### Phase 7: Controlled Deployment Hooks

Only after rollback plans exist:

- TestFlight upload support for SOOM
- Vercel deploy metadata collection for JAFOM
- Vercel static dashboard deploy metadata for Instagram

Deployment execution must remain explicit and user-approved.
