# SOOM Auth Environment Setup

## Purpose

SOOM keeps Auth local-first while preparing for future Supabase, Apple, and Google login. This document defines where environment values will enter the app without committing secrets or enabling network auth in v1.

## Values

The app can read these Info.plist-backed placeholders:

- `SOOMSupabaseURL = $(SOOM_SUPABASE_URL)`
- `SOOMSupabaseAnonKey = $(SOOM_SUPABASE_ANON_KEY)`
- `SOOMAuthRedirectScheme = $(SOOM_AUTH_REDIRECT_SCHEME)`

If a value is empty, still in `$(...)` build-setting form, or otherwise placeholder-like, SOOM treats it as unconfigured.

## Secret Policy

Do not commit a real Supabase URL, anon key, OAuth client id, or redirect secret to the repository. Real values should be injected later through Xcode build settings, `.xcconfig` files kept out of git, or CI secrets.

## Environment Strategy

- `local`: default app behavior, local-only session, no remote auth.
- `development`: future Supabase development project and test redirect scheme.
- `production`: future production Supabase project and production redirect scheme.

## Redirect Scheme Direction

Native Apple Sign In currently uses an in-app Apple credential plus Supabase id-token exchange and does not require the email callback URL scheme for the Apple button flow. Email Magic Link and future OAuth/deep-link completion use `SOOMAuthRedirectScheme` to prepare and validate `scheme://auth/callback`.

Production redirect v1 standardizes on `soom-auth://auth/callback`. The app registers `CFBundleURLTypes` with `$(SOOM_AUTH_REDIRECT_SCHEME)`, and the project default build setting is `soom-auth`. Dev and CI builds may override the scheme through ignored local configuration. Placeholder-like or unresolved values are still treated as invalid by runtime validation.

## Current Boundary

- Supabase Swift SDK is installed as a foundation dependency.
- Supabase sign-in completion and session ownership migration are not implemented.
- Apple Sign In can request an iOS credential and exchange the Apple ID token with Supabase when the environment is configured. Google Sign In is not implemented.
- HealthKit, workout, route, and progression data stay local-first.
- RecoveryCalculator and Growth calculations are unchanged.

## Supabase Swift SDK Integration v1

SOOM now includes the Supabase Swift SDK through Swift Package Manager using the `Supabase` product from `https://github.com/supabase/supabase-swift`. The SDK is present so the app can create a `SupabaseClient` only when the environment is explicitly configured.

`SupabaseClientProvider` is the only app-side boundary that imports the Supabase module. It reads `SupabaseAuthConfiguration` or `AuthEnvironment`, returns `nil` when values are missing or placeholder-like, and does not perform network login or session loading.

Real Supabase URL and anon key values must still come from Xcode build settings, ignored `.xcconfig` files, or CI secrets. The repository keeps only placeholder keys in `Info.plist`.

## Current SDK Boundary

- Supabase Swift SDK is installed.
- `SupabaseClient` can be constructed from configured mock/build-time values.
- Email Magic Link request UI is implemented; read-only Supabase session bridge can represent an existing session as a connected account.
- Supabase Auth sign-in completion, OAuth, session refresh, remote profile loading, and ownership migration are not implemented.
- Apple and Google OAuth redirect handling remains a future step.
- Local-first Auth remains the default app behavior.


## Supabase Email Session Smoke v1

SOOM now has a read-only Supabase auth session smoke path. `SupabaseAuthSessionProbe` asks `SupabaseClientProvider` for a configured client and reads the current Supabase auth session when one is available. It does not call sign-in, sign-up, sign-out, OAuth, or server storage APIs.

Session smoke states are intentionally limited:

- `unconfigured`: Supabase URL/key placeholders are missing or still placeholder-like.
- `signedOut`: the client is configured, but no local Supabase session is present.
- `signedIn`: a current Supabase session exists and can expose user id/email for smoke visibility.
- `failed`: session lookup failed without changing the local SOOM session.

