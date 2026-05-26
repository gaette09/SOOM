# SOOM Apple Sign In Setup

## Purpose

This checklist validates whether SOOM is operationally ready for Apple Sign In with Supabase Auth. It is not a promise that local HealthKit, workout, route, Growth, Recovery, or Feed data has moved to a remote owner. The app remains local-first unless a later migration/sync step is explicitly built.

## Current App State

- Bundle identifier: `app.soom.prototype`
- Entitlements file: `SOOM/SOOM.entitlements`
- App target capability: Sign In with Apple is enabled in the Xcode project.
- HealthKit entitlement remains unchanged.
- Supabase Swift SDK is installed and isolated behind auth providers/client providers.
- Apple Sign In uses `SignInWithAppleButton` and exchanges the Apple ID token with Supabase through `signInWithIdToken(provider: .apple)` when Supabase is configured.
- Raw nonce is required before Supabase exchange. Missing or empty nonce blocks exchange.
- Tokens, authorization codes, Supabase URL, anon key, Apple private key, and OAuth secrets must not be logged or committed.

## Apple Developer Configuration

Required outside the repository:

1. Confirm the Apple Developer team owns the app identifier for `app.soom.prototype` or the production bundle id.
2. Enable **Sign in with Apple** for the app identifier.
3. Regenerate or refresh provisioning profiles after enabling the capability.
4. Verify the Xcode target uses the matching team and provisioning profile.
5. For TestFlight/production, confirm the final production bundle id has the same capability enabled.

Associated Domains are not required for the direct in-app Apple credential flow currently used by SOOM. Add Associated Domains only if a future web callback, universal link, or web-to-app auth flow requires it.

## Supabase Apple Provider Configuration

Required in the Supabase dashboard:

1. Enable the Apple provider.
2. Configure Apple Team ID.
3. Configure Services ID or client identifier according to the Supabase Apple provider requirements.
4. Configure Key ID and Apple private key in Supabase secrets/dashboard only.
5. Confirm the callback URL shown by Supabase is registered where Apple expects it.
6. Keep Apple private key and provider secrets out of the repository.

Do not commit Apple private keys, `.p8` files, OAuth client secrets, or real Supabase keys.

## Supabase Environment Values

SOOM expects these values through Xcode build settings, ignored `.xcconfig` files, or CI secrets:

- `SOOM_SUPABASE_URL`
- `SOOM_SUPABASE_ANON_KEY`
- `SOOM_AUTH_REDIRECT_SCHEME` for email magic link and future callback work

Current `Info.plist` entries intentionally keep placeholders:

- `SOOMSupabaseURL = $(SOOM_SUPABASE_URL)`
- `SOOMSupabaseAnonKey = $(SOOM_SUPABASE_ANON_KEY)`
- `SOOMAuthRedirectScheme = $(SOOM_AUTH_REDIRECT_SCHEME)`

Placeholder-like values such as `$(...)`, `replace_me`, `your_...`, and `placeholder` are treated as unconfigured by the app.

## Redirect Strategy

Current Apple Sign In uses the native Apple credential and Supabase id-token exchange. It does not require the Email Magic Link callback scheme for the Apple button flow.

Email Magic Link and future OAuth callback handling may use:

`soom-auth://auth/callback`

Current state:

- Redirect scheme can be loaded from `SOOMAuthRedirectScheme`.
- Placeholder redirect schemes are ignored.
- `CFBundleURLTypes` is registered through `$(SOOM_AUTH_REDIRECT_SCHEME)`.
- The repository default scheme is `soom-auth`, and dev builds may override it with ignored local build settings.
- The app has an `onOpenURL` callback handling foundation for Email Magic Link/future OAuth URLs once a real scheme is registered.
- Durable callback persistence remains deferred.

Do not change the production scheme without confirming the Supabase redirect allowlist and iOS URL handling plan.

## Runtime Smoke Checklist

Use this checklist for local/dev validation:

1. Build and run the app with placeholder values. Expected: local-first mode, Apple card visible, Supabase environment shown as not configured.
2. Inject development Supabase URL and anon key through local build settings or ignored `.xcconfig`. Expected: Supabase environment shows configured.
3. Confirm Apple Sign In entitlement is present in the built app entitlement output.
4. Tap Apple Sign In on a real device or signed simulator environment if supported. Expected: Apple credential flow starts only when Apple capability/provisioning is valid.
5. Confirm Supabase Apple provider is enabled. Expected: configured exchange can create a Supabase Auth session.
6. After session bridge success, Settings may show `계정 연결됨`.
7. Confirm local workouts, HealthKit imports, routes, zones, progression, Feed, Recovery, and Growth records remain local and are not uploaded or migrated.

## Simulator And TestFlight Notes

- Unit tests do not automate Apple credential UI or real Apple/Supabase network auth.
- Simulator behavior may differ from physical device behavior for Apple ID state, provisioning, and credential prompts.
- TestFlight or physical device QA is required before calling the flow production-ready.
- A successful auth session is still only an account connection state in SOOM v1, not cloud sync.

## TestFlight QA Checklist

- App launches with configured Supabase environment.
- Apple button appears in Settings/My Page.
- Apple prompt appears and can be cancelled without breaking local user state.
- Missing/invalid Supabase configuration returns a soft error and preserves local session.
- Successful Apple exchange shows account connected state.
- Reopening Settings can read current session through the existing session smoke/bridge path.
- Local workout library, route maps, zone cards, progression, Recovery, and Growth remain available after auth success/failure.
- No token, authorization code, private key, or Supabase key appears in logs.

## Deferred Items

- Production callback/deep-link persistence and QA hardening.
- Supabase profile table or DB profile fetch.
- Remote workout ownership migration.
- HealthKit, route, zone, progression, Recovery, Growth, or Feed cloud sync.
- Google Sign In and password auth.
