# Multi-Project Operations

## Purpose

This document defines how to operate SOOM, JAFOM, and the SOOM Instagram Dashboard at the same time without mixing code, tasks, deployments, credentials, or release decisions.

Use this runbook when more than one project is active in the same day.

Core rules:

- Keep one terminal, editor window, Codex session, and task context per project.
- Verify the project root before running Git, build, deploy, or rollback commands.
- Treat app code, deployment config, secrets, and generated assets as project-specific.
- Write durable decisions into each project's docs or task files.
- Do not commit or deploy from a dirty worktree unless the dirty files are intentional and reviewed.

## 1. Project Inventory

### SOOM

Type:

- iOS app

Known local location:

```text
/Volumes/Platinum1TB/SOOM
```

Known important paths:

```text
/Volumes/Platinum1TB/SOOM/SOOM.xcodeproj
/Volumes/Platinum1TB/SOOM/SOOM
/Volumes/Platinum1TB/SOOM/SOOMTests
/Volumes/Platinum1TB/SOOM/docs
/Volumes/Platinum1TB/SOOM/docs/ops
/Volumes/Platinum1TB/SOOM/tasks/soom
/Volumes/Platinum1TB/SOOM/fastlane
/Volumes/Platinum1TB/SOOM/supabase
```

Primary operational concerns:

- Local iOS build health
- Simulator QA
- TestFlight readiness
- Apple signing and provisioning
- Supabase environment alignment
- App Store Connect upload path

### JAFOM

Type:

- CRM or web application

Known local location:

```text
Unknown
```

Expected location convention:

```text
/Volumes/Platinum1TB/JAFOM
```

Primary operational concerns:

- Project folder identification
- GitHub remote identification
- Runtime and package manager identification
- Staging and production hosting
- Database and environment variable ownership
- Rollback method

### SOOM Instagram Dashboard

Type:

- Web dashboard or content operations tool

Known local location:

```text
Unknown
```

Expected location convention:

```text
/Volumes/Platinum1TB/SOOM-Instagram-Dashboard
```

Primary operational concerns:

- Project folder identification
- GitHub remote identification
- Runtime and package manager identification
- Asset, export, and generated content paths
- Staging and production hosting
- Authentication and access control
- Rollback method

## 2. GitHub Repositories

Before doing work in any project, confirm the active repository from inside that project's root:

```sh
pwd
git remote -v
git status --short
git branch --show-current
```

Repository inventory:

| Project | Local root | GitHub repository | Default branch | Notes |
| --- | --- | --- | --- | --- |
| SOOM | `/Volumes/Platinum1TB/SOOM` | Confirm with `git remote -v` | Confirm with `git branch --show-current` | Current iOS repository |
| JAFOM | Unknown | Unknown | Unknown | Identify before Codex or deployment work |
| SOOM Instagram Dashboard | Unknown | Unknown | Unknown | Identify before Codex or deployment work |

GitHub operating rules:

- One pull request per project task.
- Never stage files from another project.
- Never reuse a branch name across projects unless the repository name is visible in the terminal prompt.
- Keep docs/spec commits separate from app implementation commits when practical.
- Before opening or updating a PR, run `git status --short` and review the diff.

## 3. Deployment Targets

### SOOM

Primary target:

- TestFlight

Known release path:

- Local Xcode archive
- Fastlane archive lane
- App Store Connect upload path still needs confirmation

Current known command:

```sh
fastlane ios archive
```

Use this only after Apple signing, provisioning, and account access are confirmed.

### JAFOM

Primary target:

- Unknown

Possible targets:

- Vercel
- Netlify
- Cloudflare
- Self-hosted server
- Other

Deployment cannot be treated as repeatable until these are known:

- Hosting provider
- Project ID or site name
- Staging URL
- Production URL
- Deploy command
- Required environment variables
- Rollback method

### SOOM Instagram Dashboard

Primary target:

