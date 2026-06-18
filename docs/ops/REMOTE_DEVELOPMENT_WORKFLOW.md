# Remote Development Workflow

## Purpose

This document defines how to work on SOOM and other projects remotely using the Mac mini, Codex, GitHub, local builds, screenshots, and TestFlight.

The goal is to keep remote development predictable:

- one project at a time
- clear task files
- small commits
- local verification before TestFlight
- no accidental cross-project changes

## 1. Current Project Locations

Primary SOOM workspace:

```text
/Volumes/Platinum1TB/SOOM
```

Important SOOM locations:

```text
/Volumes/Platinum1TB/SOOM/SOOM.xcodeproj
/Volumes/Platinum1TB/SOOM/SOOM
/Volumes/Platinum1TB/SOOM/docs
/Volumes/Platinum1TB/SOOM/docs/specs
/Volumes/Platinum1TB/SOOM/docs/ops
/Volumes/Platinum1TB/SOOM/tasks/soom
```

Recommended convention for additional projects:

```text
/Volumes/Platinum1TB/<PROJECT_NAME>
```

Each project should keep its own:

- Git repository
- task folder
- docs/specs folder
- build artifacts
- Codex work sessions

Do not mix SOOM tasks, specs, screenshots, or commits with another project.

## 2. How To Connect To Mac Mini Remotely

Preferred remote access stack:

- Remote desktop for visual inspection, Simulator, screenshots, and Xcode UI checks.
- SSH for terminal commands, Git, and long-running builds.
- GitHub for durable code history and review checkpoints.

Before leaving the local network, confirm:

- Mac mini is powered on.
- Network access is stable.
- Remote login or remote desktop access is enabled.
- Xcode, Simulator, and Codex work locally before relying on them remotely.
- The SOOM repo is clean or intentionally dirty with known work in progress.

Remote session checklist:

```sh
cd /Volumes/Platinum1TB/SOOM
git status --short
git log --oneline -6
```

If using remote desktop, keep Simulator visible when doing screenshot or gesture review.

## 3. How To Run Codex Safely

Always start Codex from the project root:

```sh
cd /Volumes/Platinum1TB/SOOM
```

Safe Codex rules:

- Start each request by naming the exact task or file scope.
- Say explicitly when Codex must not modify files.
- Say explicitly when Codex must not build.
- Say explicitly when Codex must not commit.
- Ask Codex to run `git status --short` before staging or committing.
- Keep commits small and topic-specific.

Use this wording for risky work:

```text
Do not modify app code.
Do not build.
Do not commit.
```

Use this wording for implementation work:

```text
Before changing files, read:
- docs/specs/...
- tasks/soom/...

After implementation:
- run xcodebuild
- report files changed
- report risks
- do not commit
```

Codex should not be used to blindly patch unstable UI interactions. For motion-heavy work, first create a spec, then a prototype, then screenshots, then production integration.

## 4. How To Manage Tasks

SOOM task files live in:

```text
tasks/soom
```

Task naming:

```text
tasks/soom/0008-strava-detail-clone-prototype.md
tasks/soom/0009-next-task-name.md
```

Task file format:

- Goal
- Context/spec references
- Requirements
- Constraints
- Acceptance criteria
- Validation commands
- Commit policy

Recommended flow:

1. Create a task file.
2. Commit the task/spec if it is stable.
3. Implement only that task.
4. Build and screenshot if relevant.
5. Review changed files.
6. Commit implementation separately.

Do not let implementation instructions live only in chat. Durable decisions should move into `docs/specs` or `tasks/soom`.

## 5. How To Separate Projects

Each project should have a separate root directory:

```text
/Volumes/Platinum1TB/SOOM
/Volumes/Platinum1TB/<OTHER_PROJECT>
```

Before any Codex task, verify:

```sh
pwd
git remote -v
git status --short
```

Project separation rules:

- Never run Git commands from the wrong project root.
- Never copy task files between projects without renaming and reviewing them.
- Never reuse screenshots without marking the source project.
- Never commit generated assets or prototypes to the wrong repo.
- Keep TestFlight, signing, bundle IDs, and app store metadata project-specific.

If multiple projects are active, keep a separate terminal tab or tmux window per project with the project name visible.

## 6. Git Branch And Commit Rules

Default rule:

