# SOOM External Route Provider Matrix

Date: 2026-07-09

## Summary

SOOM should treat route geometry as required for the premium cycling experience, but it should not assume Apple Health contains route data for every externally sourced workout.

Current finding:

- HealthKit can provide workout summaries and `HKWorkoutRoute` for some workouts.
- Running imports can display routes when HealthKit contains route samples.
- External cycling apps may write summary data to Apple Health without route samples.
- If a source app does not write route geometry to HealthKit, SOOM needs another user-authorized route source.

Recommended strategy:

1. Keep HealthKit as the first route source.
2. Add user-controlled file import next: GPX, then FIT, then TCX.
3. Run Strava and Wahoo feasibility spikes, but do not depend on either as the first production fallback.
4. Treat Garmin as a longer-term developer-program integration.
5. Treat Komoot, Ride with GPS, TrainingPeaks, Decathlon, and Chinese cycling computer apps as provider research and export-path validation.

## Provider Matrix

Legend:

- High: likely available and useful for SOOM route display.
- Medium: available in some cases, dependent on source, permission, tier, or file content.
- Low: unlikely or not the provider's primary route path.
- Review: requires API, partner, legal, or product policy review before implementation.
- Unknown: not confirmed from public documentation; validate in a spike.

| Provider | Route availability | Activity summary availability | Metrics availability | API availability | OAuth / user authorization | Server storage | Difficulty | Priority | Notes / risks |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Apple HealthKit `HKWorkoutRoute` | Medium. Excellent when route samples exist; absent for some external imports. | High via `HKWorkout` and related samples. | Distance high, duration high, speed/pace derived, elevation medium, heart rate medium, cadence/power low unless separately modeled, calories medium. | Native iOS HealthKit only. | HealthKit permission required. | Local-first; iCloud/Supabase sync needs app privacy review. | Medium, mostly implemented. | P0 existing first source. | Cannot read routes that source apps do not write to HealthKit. Keep route fetch optional and non-blocking. |
| GPX file import | High for route coordinates when user has export file. | Low to medium; GPX often has coordinates/timestamps, not rich summary. | Distance derived, duration if timestamps exist, speed/pace derived, elevation optional, heart rate/cadence/power/calories usually low. | No external API needed. | User file selection. | Local storage allowed by SOOM policy; upload only after explicit sync/privacy design. | Low to medium. | P1 first fallback. | Best compliant fallback for missing HealthKit cycling routes. Parse locally and attach only after user confirmation. |
| FIT file import | High for device-recorded activities. | High. | Distance high, duration high, speed/pace high, elevation high, heart rate/cadence/power medium to high when sensors exist, calories medium. | No external API needed for user-selected files; Garmin FIT SDK exists. | User file selection. | Local storage allowed by SOOM policy; server sync needs sensitive route-data review. | Medium to high. | P1/P2 after GPX. | Binary format; choose vetted parser strategy and initially extract route plus safe summary only. |
| TCX file import | High when exported by cycling/running platforms. | Medium to high. | Distance high, duration high, speed/pace derived, elevation medium, heart rate/cadence medium, power medium if present, calories low to medium. | No external API needed for user-selected files. | User file selection. | Local storage allowed by SOOM policy; server sync needs review. | Medium. | P2 after GPX/FIT. | XML parsing is simpler than FIT but richer than GPX. Avoid sampled stream persistence in first pass unless explicitly scoped. |
| Strava OAuth API | Medium to high if API access, scopes, activity visibility, and route/stream availability permit. | High for user-authorized activities. | Distance high, duration high, speed/pace high, elevation high, heart rate/cadence/power/calories medium depending on activity and permissions. | Public API exists with activities, routes, streams, GPX/TCX route export endpoints; policy is restrictive. | OAuth required; users can opt out of scopes. | Review required. Strava user data display/disclosure and deletion constraints apply. | High. | P1 feasibility spike, not first fallback. | No scraping/login automation. Validate activity detail map/polyline and `latlng` streams under current API tier and scopes before implementation. |
| Wahoo Cloud API / Wahoo FIT | Medium. Likely useful through Wahoo-recorded FIT exports; public cloud API details appear gated/unclear. | Medium to high for Wahoo activities/files. | Distance/duration/speed/elevation likely high in FIT; heart rate/cadence/power high if recorded; calories medium. | Public developer entry point exists, but route/workout API details need partner/account validation. | Likely OAuth or account authorization if cloud API exists; user file export otherwise. | Review required for cloud; local file import is simpler. | Medium to high. | P1 feasibility spike; FIT file support benefits Wahoo immediately. | Prioritize Wahoo FIT export/import before cloud integration. Confirm official API access path and terms. |
| Garmin Connect Developer Activity API | High for Garmin-recorded activities; official Activity API advertises FIT/GPX/TCX activity files. | High. | Distance/duration/speed/elevation high; heart rate/cadence/power high when device/sensors record them; calories medium to high. | Official developer program, Activity API, evaluation/approval flow. | End-user consent after approved integration. | Review required under Garmin program terms. | High. | P2/P3 long-term. | Strong route source, but likely slower due developer program approval and cloud-to-cloud architecture. |
| Komoot GPX / partner API | Medium through user GPX export or share/export path; partner API availability unknown. | Low to medium; route planning data may not equal completed workout data. | Route distance/elevation high for planned routes; duration/speed/HR/cadence/power/calories low unless activity recording export includes them. | Public partner API not confirmed for SOOM use. | User file export or partner OAuth if available. | Review required for partner API; user file local import simpler. | Medium for files, high for API. | P2 research. | Good route-planning source, but may not solve recorded workout summary matching. Validate whether the app exports completed activity GPX. |
| Ride with GPS GPX/TCX/API research | High for cycling routes/trips if user data access is approved. | Medium to high for trips/routes. | Distance/elevation high, duration/speed medium, HR/cadence/power/calories unknown and activity-dependent. | Public API docs exist with OAuth preferred and route/trip endpoints. | OAuth preferred; API client required. | Review required against Ride with GPS terms and user authorization. | Medium to high. | P2 research. | Strong cycling fit. Validate whether API exposes recorded trip track points and not only planned routes. |
| TrainingPeaks API/export research | Medium through exports if user can obtain files; direct API availability unclear/publicly partner-oriented. | High for training analysis if accessible. | Distance/duration/speed/elevation medium to high; HR/cadence/power high when recorded; calories medium. | Public developer docs not confirmed; partner path likely required. | User authorization or partner approval required. | Review required. | High. | P2 research. | May be better as file import path than direct API early. Validate user export formats and partner API access. |
| Decathlon / device-app export research | Unknown to medium; depends on app/device export and upload paths. | Medium. | Distance/duration/speed/elevation medium; HR/cadence/power/calories device-dependent. | Unknown. | User authorization or file export. | Review required for API; file import local-first. | Medium to high. | P2 research. | Treat as source-app-specific export validation. If app uploads to Strava/TrainingPeaks/Komoot, SOOM may rely on file export or connected provider. |
| Chinese cycling computer apps via supported upload/export paths | Unknown to high through GPX/FIT/TCX exports; direct APIs vary by vendor. | Medium to high when FIT is available. | Distance/duration/speed/elevation high in FIT; HR/cadence/power high if sensors recorded; calories medium. | Unknown and vendor-specific. | User export or provider OAuth/upload path. | Review required for any vendor API. | Medium for files, high for direct APIs. | P2 research. | Do not scrape app accounts. Document per-vendor export paths and prioritize standard GPX/FIT/TCX ingestion. |

