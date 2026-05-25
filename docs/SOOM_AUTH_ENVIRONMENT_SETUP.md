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
- Supabase network login is not implemented.
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
- Email login UI is not implemented.
- Supabase Auth sign-in, OAuth, session refresh, and remote profile loading are not implemented.
- Apple and Google OAuth redirect handling remains a future step.
- Local-first Auth remains the default app behavior.


## Supabase Email Session Smoke v1

SOOM now has a read-only Supabase auth session smoke path. `SupabaseAuthSessionProbe` asks `SupabaseClientProvider` for a configured client and reads the current Supabase auth session when one is available. It does not call sign-in, sign-up, sign-out, OAuth, or server storage APIs.

Session smoke states are intentionally limited:

- `unconfigured`: Supabase URL/key placeholders are missing or still placeholder-like.
- `signedOut`: the client is configured, but no local Supabase session is present.
- `signedIn`: a current Supabase session exists and can expose user id/email for smoke visibility.
- `failed`: session lookup failed without changing the local SOOM session.

If the environment is unconfigured, the app remains local-first. A failed smoke check must not replace `AuthSessionStore`, migrate `user_id`, upload HealthKit/workout data, or imply that login UI is active. Email login UI, OAuth, session sync, and remote profile ownership remain deferred.
