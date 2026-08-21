# SOOM Known Issues

Purpose: track known deferred work for internal TestFlight so expected limitations do not look like accidental regressions.

## Current Deferred Items

### AQI Provider Upgrade

Weather has fallback-first behavior and OpenWeather foundation. AQI/provider sophistication remains deferred.

### Club Ranking Engine

Club rankings have domain/service/UI foundation. Real ranking calculation from workout data is deferred.

### Club Challenge Engine

Challenge catalog and remaining-action copy exist. Real progress calculation engine is deferred.

### HealthKit Write

Record save is local-first. Writing completed workouts back to HealthKit is deferred.

### Background GPS Smoothing

Record route capture stores active-session coordinates. Background GPS, smoothing, filtering, and reconnect behavior are deferred.

### Direct Instagram Story Integration

Share uses image export and iOS share sheet guidance. Direct Instagram Story API integration is deferred.

### Club Staging Migration

Club Supabase migration is prepared and hardened but not yet applied to production. Staging smoke test is required first.

### Recovery Load Estimate Heart-Rate Default

Confirm before public launch. `estimateRelativeEffort`/`estimateTrainingLoad` (`ProcessedWorkoutToRecoveryActivityMapper.swift`, `UnifiedWorkoutToRecoveryActivityMapper.swift`, and the other two mapper copies carrying the same TODO) fall back to `averageHeartRate ?? 120` when a workout has no heart rate data, instead of treating missing heart rate as zero contribution. Every workout recorded without a paired Watch/HR sensor — which is every workout recorded in the Simulator, and any device-only Record session — always hits this default, so a zero-effort workout still reports a small nonzero effort/load (e.g. relativeEffort 16, trainingLoad 15 for a 0-duration, no-data activity) instead of near-zero. Output stays inside the existing clamp bounds ([1,100] / [5,180]), so it is not a launch blocker, but it is a real logic gap, not just an estimation-accuracy nit — worth fixing alongside the existing TRIMP/HR-zone TODOs (`RecoveryCalculator.swift:225`, `RecoveryActivityMapper.swift:131`, `HealthKitRecoveryActivityMapper.swift:55`, `UnifiedWorkoutToRecoveryActivityMapper.swift:56`).

### Record Launch Guidance Copy Not Score-Driven

`RecordLaunchRecommendation.title`/`.subtitle` on the Record screen ("오늘은 가볍게 이어가도 좋아요" / "Z2 라이딩 40분 또는 가벼운 조깅을 추천해요") are fixed copy independent of the recovery score. The score/label itself (`recoveryLabel`, e.g. "회복 72 · 데이터 부족") is now computed from real SwiftData workout history and matches Feed's Recovery Insight card and the Recovery detail screen, but the coaching copy underneath it does not change with that score — a low score would still show upbeat "가볍게 이어가도 좋아요" guidance. Would need a score-to-copy mapping (similar to `RecoveryCalculator.recommendation(score:...)`) to close.

### Supabase Misconfiguration Crashes Instead of Degrading

Found 2026-08-19 while wiring real Supabase credentials for the feed-public-fetch round-trip test. `SupabaseAuthConfiguration.isConfigured` only checks `projectURL != nil` — it does not validate that the URL has a host. `AuthEnvironmentLoader.supabaseURL()` builds `projectURL` with a plain `URL(string:)`, which is lenient enough to succeed even for a hostless string like `"https:"`. `SupabaseClientProvider.makeClient()` then passes that URL straight into `SupabaseClient(supabaseURL:supabaseKey:)`, which fatal-errors ("supabaseURL must have a valid host") instead of throwing or returning nil. The specific trigger that surfaced this — an un-escaped `https://...` value in `Config/LocalSecrets.xcconfig` getting truncated to `https:` because xcconfig treats `//` as a comment start — is fixed (see `SOOM_LOCAL_SECRETS_SETUP.md`), but the underlying app-level gap remains: unlike Mapbox/OpenWeather, which both degrade to a fallback surface on any bad/missing config, a malformed-but-present Supabase URL crashes the whole app at launch. Worth hardening `isConfigured` (or `SupabaseClientProvider.makeClient()`) to validate `projectURL.host != nil` before constructing the client, so future misconfiguration degrades like every other integration in this app instead of crashing.

### Share-to-Feed Success Is Indistinguishable From Local-Only Fallback