- Unknown

Possible targets:

- Vercel
- Netlify
- Cloudflare
- Streamlit Community Cloud
- Hugging Face Spaces
- Self-hosted server
- Other

Deployment cannot be treated as repeatable until these are known:

- Hosting provider
- Project ID or site name
- Staging URL
- Production URL
- Deploy command
- Required environment variables
- Asset storage location
- Rollback method

## 4. Access Methods

Use separate access channels for separate purposes:

| Access method | Use for | Rule |
| --- | --- | --- |
| Local terminal | Git, builds, tests, deploy commands | Run from the correct project root only |
| Remote desktop | Simulator, browser QA, screenshots, Xcode UI | Keep the active project visible |
| GitHub | History, PRs, reviews, issue tracking | Confirm repository before acting |
| TestFlight | SOOM iOS distribution | Confirm bundle ID, team, and build number |
| Hosting dashboard | JAFOM and dashboard deploys | Confirm project/site name before changing settings |
| Supabase dashboard | Database, auth, storage, policies | Confirm project/environment before edits |
| Password manager | Secrets and account access | Do not paste secrets into task files or docs |

Minimum access check before operational work:

```sh
pwd
git remote -v
git status --short
```

For web projects, also check:

```sh
ls
```

Then inspect the relevant manifest:

```text
package.json
pnpm-lock.yaml
yarn.lock
package-lock.json
requirements.txt
pyproject.toml
vercel.json
netlify.toml
wrangler.toml
README.md
```

## 5. Codex Workflow

Codex should operate in one project root at a time.

Start every Codex task with:

```text
Project: <SOOM | JAFOM | SOOM Instagram Dashboard>
Root: <absolute path>
Goal: <one concrete outcome>
Constraints:
- Do not modify unrelated files.
- Do not commit unless explicitly requested.
- Do not deploy unless explicitly requested.
```

For SOOM, start from:

```sh
cd /Volumes/Platinum1TB/SOOM
git status --short
```

For JAFOM and SOOM Instagram Dashboard, first identify the root, then run:

```sh
pwd
git remote -v
git status --short
```

Codex rules:

- Ask Codex to inspect relevant docs and task files before implementation.
- Ask Codex to report changed files at the end.
- Ask Codex to run focused validation when code changes are made.
- Keep Codex away from secrets, hosting dashboard settings, and account changes unless explicitly required.
- Use separate Codex sessions for simultaneous projects.

Safe Codex prompt for documentation work:

```text
Create or update only the requested documentation file.
Do not modify app code.
Do not commit.
Report changed files.
```

Safe Codex prompt for implementation work:

```text
Read the relevant docs/task file first.
Implement only this task.
Run focused validation.
Report changed files, validation results, and risks.
Do not commit.
```

## 6. Harness Workflow

Harness is the operational checklist layer for repeatable execution. Use it to keep project context, required checks, and handoff state explicit.

Create or maintain one harness task per project operation:

```text
tasks/<project>/<task-id>-<short-name>.md
```

Recommended folders:

```text
tasks/soom
tasks/jafom
tasks/instagram-dashboard
```

Harness task structure:

- Goal
- Project root
- Repository
- Context links
- Required access
- Required commands
- Acceptance criteria
- Validation evidence
- Deployment decision
- Rollback plan
- Owner and status

Harness rules:

- One harness task should map to one project and one outcome.
- Do not combine SOOM, JAFOM, and Instagram Dashboard changes into one task unless the work is explicitly cross-project coordination.
- Every deploy task must include a rollback plan before deploy starts.
- Every release task must include validation evidence after deploy.
- Completed tasks should link to the PR, release, build, or deployment record.

## 7. Hermes Workflow

Hermes is the communication and handoff layer. Use it to keep daily status, blockers, and decisions clear across projects.

Hermes update format:

```text
Project:
Status:
Today:
Next:
Blocked:
Risk:
Decision needed:
```

