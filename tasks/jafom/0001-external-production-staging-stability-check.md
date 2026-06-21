# External Production/Staging Stability Check

## Goal

Confirm JAFOM external production and staging stability, including availability, key workflow health, and current deploy state.

## Current Status

Active.

JAFOM needs an external production/staging stability check before backup and rollback planning can be made concrete.

## Acceptance Criteria

- JAFOM project root is identified.
- GitHub repository and active branch are confirmed.
- Production and staging URLs are identified.
- Key workflows are smoke tested.
- Current deployment state is recorded.
- Any broken workflow, missing access, or unclear target is documented as a blocker.

## Verification Method

- From the JAFOM project root, run:

```sh
pwd
git remote -v
git status --short
git branch --show-current
```

- Open production and staging targets.
- Smoke test key workflows.
- Record URLs checked, timestamp, workflow results, errors, and deployment IDs or commit SHAs if available.

## Blockers

- JAFOM local project root is not yet confirmed.
- Hosting provider, production URL, staging URL, and deploy metadata may still be unknown.

## Priority

2. Second active priority.

This task follows the SOOM Record Detail Content Lock and precedes the JAFOM backup/rollback checklist.
