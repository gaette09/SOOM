# SOOM TestFlight Readiness

## Purpose

This document tracks the pre-TestFlight readiness state for SOOM. It focuses on build, archive, signing, environment injection, permissions, and manual QA. It does not introduce cloud sync, user ownership migration, App Store Connect upload automation, or changes to RecoveryCalculator, Workout, or Growth calculation logic.

## Current Project Snapshot

- Project: `SOOM.xcodeproj`
- Scheme: `SOOM`
- Bundle identifier: `app.soom.prototype`
- Display name: `SOOM`
- Version: `1.0`
- Build number: `1`
- URL scheme: `soom-auth` through `SOOM_AUTH_REDIRECT_SCHEME`
- Category: `public.app-category.healthcare-fitness`
- Entitlements:
  - HealthKit enabled
  - Sign In with Apple enabled
- Supabase SDK: installed behind auth provider/client provider boundaries
- Mapbox SDK: installed through Swift Package Manager
- Mapbox token: `MBXAccessToken = $(MBX_ACCESS_TOKEN)` placeholder only

Before TestFlight, confirm whether `app.soom.prototype` is the intended production/TestFlight bundle identifier. If the production bundle id changes, update Apple Developer capabilities, provisioning profiles, Supabase redirect allowlists, and TestFlight metadata together.

## Release Build Checklist

- Select the `SOOM` scheme.
- Use Release configuration for archive.
- Confirm `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are correct for the TestFlight build.
- Confirm `PRODUCT_BUNDLE_IDENTIFIER` matches the App Store Connect app record.
- Confirm automatic signing resolves a valid distribution profile for the selected team.
- Confirm `SOOM/SOOM.entitlements` includes HealthKit and Sign In with Apple.
- Confirm `Info.plist` contains required runtime placeholders, not real secrets.
- Confirm the built app expands `SOOM_AUTH_REDIRECT_SCHEME` to `soom-auth`.
- Confirm no local `.xcconfig` or generated secret file is staged in git.

## Archive Checklist

Run an archive dry-run before upload:

```sh
xcodebuild -project /Volumes/Platinum1TB/SOOM/SOOM.xcodeproj \
  -scheme SOOM \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  archive
```

Archive outcomes:

- Pass: archive completes and produces an iOS archive signed for the configured team.
- Signing failure: record the signing/provisioning issue, but do not treat it as a product logic failure.
- Environment failure: confirm build settings are injected outside the repo.
- Package failure: resolve Swift Package dependencies before attempting upload.

Do not automate App Store Connect upload from this readiness step.

## Signing And Provisioning Checklist

- Apple Developer account has an app identifier for the final bundle id.
- HealthKit capability is enabled for the app identifier.
- Sign In with Apple capability is enabled for the app identifier.
- The provisioning profile for the same bundle id includes both HealthKit and Sign In with Apple entitlements.
- Distribution certificate and provisioning profile are valid.
- App Store Connect app record exists for the bundle id.
- Team id in the Xcode project matches the intended release team.
- TestFlight build uses Release signing, not local simulator signing.

## Signing Blocker: Sign In with Apple Profile Mismatch

The current archive failure is a provisioning mismatch:

- Bundle identifier: `app.soom.prototype`
- Xcode entitlement file: `SOOM/SOOM.entitlements`
- Entitlement present in app entitlements: `com.apple.developer.applesignin`
- Failing provisioning profile: `iOS Team Provisioning Profile: app.soom.prototype`
- Missing from profile: Sign In with Apple / `com.apple.developer.applesignin`

This means the app target is asking for Sign In with Apple, but the selected provisioning profile was generated before that capability was enabled or has not been refreshed. Do not remove the app entitlement to make archive pass; fix the App ID and provisioning profile instead.

Manual Apple Developer actions:

1. Open Apple Developer > Certificates, Identifiers & Profiles.
2. Select the App ID for `app.soom.prototype` or the final production bundle id.
3. Enable **Sign In with Apple** for that App ID.
4. Confirm **HealthKit** remains enabled.
5. Save the App ID capability changes.
6. Regenerate the iOS App Store / distribution provisioning profile for the same App ID.
7. Download/install the regenerated profile or let Xcode automatic signing fetch it.
8. Confirm the profile details include `com.apple.developer.applesignin`.

Xcode refresh actions:

1. Open Xcode > Settings > Accounts.
2. Select the release team `82D59P8SDL`.
3. Refresh/download provisioning profiles.
4. Open the SOOM target > Signing & Capabilities.
5. Confirm Team, Bundle Identifier, HealthKit, and Sign In with Apple match the Apple Developer App ID.
6. Clean build folder if Xcode keeps selecting a stale profile.
7. Retry archive with the command below.

Archive retry command:

```sh
xcodebuild -project /Volumes/Platinum1TB/SOOM/SOOM.xcodeproj \
  -scheme SOOM \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  archive