Daily Hermes update should include all three projects, even if a project is idle:

```text
SOOM:
JAFOM:
SOOM Instagram Dashboard:
```

Hermes rules:

- State whether a project is active, waiting, blocked, or idle.
- Include exact URLs, PR numbers, build numbers, and deployment IDs when available.
- Do not include secrets.
- Do not bury blockers in long narrative updates.
- Mark cross-project dependencies explicitly.

Example:

```text
Project: SOOM
Status: Active
Today: Verified simulator build and reviewed TestFlight readiness.
Next: Confirm App Store Connect app record and provisioning profile.
Blocked: Apple account/session verification.
Risk: Bundle ID or entitlement mismatch could block archive upload.
Decision needed: Confirm whether app.soom.prototype is the TestFlight bundle ID.
```

## 8. Goal/Task Hierarchy

Use this hierarchy for all three projects:

```text
Portfolio goal
Project goal
Milestone
Task
Subtask
Validation
Release
Review
```

Definitions:

- Portfolio goal: outcome across SOOM, JAFOM, and the Instagram Dashboard.
- Project goal: outcome for one project.
- Milestone: meaningful deliverable or phase.
- Task: unit of work suitable for one PR or one documented operation.
- Subtask: implementation or inspection step.
- Validation: proof that the task works.
- Release: deployment or distribution action.
- Review: post-release or weekly assessment.

Example hierarchy:

```text
Portfolio goal: Operate all products reliably from the Mac mini.
Project goal: Make SOOM TestFlight-ready.
Milestone: Confirm signing and upload path.
Task: Validate archive lane and App Store Connect configuration.
Subtask: Inspect bundle ID, team ID, entitlements, and provisioning.
Validation: Successful archive or documented signing blocker.
Release: Upload to TestFlight.
Review: Confirm install on physical device.
```

## 9. Priority Rules

When projects compete for time, prioritize in this order:

1. Production incident, broken deploy, or user-blocking bug.
2. Release blocker for a scheduled launch or review.
3. Security, privacy, account, or data integrity issue.
4. Work that unblocks another project or person.
5. Small validation task that reduces major uncertainty.
6. Planned feature implementation.
7. Refactor, polish, cleanup, or exploratory work.

Tie-breakers:

- Prefer work with a clear owner, clear acceptance criteria, and clear validation path.
- Prefer finishing an active release checklist over starting a new feature.
- Prefer documentation when the missing information is causing repeated confusion.
- Avoid switching projects while a build, deploy, or rollback is half-finished.

Stop-work triggers:

- Wrong repository or project root is detected.
- Secrets are missing or uncertain.
- Deployment target is ambiguous.
- Rollback path is unknown.
- Git worktree has unexplained changes in files relevant to the task.

## 10. Daily Routine

Start of day:

1. Open one terminal or tmux window per active project.
2. Confirm the root and Git state for each active project.
3. Review yesterday's Hermes update.
4. Choose one primary project and one backup task.
5. Confirm blockers and required access.

SOOM check:

```sh
cd /Volumes/Platinum1TB/SOOM
git status --short
git branch --show-current
```

JAFOM check once root is known:

```sh
cd /Volumes/Platinum1TB/JAFOM
git status --short
git branch --show-current
```

SOOM Instagram Dashboard check once root is known:

```sh
cd /Volumes/Platinum1TB/SOOM-Instagram-Dashboard
git status --short
git branch --show-current
```

During the day:

- Keep one task active per project.
- Record blockers immediately.
- Run validation before switching away from implementation work.
- Do not deploy near the end of a session unless rollback access is confirmed.

End of day:

1. Run `git status --short` in every active project.
2. Save or update task status.
3. Record validation results.
4. Record blockers and decisions needed.
5. Write a Hermes update.
6. Leave each project in a known state.

## 11. Weekly Review

Weekly review should answer:

