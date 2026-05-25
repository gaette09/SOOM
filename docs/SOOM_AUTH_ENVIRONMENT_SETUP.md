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

- Supabase SDK is not installed.
- Supabase network login is not implemented.
- Apple Sign In and Google Sign In are not implemented.
- HealthKit, workout, route, and progression data stay local-first.
- RecoveryCalculator and Growth calculations are unchanged.