- Work on a feature branch for risky or multi-step work.
- Commit small stable checkpoints.
- Keep unrelated changes in separate commits.

Recommended branch names:

```text
feat/feed-home-v1
feat/record-detail-frame-lock
docs/remote-workflow
chore/testflight-setup
```

Commit categories:

```text
feat(...)
fix(...)
docs(...)
style(...)
chore(...)
test(...)
```

Before staging:

```sh
git status --short
git diff --stat
```

Before committing:

```sh
git diff --cached --stat
git diff --cached
```

Commit rules:

- Do not commit failing builds unless the commit is explicitly marked as a broken checkpoint.
- Do not mix docs-only changes with app implementation unless the docs are required for that implementation.
- Do not mix global app shell changes with feature UI changes.
- Do not commit TestFlight/Fastlane changes with product UI changes.
- Do not commit secrets, provisioning profiles, tokens, or local machine paths that expose credentials.

## 7. Build And Test Commands

Standard SOOM simulator build:

```sh
xcodebuild -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Useful simulator commands:

```sh
xcrun simctl list devices
xcrun simctl boot "<DEVICE_ID_OR_NAME>"
xcrun simctl install booted /path/to/SOOM.app
xcrun simctl launch booted app.soom.prototype
xcrun simctl io booted screenshot /tmp/soom-screens/example.png
```

Recommended validation sequence:

1. `git status --short`
2. `xcodebuild ... build`
3. Launch app in Simulator.
4. Verify changed flow manually.
5. Capture screenshots for UI work.
6. Report remaining risks.

For UI-only changes, at minimum verify:

- app launches
- changed screen opens
- primary interaction works
- existing Feed, Record, and Recovery entry points are not obviously broken

## 8. TestFlight Upload Flow

Use TestFlight only after local build and smoke review pass.

Pre-upload checklist:

- Git status is clean or only contains intentional release metadata.
- Version and build number are correct.
- Signing configuration is correct.
- Release notes are written.
- No debug-only prototype entry is accidentally exposed unless intended.
- No local/mock-only feature is presented as production-ready.

Recommended archive flow:

1. Build locally on simulator.
2. Build or archive for generic iOS device in Xcode or command line.
3. Upload through Xcode Organizer or approved Fastlane lane.
4. Wait for App Store Connect processing.
5. Add internal tester notes.
6. Install from TestFlight.
7. Run smoke test on physical device.

Do not combine TestFlight upload work with product UI implementation commits. TestFlight changes should be their own task and commit.

## 9. Screenshot Review Flow

Use screenshots for:

- layout frame validation
- gesture state comparison
- before/after review
- TestFlight smoke reports

Recommended screenshot folder:

```text
/tmp/soom-screens
```

Capture command:

```sh
xcrun simctl io booted screenshot /tmp/soom-screens/<name>.png
```

Screenshot naming:

```text
feed-home-v5-preview.png
record-detail-map-sheet-expanded.png
strava-frame-lock-preview.png
strava-frame-lock-expanded.png
```

Screenshot review rules:

- Capture the exact requested states.
- Verify screenshots before reporting paths.
- Do not commit temporary screenshots unless a task explicitly asks for visual fixtures.
- For motion work, capture at least preview, expanded, scrolled, and collapsed states.
- If automation cannot reproduce a gesture, report that honestly instead of claiming success.

## 10. Daily Operating Routine

Start of day:

```sh
cd /Volumes/Platinum1TB/SOOM
git status --short
git log --oneline -6
```

Then:

1. Review current task file.
2. Review relevant specs.
3. Confirm whether today is docs, prototype, app implementation, QA, or TestFlight work.
4. Create a branch if the work is risky or multi-step.
5. Ask Codex to work within one clear scope.

During work:

- Keep changes small.
- Build after meaningful implementation.
- Capture screenshots for UI changes.
- Commit stable checkpoints.
- Leave clear notes for known risks.

End of day:

```sh
git status --short
git diff --stat
git log --oneline -6
```

End-of-day checklist:

- Important changes are committed.
- Uncommitted changes are intentional and understood.
- Screenshots needed for review are saved and paths are recorded.
- Failing builds or known broken states are documented.
- Next task is written in `tasks/soom`.

If stopping mid-task, leave a short note in the task file or commit message explaining:

- what changed
- what still needs validation
- what should not be touched next