- What shipped?
- What was validated?
- What remains blocked?
- Which project has the highest operational risk?
- Which project has stale docs or unclear ownership?
- Which deployment path is least repeatable?
- Which tasks should be stopped, split, or deferred?

Review checklist:

1. Review GitHub PRs and open issues for each project.
2. Review deployment status for each project.
3. Review known blockers and access gaps.
4. Review app or site analytics if available.
5. Review task folders for stale or ambiguous tasks.
6. Update project inventory if roots, repos, URLs, or owners changed.
7. Pick next week's primary project priorities.

Weekly output format:

```text
Week of:

SOOM:
- Shipped:
- Validated:
- Blocked:
- Next:

JAFOM:
- Shipped:
- Validated:
- Blocked:
- Next:

SOOM Instagram Dashboard:
- Shipped:
- Validated:
- Blocked:
- Next:

Cross-project risks:
Decisions needed:
```

## 12. Release Checklist

Use this checklist before any TestFlight upload or web deployment.

Pre-release:

1. Confirm project root.
2. Confirm repository and branch.
3. Confirm worktree state.
4. Confirm release scope.
5. Confirm target environment.
6. Confirm required secrets and account access.
7. Confirm rollback method.
8. Confirm owner approval if needed.

Git check:

```sh
pwd
git remote -v
git status --short
git branch --show-current
git log --oneline -6
```

Validation:

- SOOM: run the agreed Xcode build, simulator QA, and archive readiness checks.
- JAFOM: run the agreed lint, test, build, and smoke checks.
- SOOM Instagram Dashboard: run the agreed lint, test, build, data, asset, and export checks.

Release execution:

1. Capture current version, build number, commit SHA, or deployment ID.
2. Run the release command from the correct project root.
3. Watch logs until success or failure is unambiguous.
4. Capture the resulting build number, URL, deployment ID, or release artifact.
5. Smoke test the deployed target.
6. Record the release in the project task or release notes.

Post-release:

- Confirm the released app/site is accessible.
- Confirm key workflows still work.
- Confirm no urgent errors are visible.
- Confirm rollback remains available.
- Send Hermes update with release evidence.

Release evidence format:

```text
Project:
Environment:
Commit:
Version/build:
Deployment URL or TestFlight build:
Validation:
Known risks:
Rollback:
```

## 13. Rollback Checklist

Use rollback when a release breaks core workflows, exposes incorrect data, creates account/security risk, or cannot be fixed quickly.

Before rollback:

1. Confirm the affected project.
2. Confirm the affected environment.
3. Confirm the bad version, commit, build, or deployment ID.
4. Confirm the last known good version.
5. Confirm rollback authority.
6. Notify stakeholders if users are affected.

SOOM rollback options:

- Stop promoting the bad TestFlight build.
- Upload a corrected build with a higher build number.
- Revert the bad commit in Git and archive again.
- Document App Store Connect or TestFlight state after action.

JAFOM rollback options:

- Revert to previous hosting deployment.
- Revert the bad commit and redeploy.
- Disable the problematic feature flag if available.
- Restore database state only with an explicit backup and approval.

SOOM Instagram Dashboard rollback options:

- Revert to previous hosting deployment.
- Revert the bad commit and redeploy.
- Restore previous generated assets or exports.
- Disable publishing or external sharing until corrected.

Rollback execution:

1. Record current state before changing it.
2. Execute the smallest rollback that restores service.
3. Smoke test the restored target.
4. Confirm the incident is resolved or reduced.
5. Record final version, deployment ID, or build number.
6. Create a follow-up task for root cause and prevention.

Rollback evidence format:

```text
Project:
Environment:
Bad version:
Restored version:
Action taken:
Validation:
Remaining risk:
Follow-up task:
```

After rollback:

- Do not resume feature deployment until root cause is understood.
- Update the release checklist if the failure exposed a missing check.
- Add a Hermes update with status, impact, rollback action, and next step.