## Provider Recommendations

### Tier 0: Keep HealthKit First

Use HealthKit route data whenever `HKWorkoutRoute` exists:

- It is native to iOS.
- It is already aligned with the current manual read-only HealthKit import path.
- It avoids additional third-party accounts.
- It preserves SOOM’s local-first posture.

Limit:

- HealthKit cannot provide route coordinates that the source app never wrote to Apple Health.

### Tier 1: File Import First

File import should be the first production fallback:

1. GPX v1
2. FIT v1 planning and parser selection
3. TCX v1

Reasoning:

- User-controlled.
- No scraping.
- No login automation.
- No partner approval dependency.
- Solves many cycling-computer and external-app route gaps.
- Fits existing SOOM route persistence.

GPX should ship first because it is the simplest route-only file format. FIT should follow because cycling devices often produce FIT with route and sensor data. TCX should follow or ship beside FIT if XML parser work is lower risk than FIT parser integration.

### Tier 2: OAuth / API Feasibility Spikes

Run feasibility spikes before implementation:

- Strava OAuth API
- Wahoo Cloud API

Spike scope:

- Create developer/test app only.
- OAuth only.
- Validate scopes, rate limits, route geometry, detailed activity fields, stream access, retention/deletion constraints, and display restrictions.
- Do not scrape.
- Do not automate login.
- Do not store data beyond a small user-authorized test unless policy review passes.