`RecordShareDraftCoordinator.handle(.shareToFeed:)` (feed-write-path, 2026-08-19) tries a real Supabase insert first and silently falls back to the pre-existing local-only draft file on any failure — no session (the common case today, since Supabase sign-in completion isn't implemented yet), RLS rejection, network loss. This was a deliberate design choice so share-to-feed never becomes less reliable than it was before this batch, and it's been verified end-to-end: RLS/FK rejection produce clean catchable errors (not crashes, confirmed against the real project), and a no-session attempt correctly falls through to a local save with zero data loss (confirmed via real execution: `draftReturned=true localDraftsWritten=1`). The gap is UX transparency, not correctness: `RecordView` shows the same "피드에 공유했어요" success completion either way, so a user (or a future silent RLS misconfiguration) has no way to tell from the UI whether a share actually reached the server or only saved to the device. Not a blocker — this exactly matches pre-batch behavior, where every share was local-only and shown as success. Worth reconsidering once there's a real sign-in flow and "posted online" starts being the common case rather than the rare one.

### Imported Workout Library List Not Source-Filtered

Found 2026-08-19 while fixing Activity tap-routing (`ia-fix-q4-workout-source-distinction`). `UnifiedWorkoutLibraryViewModel.loadRecentWorkouts()` fetches every `UnifiedWorkout` regardless of `source`, so the "가져온 운동 기록" (imported workout library) screen lists direct-Record (`.soomLocal`) workouts alongside real HealthKit imports — confirmed live: a seeded `.soomLocal` workout showed up there tagged "SOOM" next to a `.appleHealthKit` one. The Q4 fix only corrected which screen a workout *routes to* when tapped from Activity's "최근 운동" list; it did not touch what this library screen itself lists. Not fixed this round — deferred.

### Growth/Weakness Insight Not Using Real Pace Samples

Found 2026-08-19 while wiring real chart/split data (`ia-fix-q2-chart-data-wiring`). `WorkoutGrowthSummaryBuilder`/`WorkoutWeaknessInsightBuilder` are called from `DetailViews.swift` with `workout` (the base `Workout(unifiedWorkout:)` value, whose `.samples` is still hardcoded empty) rather than the `effectiveWorkout` that now carries real route-derived pace samples for chart/split rendering. Not a regression — these builders always saw empty samples before this batch too, so their sample-count-gated logic (late-pace-drop, endurance-drop detection, etc.) still takes the same "insufficient data" fallback path as before. Just an opportunity left on the table: now that real pace samples exist, these insights could use them. Not fixed this round — deferred.

### Distance-Axis Charts Have No Comparison Overlay

Found 2026-08-21 while building the shared distance-axis chart component (`WorkoutDistanceChartCard`, feed-detail-migration-plan.md batch 3). The PDF reference shows a gray comparison overlay behind Power/HR/Speed/Cadence (a prior-effort or rolling-average line) — SOOM has no data source for this concept anywhere (no stored "comparison workout" or rolling baseline), so `WorkoutDistanceChartCard` renders only the primary series. Not fixed this round — revisit in batch 5 or a separate track once a comparison-data source is designed.

### Growth-Comparison Sections Silently Empty on "활동 탭 최근 운동" Path

Found 2026-08-22 while scoping the Relative Effort batch (feed-detail-migration-plan.md). `RootTabView`'s `.directWorkout` case constructs `UnifiedWorkoutDetailDestination` without a `similarCandidateProvider` (defaults to `nil`) and never passes `comparisonWorkouts` to `WorkoutDeepDetailView` either (defaults to `[]`). Both `comparisonInsight`/`courseRecord`/`courseProgression` (gated by `similarCandidateProvider`) and `growthMetrics`/`growthSummary`/`weaknessInsight` (which fall back to `comparisonWorkouts.isEmpty ? [workout] : comparisonWorkouts`, i.e. compare the workout against itself) are affected — no error, no placeholder, the `.growth` section just renders emptier/more trivial than it should. `UnifiedWorkoutLibraryViewContainer`'s path (운동 라이브러리 screen) wires `similarCandidateProvider` correctly and doesn't have this gap. Not fixed this round — Relative Effort was deliberately built on an independent data path (`RelativeEffortHistoryProviding`) specifically to avoid inheriting this gap, rather than fixing it. Worth fixing `RootTabView`'s call site to wire `similarCandidateProvider`/`comparisonWorkouts` properly, since it's the primary "최근 운동" entry point.

### Club's Fallback Pattern Is Reimplemented Independently From Feed

Found 2026-08-20 during a full-app sweep (Club/Settings/onboarding) using the same criteria as the IA fix batches. `ClubDomainFoundation.swift`'s `SupabaseClubService`/`FallbackClubService`/`InMemoryClubService` reimplement the same "try remote, fall back to local persistence on failure" shape that `FeedDataSource`/`FeedShareDraftStore` already established for Feed — built independently rather than sharing a common abstraction. Both work correctly today (confirmed live during the sweep), so this is not a bug — just duplicated design that's likely to repeat again the next time a feature needs the same remote-with-local-fallback shape. Not refactored this round — deferred, revisit if a third feature needs the same pattern.

## Resolved

### Unguarded Dev Recovery Preview Screens (resolved 2026-08-20)

`HealthKitSettingsView.swift` exposed two dev-only Recovery comparison screens (`HealthKitRecoveryPreviewViewContainer`, `RecoveryRealDataPreviewViewContainer`) via plain `NavigationLink`s with no `#if DEBUG` guard, reachable by any user in release builds. Fixed by wrapping both the call sites and the property declarations in `#if DEBUG`. Same pass also caught and fixed the identical pattern on `SettingsView.swift`'s `prototypeSection` (Strava Frame Lock prototype entry), found during the 2026-08-20 sweep.

## Not Blockers For Internal TestFlight

- Local-first fallback when remote services are unavailable.
- Time-only workouts when location is denied.
- Share through iOS share sheet instead of direct Story API.
- Club ranking/challenge data shown as foundation until staging backend is validated.

## Watch Closely

- Share export on real devices.
- Location denial copy and time-only save copy.
- Club RLS behavior after staging migration.
- Profile aggregation for users with only time-based workouts.