```

## Environment Checklist

Inject these values through local Xcode build settings, ignored `.xcconfig`, CI secrets, or App Store Connect/Xcode Cloud secrets. Do not commit real values.

| Setting | Expected TestFlight value | Repository state |
| --- | --- | --- |
| `SOOM_SUPABASE_URL` | Production or staging Supabase project URL | Placeholder only |
| `SOOM_SUPABASE_ANON_KEY` | Matching Supabase anon key | Placeholder only |
| `SOOM_AUTH_REDIRECT_SCHEME` | `soom-auth` | Project default |
| `MBX_ACCESS_TOKEN` | Mapbox public access token | Placeholder only |

Secret safety rules:

- Never commit Supabase URL, anon key, OAuth secrets, Apple private key, or Mapbox secret token.
- Mapbox public token may be injected at build time, but should still stay out of source files.
- Keep local `.xcconfig` files with real values ignored.
- Keep screenshots/logs containing magic links or tokens out of the repo.

## Required Capabilities

### HealthKit

- Entitlement: enabled.
- `NSHealthShareUsageDescription`: present in `Info.plist`.
- Read-only data use: workout, heart rate, distance, active energy, routes, cadence, and power where available.
- QA must cover permission granted, permission denied, and no-data states.

### Sign In with Apple

- Entitlement: enabled.
- Supabase Apple provider must be configured outside the repo.
- Apple private key and provider secrets stay in Apple/Supabase secret storage only.
- Apple sign-in creates account state only; it does not migrate local workout ownership.

### Supabase Redirect Scheme

- Production callback URL: `soom-auth://auth/callback`.
- `CFBundleURLTypes` uses `$(SOOM_AUTH_REDIRECT_SCHEME)`.
- Supabase Dashboard redirect allowlist must include `soom-auth://auth/callback`.
- Email Magic Link callback updates account UI state only; it does not cloud sync local data.

### Mapbox

- `MBXAccessToken` is read from `Info.plist`.
- Current repo value is `$(MBX_ACCESS_TOKEN)`.
- Token missing or route missing must fall back to neutral route UI.
- Share/feed previews must keep route privacy masking.

## Auth QA Checklist

Use `docs/SOOM_DEVICE_AUTH_QA_CHECKLIST.md` for detailed device auth QA. TestFlight readiness should include:

- Email Magic Link request succeeds with configured Supabase.
- Magic Link opens `soom-auth://auth/callback` into SOOM.
- Callback bridges Supabase session to root auth state.
- App relaunch restores Supabase currentSession when available.
- Remote sign-out/account unlink returns to local-first state.
- Apple Sign In can create a Supabase session when Apple/Supabase settings are valid.
- Failed/cancelled auth preserves local session.
- Account connected state does not imply data sync or ownership migration.

## HealthKit QA Checklist

- Fresh install shows local-first state before permissions.
- HealthKit permission request explains read-only use clearly.
- Permission denied keeps the app usable.
- Manual workout import works when HealthKit has workouts.
- No-workout state shows gentle empty/fallback UI.
- Imported workout detail can fetch HR/cadence/power streams when present.
- Missing stream data shows unavailable/fallback zone cards without error tone.
- Workout routes persist locally when available.
- Route fetch failure does not fail workout import.
- RecoveryCalculator output is not changed by import.
- Growth calculations only use the established UnifiedWorkout/Growth input path.