If the environment is unconfigured, the app remains local-first. A failed smoke check must not replace `AuthSessionStore`, migrate `user_id`, upload HealthKit/workout data, or imply that completed login/session sync is active. Email Magic Link request UI exists, and a read-only session bridge can show an existing Supabase session as connected. Google OAuth, password auth, remote profile ownership, and data migration remain deferred. Apple Sign In can create a Supabase session when configured, but it does not migrate local data ownership.


## Supabase Email Auth UI v1

Settings/My Page now includes a low-pressure email auth request surface. The UI can ask the configured Supabase client to send a magic link/OTP email through `SupabaseAuthProvider.requestMagicLink(email:redirectTo:)`. This is an auth request only; a separate read-only bridge can represent an existing Supabase session in the current UI, but it does not write that user into SOOM's local `AuthSessionStore`.

Current boundary:

- Email format is validated before a request is sent.
- Supabase must be configured through environment/build settings; placeholder values keep the flow safely unavailable.
- `signInWithOTP` is used only for magic link/OTP request and starts with `shouldCreateUser: false` because explicit signup UI is still deferred.
- Redirect URL is optional for request construction, but production/device QA now uses `soom-auth://auth/callback`. `SOOM_AUTH_REDIRECT_SCHEME` is registered through `CFBundleURLTypes`, and `onOpenURL` can pass matching callbacks to Supabase Auth session handling. Durable callback persistence, remote ownership migration, and cloud sync remain future work.
- Password login, signup UI, Apple/Google OAuth, sign-in completion, user ownership migration, and remote data sync remain deferred.


## Email Magic Link Callback Handling v1

SOOM now has a callback handling foundation for Email Magic Link and future auth callbacks. `AuthCallbackURL` validates that an incoming URL uses the configured non-placeholder redirect scheme and matches `auth/callback`. `AuthCallbackHandler` then asks the remote auth provider to load the Supabase session from the callback URL and bridge a valid Supabase session into a transient `AuthSession.signedIn` state.

Current boundary:

- Non-auth URLs are ignored.
- Placeholder redirect schemes remain invalid.
- Supabase callback session loading is attempted only when Supabase is configured.
- Local `AuthSessionStore` is not deleted, overwritten, or migrated.
- Production URL scheme registration now uses `CFBundleURLTypes` with `$(SOOM_AUTH_REDIRECT_SCHEME)` and the repository default `soom-auth`.
- Durable callback persistence, user ownership migration, and cloud sync remain deferred.


## Supabase Session Bridge v1

SOOM now maps a read-only `SupabaseAuthSessionSnapshot.signedIn` state into an `AppUser` and transient `AuthSession.signedIn` state through `SupabaseAppUserMapper` and `AuthSessionBridge` only when the Supabase user id is a valid UUID. This lets Settings/My Page show “계정 연결됨” after a Supabase current session is detected.

The bridge does not fetch Supabase profiles, does not persist the remote user into `AuthSessionStore`, and does not migrate HealthKit/workout/route/progression ownership. Signed-out, failed, unconfigured, empty-id, or non-UUID snapshots preserve the local-first session.


## Apple Sign In Real Flow v1

SOOM now includes an executable Apple Sign In path in Settings/My Page. The app enables the Apple Sign In entitlement, uses `SignInWithAppleButton` with `AppleSignInProvider` nonce hashing and credential parsing, and passes the Apple ID token to Supabase through `auth.signInWithIdToken(provider: .apple)`. Tokens are not logged.

A successful Supabase Apple exchange is bridged into transient `AppUser` / `AuthSession.signedIn` UI state. This does not write the remote user into `AuthSessionStore`, does not migrate local workout ownership, and does not sync HealthKit, route, zone, progression, or feed data. Missing Supabase configuration, Apple cancellation, missing token, or exchange failure preserves the local-first session.

