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

Email Magic Link uses the app URL scheme. Native Apple Sign In uses the Apple credential and Supabase id-token exchange, so it does not require this URL scheme for the Apple button itself.

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

## Deferred Items

- Remote sign-out and account unlink.
- User ownership migration.
- Cloud sync for HealthKit, workouts, routes, Feed, Recovery, Growth, or progression.
- Google OAuth.
- Password login.
- Production support playbook for expired, revoked, or cross-device magic links.