Strava should not be the first production fallback because API policy is restrictive and route/stream access may depend on scopes, activity visibility, and current API tier.

Wahoo should be evaluated in parallel because cycling users often record on Wahoo devices, but Wahoo FIT export/import may solve the route problem faster than cloud API work.

### Tier 3: Longer-Term Provider Paths

Garmin:

- Strong long-term candidate because the official Activity API advertises full activity details and activity files.
- Requires developer-program approval and cloud-to-cloud architecture.
- Prioritize after SOOM validates file ingestion and route attachment.

Komoot, Ride with GPS, TrainingPeaks:

- Useful provider research.
- Validate whether SOOM needs completed workout tracks, planned route files, or both.
- Ride with GPS appears promising because public API docs exist and OAuth is preferred.
- Komoot and TrainingPeaks should start with user export/file-path validation.

Decathlon and Chinese cycling computer apps:

- Research upload/export paths first.
- Prefer standard file export or upload-to-supported-provider flows.
- Avoid vendor-specific direct APIs until there is strong user demand and clear official documentation.

## Route Fallback Product Flow

When a HealthKit imported workout has no route:

1. Set explicit route missing state.
2. Keep the workout visible with a clean no-route fallback.
3. Explain that Apple Health did not include route data for this workout.
4. Offer user-controlled actions:
   - Import GPX/FIT/TCX
   - Connect Strava, if feasibility passes
   - Connect Wahoo/Garmin later, if approved integrations exist
   - Skip route for now

Recommended `routeMissingReason` values:

```swift
enum WorkoutRouteMissingReason: String, Codable, Equatable {
    case notChecked
    case healthKitRouteUnavailable
    case healthKitPermissionDenied
    case sourceDidNotProvideRoute
    case routeFetchFailed
    case routeFileImportRequired
    case routeFileInvalid
    case userDeclinedRouteImport
    case providerAuthRequired
    case providerRouteUnavailable
    case providerPolicyBlocked
}
```

Display rules:

- Route exists: show map and route-backed share/detail behavior.
- HealthKit route missing: show no-route fallback plus optional “Add route file”.
- File imported and valid: persist route and reload Activity Detail.
- Provider unavailable or policy-blocked: explain that route import is not available from that provider yet.
- User skips: keep no-route fallback without repeated interruption.

## Storage And Privacy Strategy

Route data is sensitive location data.

Rules:

- Store only user-authorized route data.
- Keep file import local-first by default.
- Do not upload route coordinates to Supabase until route privacy, deletion, sync, and account ownership semantics are explicit.
- Do not store provider credentials in route records.
- Store OAuth tokens only in secure server-side storage if a server integration is approved.
- Provide disconnect and delete behavior for provider-linked routes.
- Preserve route source metadata for debugging and user trust.

Recommended route source metadata:

