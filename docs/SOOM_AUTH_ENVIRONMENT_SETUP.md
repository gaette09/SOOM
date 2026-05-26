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

Apple and Google OAuth will need an iOS redirect/scheme policy before implementation. v1 documents the expected placeholder but does not add a concrete OAuth flow, OAuth SDK, or URL callback handler. If `CFBundleURLTypes` is added later, the scheme must be injected from configuration and reviewed so it does not expose secrets or imply login is already active.

## Current Boundary

- Supabase Swift SDK is installed as a foundation dependency.
- Supabase sign-in completion and session ownership migration are not implemented.
- Apple Sign In and Google Sign In are not implemented.
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

If the environment is unconfigured, the app remains local-first. A failed smoke check must not replace `AuthSessionStore`, migrate `user_id`, upload HealthKit/workout data, or imply that completed login/session sync is active. Email Magic Link request UI exists, and a read-only session bridge can show an existing Supabase session as connected. OAuth, session sync, remote profile ownership, and data migration remain deferred.


## Supabase Email Auth UI v1

Settings/My Page now includes a low-pressure email auth request surface. The UI can ask the configured Supabase client to send a magic link/OTP email through `SupabaseAuthProvider.requestMagicLink(email:redirectTo:)`. This is an auth request only; a separate read-only bridge can represent an existing Supabase session in the current UI, but it does not write that user into SOOM's local `AuthSessionStore`.

Current boundary:

- Email format is validated before a request is sent.
- Supabase must be configured through environment/build settings; placeholder values keep the flow safely unavailable.
- `signInWithOTP` is used only for magic link/OTP request and starts with `shouldCreateUser: false` because explicit signup UI is still deferred.
- Redirect URL is optional. If `SOOM_AUTH_REDIRECT_SCHEME` is configured, SOOM can prepare `scheme://auth/callback`; `CFBundleURLTypes` and deep-link session handling remain future work.
- Password login, signup UI, Apple/Google OAuth, sign-in completion, user ownership migration, and remote data sync remain deferred.


## Supabase Session Bridge v1

SOOM now maps a read-only `SupabaseAuthSessionSnapshot.signedIn` state into an `AppUser` and transient `AuthSession.signedIn` state through `SupabaseAppUserMapper` and `AuthSessionBridge`. This lets Settings/My Page show “계정 연결됨” after a Supabase current session is detected.

The bridge does not fetch Supabase profiles, does not persist the remote user into `AuthSessionStore`, and does not migrate HealthKit/workout/route/progression ownership. Signed-out, failed, or unconfigured snapshots preserve the local-first session.
