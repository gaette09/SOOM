# Harness Phase 2 Automation Plan

## Purpose

Move Harness from read-only validation to daily operations automation for SOOM, JAFOM, and the SOOM Instagram Dashboard.

Phase 2 keeps the same safety boundary as Phase 1 by default:

- No app-code modification.
- No deploys.
- No commits.
- No installs.
- No secret reads.

Automation in this phase should generate or validate operating documents only when explicitly requested.

## Current Baseline

Harness Phase 1 is installed at:

```text
tools/harness-poc
```

Current startup command:

```sh
node tools/harness-poc/check-queue.mjs
```

Current verified integrations:

- `docs/ops/PROJECT_MEMORY.md`
- `docs/ops/PROJECT_GOALS.md`
- `docs/ops/TODAY_QUEUE.md`
- `tasks/`
- `docs/reports/`

Latest daily operations report:

```text
docs/reports/DAILY_OPERATIONS_REPORT.md
```

Current Harness result:

```text
Result: PASS
```

## 1. Daily Report Automation

Objective:

- Generate a daily operations report from project memory, goal hierarchy, Today Queue, task files, report files, and Harness validation output.

Recommended command:

```sh
node tools/harness-poc/generate-daily-report.mjs
```

Recommended output:

```text
docs/reports/daily/YYYY-MM-DD-operations-report.md
```

Optional compatibility output:

```text
docs/reports/DAILY_OPERATIONS_REPORT.md
```

Required report sections:

- Source inputs.
- Harness result.
- Active tasks.
- Project status.
- Blockers.
- Deployment status.
- Recommended next actions.
- Operating decision.

Inputs:

| Input | Use |
| --- | --- |
| `docs/ops/PROJECT_MEMORY.md` | Stable roots, repositories, deployment targets, blockers, and last verified dates |
| `docs/ops/PROJECT_GOALS.md` | Active, Next, and Blocked goals |
| `docs/ops/TODAY_QUEUE.md` | Current daily active queue |
| `tasks/<project>/*.md` | Acceptance criteria, verification method, priority, and blockers |
| `docs/reports/*.md` | Existing evidence and task findings |
| `tools/harness-poc/harness.config.json` | Expected roots, branches, remotes, active task/report mappings |

Automation rules:

- Report generation is allowed only when explicitly requested.
- Generated reports must not modify app code.
- Generated reports must include the Harness command and result.
- Reports must distinguish verified facts from missing evidence.
- Reports must not treat deployment readiness as deployment approval.

Recommended implementation:

1. Add a new generator script under `tools/harness-poc`.
2. Reuse the existing validation logic from `check-queue.mjs`.
3. Build the Markdown report from structured validation output.
4. Write only to `docs/reports/`.
5. Print the generated file path and summary.

## 2. Queue Freshness Checks

Objective:

- Detect whether `docs/ops/TODAY_QUEUE.md` is still aligned with the current date, active goals, and active task reports.

Checks:

| Check | Rule |
| --- | --- |
| Queue exists | `docs/ops/TODAY_QUEUE.md` must exist. |
| Active task coverage | Every Active goal in `PROJECT_GOALS.md` must appear in `TODAY_QUEUE.md`. |
| Report coverage | Every Today Queue task must have a matching report file. |
| Report freshness | Every Today Queue report should be dated for the current operating day or explicitly marked historical. |
| Worktree safety | Harness should report each project worktree status before active execution starts. |
| Queue scope safety | Today Queue must not request deploy, install, commit, or app-code changes unless explicitly stated. |

Recommended command:

```sh
node tools/harness-poc/check-queue.mjs --freshness
```

Initial implementation can keep this as a separate command:

```sh
node tools/harness-poc/check-freshness.mjs
```

Output states:

| State | Meaning |
| --- | --- |
| `PASS` | Queue is current and all active reports exist. |
| `WARN` | Queue is valid but evidence is stale or incomplete. |
| `FAIL` | Required queue, task, or report mappings are missing. |

## 3. Goal/Task Drift Detection

Objective:

- Detect drift between `PROJECT_GOALS.md`, `TODAY_QUEUE.md`, `tasks/`, and `docs/reports/`.

Drift types:

| Drift type | Example | Severity |
| --- | --- | --- |
| Active goal missing from Today Queue | SOOM Active goal not listed in `TODAY_QUEUE.md` | Fail |
| Today Queue task missing from Project Goals | Queue references an untracked task | Fail |
| Task file missing | `tasks/soom/0009...` does not exist | Fail |
| Report file missing | Active task has no `docs/reports/*` report | Fail |
| Task section missing | Active task lacks verification method or blockers | Warn or fail |
| Memory mismatch | Project root, branch, or repo differs between memory and Harness config | Fail |
| Blocker mismatch | Blocker appears in task/report but not `PROJECT_MEMORY.md` | Warn |

Recommended command:

```sh
node tools/harness-poc/check-drift.mjs
```

Required output:

```text
Goal/task drift:
- Active goal coverage: PASS
- Today Queue coverage: PASS
- Task file coverage: PASS
- Report file coverage: PASS
- Memory alignment: PASS/WARN/FAIL
```

Implementation notes:

- Prefer structured parsing where practical.
- Keep matching conservative and explicit.
- Do not auto-edit goals, tasks, or reports in the first Phase 2 rollout.
- If auto-fix is added later, require a separate explicit user request.

## 4. Deployment Verification Hooks

Objective:

- Add safe hooks that verify deployment metadata and access readiness without deploying.

