# Project Deployment Status

## Purpose

This document tracks which projects can be accessed externally and what remains needed before they can be reliably used from outside the Mac mini.

Status terms:

- `Ready`: external access is confirmed and repeatable.
- `Partial`: local access works, but external access still needs verification.
- `Unknown`: project exists conceptually or locally, but location/deploy path is not confirmed.
- `Blocked`: a required account, secret, build, or hosting dependency is missing.

## 1. SOOM iOS

External access target:

- TestFlight

Current status:

- `Partial`
- SOOM iOS project location is known:

```text
/Volumes/Platinum1TB/SOOM
```

- Local simulator build flow exists.
- Current status: `Partial`, build-ready but not TestFlight-ready.
- TestFlight flow needs Apple provisioning/session verification before archive or upload.

Inspection result:

- Fastlane installed: `2.236.0`
- Existing Fastlane lane: `ios archive` only
- Existing lane behavior: local Release archive build with `export_method: "app-store"`
- Missing Fastlane/App Store Connect setup:
  - `Appfile`
  - `upload_to_testflight` / `pilot` lane
  - App Store Connect API key config
  - Match setup
- Bundle ID: `app.soom.prototype`
- Team ID: `82D59P8SDL`
- Signing: `Automatic`
- Version/build: `1.0` / `1`

Needed:

- Confirm Apple Developer provisioning for `app.soom.prototype`.
- Confirm App Store Connect app record for `app.soom.prototype`.
- Confirm Sign In with Apple and HealthKit are enabled in the distribution provisioning profile.
- Confirm whether `ios archive` should be the release archive lane.
- Add or confirm an upload lane only after archive/signing is verified.
- Confirm App Store Connect upload path.
- Confirm TestFlight internal testing group.
- Confirm TestFlight install flow on physical device.
- Confirm build number increment policy.
- Confirm release notes format.

Next safe step:

```sh
cd /Volumes/Platinum1TB/SOOM
git status --short
xcodebuild -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project SOOM.xcodeproj -scheme SOOM -configuration Release -showBuildSettings | rg "PRODUCT_BUNDLE_IDENTIFIER|DEVELOPMENT_TEAM|CODE_SIGN_STYLE|CURRENT_PROJECT_VERSION|MARKETING_VERSION|SOOM_AUTH_REDIRECT_SCHEME|PROVISIONING_PROFILE"
```

Next blocked step:

```sh
fastlane ios archive
```

Run this only after Apple provisioning and account/session access are confirmed. It is a local archive lane, but it can still fail on signing and provisioning.

Open questions:

- Is `app.soom.prototype` the intended TestFlight bundle ID?
- Is the current App Store Connect app ready for upload?
- Which Apple ID/team should be used?
- Is the current local Apple Developer session valid?

## 2. JAFOM CRM

External access target:

- Public or staging web URL

Current status:

- `Unknown`
- A local/web app reportedly exists.
- External hosting status is unknown.
- Project folder is not yet identified in this document.

Needed:

- Identify project folder.
- Identify framework:
  - Next.js
  - Vite
  - Remix
  - Rails
  - other
- Identify package manager:
  - npm
  - pnpm
  - yarn
  - bun
- Identify required environment variables.
- Identify Supabase project and connection mode.
- Identify hosting target:
  - Vercel
  - Netlify
  - Cloudflare
  - self-hosted
  - other
- Identify deploy command.
- Confirm staging URL.
- Confirm rollback method.

First inspection commands once folder is known:

```sh
pwd
git status --short
git remote -v
ls
```

Likely files to inspect:

```text
package.json
.env.example
.env.local
supabase
vercel.json
netlify.toml
wrangler.toml
README.md
```

Open questions:

- Where is the project folder on the Mac mini?
- Is there a GitHub remote?
- Is Supabase already connected?
- Does staging already exist?

## 3. Instagram/SOOM Content Tool

External access target:

- Public or staging web URL

Current status:

- `Unknown`
- Dashboard/tool reportedly exists.
- External hosting status is unknown.
- Project folder is not yet identified in this document.

Needed:

- Identify project folder.
- Identify framework:
  - Next.js
  - Vite
  - Streamlit
  - custom Node app
  - other
- Identify package manager or runtime.
- Identify required environment variables.
- Identify asset/input folders.
- Identify output/export folders.
- Identify whether generated content is stored locally, in Supabase, or in another storage provider.
- Identify hosting target:
  - Vercel
  - Netlify
  - Cloudflare
  - Hugging Face Spaces
  - self-hosted
  - other
- Identify deploy command.
- Confirm staging URL.
- Confirm rollback method.

First inspection commands once folder is known:

```sh
pwd
git status --short
git remote -v
ls
```

Likely files/folders to inspect:

```text
package.json
requirements.txt
pyproject.toml
.env.example
.env.local
assets
outputs
exports
public
README.md
```

Open questions:

- Where is the project folder on the Mac mini?
- Does it generate static outputs or run as an app server?
- Are Instagram assets stored locally or remotely?
- Does it need authentication before public/staging access?

## 4. Common Operation

### GitHub Remote Check

For each project:

```sh
git remote -v
git status --short
git branch --show-current
git log --oneline -6
```

Requirements:

- Every externally deployed project should have a GitHub remote.
- Local-only projects should be marked as local-only until a remote is created.
- Deployment should come from a known branch, not from untracked local changes.

### Branch Rules

Recommended branch policy:

- `main`: stable local release or production-ready state.
- `develop` or feature branches: active implementation.
- `staging` branch only if the hosting provider deploys from a branch.

Branch naming:

```text
feat/<project-feature>
fix/<project-bug>
docs/<project-doc>
chore/<project-ops>
deploy/<target>
```

Rules:

- Do not deploy from a dirty working tree.
- Do not mix deployment config changes with product UI changes.
- Do not force-push shared branches unless explicitly agreed.

### Env Var Storage

Rules:

- Do not commit `.env.local`.
- Do not commit API keys, Supabase service role keys, Apple credentials, or hosting tokens.
- Keep `.env.example` updated with variable names only.
- Store production and staging secrets in the hosting provider dashboard.
- Store local secrets only on the Mac mini or an approved password manager.

For each project, document:

```text
ENV_VAR_NAME=
Owner:
Used by:
Local source:
Hosting source:
Required for build:
Required for runtime:
```

### Screenshot Review

Use screenshots for:

- local smoke checks
- staging review
- TestFlight review
- before/after UI comparison

Default local screenshot folder:

```text
/tmp/soom-screens
```

Rules:

- Capture exact requested states.
- Verify screenshots before reporting paths.
- Do not commit temporary screenshots unless they are intentional fixtures.
- For mobile motion, capture preview, expanded, scrolled, and collapsed states.
- For web staging, capture desktop and mobile viewport states.

### Rollback Plan

Every externally deployed project needs a rollback plan before production use.

For web projects:

- Confirm hosting provider keeps previous deployments.
- Record how to promote or restore a previous deployment.
- Keep the previous stable Git commit SHA.

For TestFlight:

- Keep the previous accepted build available when possible.
- Record current build number before uploading.
- Smoke test the new build before expanding testers.

Rollback record format:

```text
Project:
Target:
Current deployment:
Previous stable deployment:
Git SHA:
Rollback command or dashboard path:
Owner:
Last verified:
```

## Recommended Inspection Order

1. SOOM iOS TestFlight flow
2. JAFOM CRM project folder and hosting status
3. Instagram/SOOM content tool folder and hosting status

Reason:

- SOOM iOS has a known project location and known external access target.
- JAFOM CRM and Instagram/SOOM content tool still require discovery before deployment planning can be reliable.
