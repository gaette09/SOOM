# Codex Approval Policy

## Purpose

Reduce approval fatigue during normal development while preserving safety for destructive, system-level, and credential-sensitive operations.

This policy is intended for trusted project workspaces where Codex should be able to run common development commands without repeated approval prompts, while still requiring explicit approval for operations that can delete data, alter system configuration, change credentials, or rewrite repository history.

## Current Operating Model

- Approval mode: `on-request` / guardian approvals
- Sandbox mode: `workspace-write`
- Recommended project trust: trusted workspace
- Network access: restricted unless explicitly approved

## Approved Prefixes

These command prefixes are safe for normal development workflow and may be approved persistently for trusted workspaces:

- `git add`
- `git commit`
- `git status`
- `git log`
- `xcodebuild`
- `npm run build`
- `npm run dev`
- `ps`
- `rg`
- `find`
- `ls`
- `cat`

Expected use:

- Stage explicitly requested files.
- Commit explicitly requested changes.
- Inspect repository status and history.
- Build or run local development targets.
- Search and inspect local files.
- Inspect local process state when needed for development diagnostics.

## Protected Prefixes

These command prefixes must remain approval-gated:

- `rm`
- `rm -rf`
- `git reset --hard`
- `security`
- `defaults write`
- `chmod -R`
- `chown -R`

Required review:

- Confirm exact target path before deletion.
- Avoid broad or recursive destructive commands unless the user explicitly requested them.
- Do not rewrite repository history without direct user instruction.
- Do not modify keychain, credentials, profiles, signing assets, or system defaults without explicit approval.
- Do not recursively change permissions or ownership without a specific recovery reason.

## Safety Rules

- Prefer workspace-scoped commands.
- Stage only files explicitly requested by the user.
- Do not commit automatically unless the user asks for a commit.
- Do not deploy unless the user asks for deployment.
- Do not approve broad shell prefixes that allow arbitrary scripting.
- Treat credential, signing, and system configuration changes as protected even if the command prefix is not listed above.

## Recommended Configuration

Use `on-request` approvals with persistent approvals for the approved development prefixes.

Keep `workspace-write` sandboxing enabled so normal file edits and builds can proceed inside the repository, while writes outside the workspace still require approval.

This gives Codex enough autonomy for routine development while preserving a hard checkpoint for high-risk operations.