Default Phase 2 behavior:

- Deployment hooks are disabled unless explicitly requested.
- Hooks must be read-only.
- Hooks must never run `vercel deploy`, Fastlane upload, App Store Connect upload, database migrations, or production mutations.

Recommended hook categories:

| Project | Hook | Read-only verification |
| --- | --- | --- |
| SOOM | TestFlight readiness hook | Confirm configured bundle ID, build number, Fastlane lane presence, signing status notes, and latest blocker state. |
| JAFOM | Vercel metadata hook | Confirm recorded Vercel URL, deployment ID, deployed SHA, and route/auth smoke result fields exist. |
| Instagram | Static Vercel review hook | Confirm recorded static review URL, deployment ID, desktop/mobile review result fields, and feedback path exist. |

Recommended config extension:

```json
{
  "deploymentHooks": {
    "enabledByDefault": false,
    "allowDeploy": false,
    "projects": {
      "soom": {
        "target": "testflight",
        "mode": "metadata-only"
      },
      "jafom": {
        "target": "vercel",
        "mode": "metadata-only"
      },
      "instagram": {
        "target": "vercel-static",
        "mode": "metadata-only"
      }
    }
  }
}
```

Recommended command:

```sh
node tools/harness-poc/check-deployments.mjs
```

Expected result:

- Harness reports whether required deployment evidence fields are present.
- Harness flags missing URLs, deployment IDs, deployed SHAs, and smoke results.
- Harness does not authenticate to deployment providers in the first rollout.
- Harness does not deploy.

## 5. Project Memory Verification

Objective:

- Keep `docs/ops/PROJECT_MEMORY.md` authoritative and current enough for automation.

Checks:

| Field | Required for | Rule |
| --- | --- | --- |
| Local path | All projects | Must exist on disk or be explicitly marked unavailable. |
| GitHub | All projects | Must match configured expected remote. |
| Branch | All projects | Must match configured expected branch. |
| Deployment target | All projects | Must be present. |
| URL | JAFOM, Instagram | Must be recorded or explicitly marked `Not recorded yet`. |
| Active goal | All projects | Must match `PROJECT_GOALS.md`. |
| Current task | All projects | Must match Active goal task file. |
| Last verified | All projects | Must be present and reviewed for staleness. |
| Known blockers | All projects | Must reflect active blocker set. |

Recommended command:

```sh
node tools/harness-poc/check-memory.mjs
```

Recommended output:

```text
Project memory:
- SOOM: PASS
- JAFOM: WARN missing Vercel URL
- Instagram: WARN missing Vercel URL
```

Automation rules:

- Harness may propose memory updates.
- Harness must not update `PROJECT_MEMORY.md` unless explicitly requested.
- Secret values must never be added to memory.
- Deployment URLs may be stored; tokens, session IDs, and credentials may not be stored.

## 6. Rollout Plan

### Phase 2A: Report Generator Design

Objective:

- Convert the current manual daily operations report format into a repeatable generator design.

Deliverables:

- `tools/harness-poc/generate-daily-report.mjs` design notes or implementation.
- Standard daily report template.
- Explicit output path policy.

Success criteria:

- Generated report includes all required sections.
- Generated report uses current Harness validation output.
- No app code is modified.

Estimated effort:

```text
0.5 day
```

### Phase 2B: Freshness and Drift Checks

Objective:

- Add checks that detect stale queue/report state and goal/task drift.

Deliverables:

- Freshness check.
- Drift check.
- Pass/warn/fail output convention.

Success criteria:

- Missing active task reports are detected.
- Stale reports are detected.
- Active goal and Today Queue mismatch is detected.
- Memory/config mismatch is detected.

Estimated effort:

```text
1 day
```

### Phase 2C: Memory Verification

Objective:

- Verify that `PROJECT_MEMORY.md` remains the stable project fact source.

Deliverables:

- Memory verification command.
- Missing or stale memory field warnings.
- Recommended memory update section in the daily report.

Success criteria:

- Missing Vercel URLs are flagged.
- Last verified dates are checked.
- Active goals and current tasks match the goal system.

Estimated effort:

```text
0.5-1 day
```

### Phase 2D: Deployment Metadata Hooks

Objective:

- Add read-only deployment evidence checks without provider mutation.

Deliverables:

- Deployment metadata check command.
- SOOM TestFlight readiness evidence check.
- JAFOM Vercel evidence field check.
- Instagram static Vercel evidence field check.

Success criteria:

- Missing deployment URLs and deployment IDs are flagged.
- SOOM signing/archive blocker remains visible.
- No deployment command is available from Harness.

Estimated effort:

```text
1 day
```

### Phase 2E: Daily Operations Automation Dry Run

Objective:

- Run all Phase 2 automation in read-only mode and generate one daily report.

Recommended command:

```sh
node tools/harness-poc/generate-daily-report.mjs --dry-run
```

Success criteria:

- Harness produces a daily report draft.
- Harness reports freshness, drift, memory, and deployment metadata status.
- The draft is reviewed before committing.
- No app code, deployment state, or secrets are touched.

Estimated effort:

```text
0.5 day
```

## Recommended Next Step

Start with Phase 2A and Phase 2B together:

1. Add structured validation output to `check-queue.mjs`.
2. Add `generate-daily-report.mjs`.
3. Add queue freshness checks.
4. Run the generated report in dry-run mode.

Do not add deployment provider integrations until the report generator and drift checks are stable.

