# Harness POC

Version: `0.1.0-phase1`

Purpose: read-only Phase 1 Harness proof of concept for the SOOM/JAFOM/Instagram operating system.

Startup command:

```sh
node tools/harness-poc/check-queue.mjs
```

Allowed behavior:

- Read `docs/ops/PROJECT_MEMORY.md`.
- Read `docs/ops/PROJECT_GOALS.md`.
- Read `docs/ops/TODAY_QUEUE.md`.
- Read `tasks/`.
- Read `docs/reports/`.
- Run `git remote -v`, `git branch --show-current`, and `git status --short` for configured project roots.
- Print a validation summary.

Forbidden behavior:

- Modify app code.
- Modify docs.
- Install dependencies.
- Deploy.
- Commit.
- Push.
- Read or print secrets.