```swift
enum WorkoutRouteOrigin: String, Codable, Equatable {
    case healthKit
    case gpxFile
    case fitFile
    case tcxFile
    case strava
    case wahoo
    case garmin
    case komoot
    case rideWithGPS
    case trainingPeaks
    case decathlon
    case externalDeviceApp
}
```

Recommended route import fields:

- `workoutId`
- `routeOrigin`
- `externalProviderActivityId`
- `originalFilenameHash`
- `coordinateCount`
- `routeDistanceMeters`
- `summaryDistanceMeters`
- `importedAt`
- `userConfirmedAt`
- `parserVersion`
- `authorizationScopeSnapshot`
- `deleteByProviderDisconnect`

## Metrics Strategy

Phase 1 file/API fallback should treat route geometry as the primary goal.

Safe v1 metrics:

- distance
- duration
- speed/pace derived from distance and duration
- elevation if present
- start/end timestamps if present

Deferred metrics unless the existing read model safely supports them:

- heart rate streams
- cadence streams
- power streams
- calorie recomputation
- lap/segment details
- moving time from samples

Rules:

- Do not fake missing metrics.
- Preserve imported HealthKit summary as the workout summary unless user explicitly replaces it.
- Store route-derived distance separately when it differs from summary distance.
- Use route-derived distance as fallback only when summary distance is missing or clearly unavailable.

## Recommended Next Implementation

1. `routeMissingReason` model

- Add explicit missing route state for HealthKit imported workouts.
- Keep Activity Detail no-route fallback stable.
- Add tests for route exists, HealthKit route missing, permission denied, and user skipped.

2. GPX Import v1

- User selects GPX.
- Parse coordinates locally.
- Validate route.
- Attach route to selected imported workout.
- Persist through existing route persistence.
- Reload Activity Detail/Share route display.

3. FIT Import v1 planning

- Select parser strategy.
- Define route-only extraction from FIT.
- Validate Wahoo/Garmin/bike-computer sample files.

4. Strava OAuth feasibility spike

- Validate current scopes, API tier, activity detail, map/polyline, and `latlng` streams.
- Review server storage/display/deletion constraints.
- Stop if route access or policy constraints do not support SOOM’s product requirements.

5. Wahoo feasibility spike

- Validate public/partner cloud API availability.
- Validate Wahoo FIT export path.
- Prefer FIT file import if cloud API is unavailable or slow to approve.

## Explicit Non-Goals

- No scraping.
- No login automation.
- No bypass of platform API limitations.
- No private activity bypass.
- No storing provider data without user authorization.
- No public display of provider activity data to other users.
- No AI model training using provider API data.
- No HealthKit write-back.
- No background sync in this planning phase.
- No route smoothing/snapping in route import v1.
- No sampled stream persistence in initial route fallback implementation.

## Source Notes

Official/public references reviewed:

- Apple HealthKit `HKWorkoutRoute`: `https://developer.apple.com/documentation/healthkit/hkworkoutroute`
- Apple HealthKit route reading: `https://developer.apple.com/documentation/healthkit/reading-route-data`
- Strava API reference: `https://developers.strava.com/docs/reference/`
- Strava OAuth docs: `https://developers.strava.com/docs/authentication/`
- Strava API agreement: `https://www.strava.com/legal/api`
- Garmin Connect Developer Program overview: `https://developer.garmin.com/gc-developer-program/overview/`
- Garmin Connect Activity API: `https://developer.garmin.com/gc-developer-program/activity-api/`
- Garmin FIT SDK: `https://developer.garmin.com/fit/overview/`
- Wahoo developer entry point: `https://developer.wahooligan.com/`
- Ride with GPS API docs: `https://ridewithgps.com/api`

Research caveat:

- Komoot, TrainingPeaks, Decathlon, and Chinese cycling computer app paths need provider-specific validation. Until official API/export docs and terms are confirmed for SOOM’s use case, treat them as file/export research rather than approved direct integrations.
