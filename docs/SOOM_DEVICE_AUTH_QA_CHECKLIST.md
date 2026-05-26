# SOOM Device Auth QA Checklist

## Purpose

This checklist verifies production redirect readiness for Email Magic Link and device auth flows without committing secrets or implying that account connection migrates local data.

## Redirect Scheme Decision

- Default production scheme: `soom-auth`
- Callback URL: `soom-auth://auth/callback`
- Build setting: `SOOM_AUTH_REDIRECT_SCHEME`
- Info.plist registration: `CFBundleURLTypes` uses `$(SOOM_AUTH_REDIRECT_SCHEME)`

SOOM uses one production-ready scheme in v1 to keep Supabase Dashboard allowlists and TestFlight QA simple. Dev builds may override `SOOM_AUTH_REDIRECT_SCHEME` through an ignored `.xcconfig` or local Xcode build setting, but the repository default stays `soom-auth`.

The scheme is not a secret. Supabase URL, anon key, Apple private key, and OAuth provider secrets must still be injected outside the repository.

## Supabase Dashboard Setup

Configure Supabase Auth URL settings with:

- Site URL: the production app/web landing URL when one exists, or the Supabase-approved native fallback used by the project.
- Additional Redirect URLs: `soom-auth://auth/callback`
- Email Magic Link template: keep the generated confirmation link intact and make sure the redirect target matches the allowlisted native URL.
- Email Magic Link provider: enabled.
- Apple provider: enabled only when device QA includes Apple Sign In.
- Apple Services ID, Team ID, Key ID, and private key: configured in Supabase Dashboard or secret storage only.

Email Magic Link uses the app URL scheme. Native Apple Sign In uses the Apple credential and Supabase id-token exchange, so it does not require this URL scheme for the Apple button itself.

Do not record Supabase project URL, anon key, Apple private key, `.p8` content, or OAuth secrets in this repository. Record only whether each setting is present.

## Local Environment Injection

Device QA requires local or CI-provided values outside the repository:

- `SOOM_SUPABASE_URL`: injected through local Xcode build settings, ignored `.xcconfig`, CI secret, or TestFlight configuration.
- `SOOM_SUPABASE_ANON_KEY`: injected through local Xcode build settings, ignored `.xcconfig`, CI secret, or TestFlight configuration.
- `SOOM_AUTH_REDIRECT_SCHEME=soom-auth`: repository default, overridable by ignored local configuration.

Safe local `.xcconfig` shape:

```xcconfig
SOOM_SUPABASE_URL = https://<project-ref>.supabase.co
SOOM_SUPABASE_ANON_KEY = <anon-key-from-local-secret-store>
SOOM_AUTH_REDIRECT_SCHEME = soom-auth
```

Keep the actual `.xcconfig` with real values out of git. Before QA, confirm the built app's `Info.plist` contains `CFBundleURLSchemes = soom-auth` and that Settings shows Supabase environment as configured.

## Real Device QA

1. Install a build signed with the expected bundle identifier and Apple Sign In entitlement.
2. Confirm the build setting `SOOM_AUTH_REDIRECT_SCHEME=soom-auth` is present for the target.
3. Confirm Supabase URL and anon key are injected through local build settings, ignored `.xcconfig`, CI secrets, or TestFlight configuration.
4. Request an email magic link from Settings/My Page.
5. Open the email on the same device and tap the link.
6. Expected: iOS opens SOOM through `soom-auth://auth/callback`.
7. Expected: SOOM handles the callback, checks the Supabase session, and updates account state to `계정 연결됨` if a valid session exists.
8. Expected: current workouts, HealthKit imports, routes, Recovery, Growth, Feed, and progression records remain local.
9. Reuse the same link after it expires or has already been consumed.
10. Expected: callback failure is soft and the local session remains usable.

## TestFlight QA

- Fresh install with no Supabase session: app remains local-first.
- Magic Link request with configured Supabase: email request succeeds.
- Magic Link callback with installed app: app opens and account state can update.
- Magic Link callback with app not installed: document the platform fallback experience; do not treat it as an in-app failure.
- Network unavailable during callback: local session remains intact.
- Supabase unconfigured: auth UI shows a calm unavailable state.
- Apple Sign In cancel: local session remains intact.
- Apple Sign In success: account state can become connected, but local records are not migrated.
- Relaunch after successful auth: root auth bootstrap restores account state if Supabase currentSession is available.
- Remote sign-out/account unlink: implemented in Settings/My Page, but must be verified on a physical device with a real Supabase session.
- Remote sign-out success: account state returns to local-first and local workouts, settings, and route data remain on device.

## QA Result Template

Use this template per QA run. Keep secret values out of the result.

| Field | Result |
| --- | --- |
| Date | |
| Tester | |
| Device | |
| iOS version | |
| Build type | Local / TestFlight / Release Candidate |
| Bundle identifier | |
| Supabase project label | Dev / Staging / Production / Other |
| Supabase Site URL configured | Yes / No / Not checked |
| `soom-auth://auth/callback` allowlisted | Yes / No / Not checked |
| Email Magic Link enabled | Yes / No / Not checked |
| Apple provider configured | Yes / No / Not checked / Not in scope |
| Local env injected without repo secrets | Yes / No / Not checked |
| Built URL scheme is `soom-auth` | Yes / No / Not checked |
| Magic Link request result | Pass / Fail / Not run |
| Callback opens SOOM | Pass / Fail / Not run |
| Session bridge result | Pass / Fail / Not run |
| Relaunch session restore result | Pass / Fail / Not run |
| Apple Sign In result | Pass / Fail / Not run / Not in scope |
| Remote sign-out/account unlink result | Pass / Fail / Not run |
| Local-first data boundary verified | Pass / Fail / Not run |
| Known issues | |

## QA Run Notes

Append dated notes below. Avoid raw tokens, keys, private keys, email magic link URLs, or screenshots containing secrets.

### 2026-05-26 Baseline Readiness

- Production redirect scheme is defined as `soom-auth`.
- Callback URL is defined as `soom-auth://auth/callback`.
- `CFBundleURLTypes` is registered through `$(SOOM_AUTH_REDIRECT_SCHEME)`.
- Unit test/build verification passed in simulator.
- Real Supabase Dashboard allowlist and physical device Magic Link round trip still require manual QA.
- Remote sign-out/account unlink is implemented, but physical device QA with a real Supabase session is still required.

## Implemented, QA Required

- Remote sign-out and account unlink are implemented for Supabase sessions.
- Device QA must still verify remote sign-out success, sign-out failure handling, local fallback restore, and local data preservation.
- Remote sign-out does not perform account deletion, local data deletion, user ownership migration, or cloud sync.

## Deferred Items

- Account deletion and server-side data deletion.
- User ownership migration.
- Cloud sync for HealthKit, workouts, routes, Feed, Recovery, Growth, or progression.
- Google OAuth.
- Password login.
- Production support playbook for expired, revoked, or cross-device magic links.