Required manual setup remains outside the repository: Apple Developer Sign in with Apple capability, matching app identifier/provisioning profile, and Supabase Apple provider configuration. `SOOM_SUPABASE_URL` and `SOOM_SUPABASE_ANON_KEY` still come from build settings/xcconfig/CI secrets, not committed values.

Operational setup details live in `docs/SOOM_APPLE_SIGNIN_SETUP.md`. The app can validate configured/unconfigured environment state, nonce-required credential readiness, and redirect placeholder behavior, but real Apple Developer, Supabase provider, and TestFlight/device checks must still be performed outside unit tests.

Deferred: explicit user ownership migration, cloud sync, Google OAuth, password auth, Feed ownership migration, HealthKit remote sync, and production callback persistence.

## Supabase Session Persistence v1

SOOM now restores Supabase `currentSession` on app launch through a read-only session restore foundation. `AuthSessionRestorer` first loads the local `AuthSessionStore` session, then checks the remote Supabase session when the policy is `preferRemoteIfAvailable`. A valid remote session can be bridged into transient `AuthSession.signedIn` UI state, while signed-out, failed, unconfigured, or missing remote sessions preserve the local session.

This restore step does not call Supabase sign-out, password login, Apple/Google additions, database profile fetch, server storage, or any ownership migration. Local HealthKit, workout, route, Growth, Recovery, Feed, and progression records remain local-first until a separate explicit sync/migration step exists.


## Root Auth Bootstrap v1

Auth session restore now starts from the app root instead of depending on Settings entry. `SOOMApp` owns the root `AuthViewModel`, injects it through the SwiftUI environment, and runs `RootAuthBootstrap` with the existing read-only restore policy. Settings observes the global auth state and no longer forces a separate restore task when the user opens My Page.

The bootstrap is non-blocking and idempotent: duplicate launch tasks share the active restore path, and failed or missing remote sessions keep the local-first session intact. This still does not migrate local workout ownership, upload HealthKit data, or sync Feed/Recovery/Growth records to a remote account.


## Magic Link Callback Root State Sync v1

Magic Link callback handling now syncs a successful `AuthCallbackResult.sessionBridged` result into the root `AuthViewModel` immediately from `SOOMApp.onOpenURL`. This lets Settings/My Page show the connected account state after a valid callback without waiting for an app relaunch or a later session restore.

Ignored or failed callbacks keep the current local-first session. The callback sync updates transient UI auth state only; it does not write the remote user into `AuthSessionStore`, migrate local workout ownership, upload HealthKit data, or sync Feed/Recovery/Growth records.

## Production Redirect & Device Auth QA v1

Production/device QA uses `soom-auth://auth/callback` as the recommended Email Magic Link callback. The scheme is registered through `CFBundleURLTypes`, while Supabase URL, anon key, Apple private key, and OAuth provider secrets remain outside the repository.

Supabase Dashboard should allowlist `soom-auth://auth/callback` for email magic links. Native Apple Sign In remains separate: it uses Apple credential plus Supabase id-token exchange and does not depend on the email callback URL scheme.

Operational QA details live in `docs/SOOM_DEVICE_AUTH_QA_CHECKLIST.md`.

## Remote Sign-Out & Account Unlink UX v1

SOOM now has a remote account disconnect path for Supabase sessions. When a Supabase account is connected, Settings/My Page can call `SupabaseAuthProvider.signOut()` to end only the remote Supabase auth session, then return the UI to the local-first fallback session.

Current boundary:

- Remote sign-out does not delete local `AuthSessionStore` data.
- Local workout records, settings, HealthKit imports, persisted routes, route privacy settings, Growth, Recovery, Feed, and progression data stay on device.
- If a local user exists, SOOM restores that local session after remote disconnect.
- If no local user exists, SOOM creates the normal local fallback user so the app remains usable.
- Account deletion, server-side data deletion, user ownership migration, cloud sync, and HealthKit remote sync remain deferred.

Settings copy must describe this as “계정 연결 해제”, not account deletion. The confirmation message should make clear that this device's records are preserved.