## Map And Route QA Checklist

- Mapbox token present: route hero renders for workouts with route data.
- Mapbox token missing: route hero uses fallback without crash.
- Route missing: detail UI remains useful with summary metrics.
- Persisted route reuse works for comparison/course record/progression where route data exists.
- Terrain cue appears only when route/elevation context is sufficient.
- Climb insight uses persisted route elevation when available, then summary fallback.
- Share/feed static route preview uses privacy masking by default.
- Very short or unsafe routes fall back instead of exposing precise start/end locations.

## App Store And TestFlight Metadata TODO

- App name and subtitle.
- Short description and TestFlight beta notes.
- Support URL.
- Privacy policy URL.
- Health data usage explanation.
- Sign In with Apple compliance notes.
- Privacy Nutrition Labels:
  - Health and fitness data read from HealthKit.
  - Contact info/email only if Supabase auth is used.
  - Identifiers/account id only for connected Supabase auth state.
  - Location/route data handling, including local-first and masked sharing boundaries.
- Export compliance answers.
- Age rating questionnaire.
- Beta tester instructions for HealthKit, Auth, Mapbox token, and local-first data boundaries.

## Build Validation Commands

```sh
xcodebuild -project /Volumes/Platinum1TB/SOOM/SOOM.xcodeproj \
  -scheme SOOM \
  -destination 'platform=iOS Simulator,id=E6A13169-3246-423B-895D-A707A36D5076' \
  test \
  -parallel-testing-enabled NO
```

```sh
xcodebuild -project /Volumes/Platinum1TB/SOOM/SOOM.xcodeproj \
  -scheme SOOM \
  -destination 'generic/platform=iOS Simulator' \
  build
```

```sh
xcodebuild -project /Volumes/Platinum1TB/SOOM/SOOM.xcodeproj \
  -scheme SOOM \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  archive
```

## Deferred Items

- App Store Connect upload automation.
- Actual production secret injection verification in CI.
- User ownership migration.
- Cloud sync for HealthKit, workouts, routes, Feed, Recovery, Growth, or progression.
- Google OAuth.
- Password login.
- Account deletion and server-side data deletion.
- Production support playbook for expired links, revoked Apple credentials, and cross-device magic links.

## Readiness Assessment

Current readiness is high for simulator build/test and local-first product logic, but not complete for TestFlight until archive/signing and real device QA pass.

- Code/test readiness: strong.
- Auth readiness: feature-complete foundation, requires real device QA.
- HealthKit readiness: implemented, requires permission and import QA on real data.
- Map readiness: implemented with placeholder token strategy, requires injected token QA.
- Ownership/cloud readiness: intentionally deferred.

## Validation Log

### 2026-05-27

- `xcodebuild clean -project /Volumes/Platinum1TB/SOOM/SOOM.xcodeproj -scheme SOOM`: passed.
- `xcodebuild test -destination 'platform=iOS Simulator,id=E6A13169-3246-423B-895D-A707A36D5076'`: passed.
- `xcodebuild build -destination 'generic/platform=iOS Simulator'`: passed.
- `xcodebuild archive -configuration Release -destination 'generic/platform=iOS'`: failed at signing/provisioning.

Archive blocker:

- The provisioning profile `iOS Team Provisioning Profile: app.soom.prototype` does not include the Sign In with Apple capability.
- The same profile does not include the `com.apple.developer.applesignin` entitlement.

This is a release signing readiness issue, not a simulator build/test or product logic failure. Before TestFlight upload, update the Apple Developer app identifier/provisioning profile so Sign In with Apple is enabled for the final bundle id, then regenerate or refresh the distribution profile used by the archive.

Next manual action: regenerate or refresh the provisioning profile after enabling Sign In with Apple on the App ID, then rerun the archive command above.
