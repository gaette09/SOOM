# SOOM 0010 Record Map Blocker

Date: 2026-06-25

## Summary

Physical TestFlight QA found that the Record screen map is not rendering as a real map. This is a release blocker.

The Record map is implemented with Mapbox, not MapKit. It intentionally falls back to a custom lightweight placeholder surface when a usable Mapbox public token is not available. The current Release/TestFlight path does not appear to inject `MBX_ACCESS_TOKEN`, so the processed app `Info.plist` has an empty `MBXAccessToken` value and Record renders fallback UI instead of a real map.

## Findings

### 1. File that renders the Record map

The Record screen renders the map from:

- `SOOM/Features/Activity/RecordView.swift`
- `SOOM/Features/Activity/RecordMapView.swift`

`RecordView` places `RecordMapView` as the full-screen base layer:

- `RecordView.swift`: `RecordMapView(...)` is created in the root `ZStack`.
- `RecordMapView.swift`: decides between Mapbox and fallback rendering.

### 2. MapKit, Mapbox, or placeholder/custom

Record uses Mapbox:

- `RecordMapView.swift` imports `MapboxMaps`.
- `RecordMapboxSurface` creates a `MapboxMaps.MapView`.
- The map style is `styleURI: .light`.
- Route and location visuals are custom Mapbox annotations on top of the Mapbox base map.

Record does not use MapKit for this surface.

Record also has a custom fallback:

- `RecordMapView.shouldRenderMapbox` returns `accessTokenAvailable`.
- If false, `RecordMapFallbackSurface` is rendered instead.
- Fallback reason is `missing-or-unusable-mapbox-token`.

### 3. Why TestFlight/device does not show a real map

The likely direct cause is missing Mapbox token injection in Release/TestFlight.

Evidence:

- `SOOM/Info.plist` defines `MBXAccessToken` as `$(MBX_ACCESS_TOKEN)`.
- `MapboxAccessTokenAvailability` reads `MBXAccessToken` from `Info.plist`, then environment variables `MBX_ACCESS_TOKEN` and `MAPBOX_ACCESS_TOKEN`.
- `MapboxAccessTokenAvailability.isUsableToken` rejects nil, empty strings, unresolved `$(...)` values, placeholders, and `your_*` values.
- `RecordMapView` renders Mapbox only when `MapboxAccessTokenAvailability.hasUsableToken` is true.
- The existing local IPA at `build/SOOM.ipa` has `CFBundleVersion = 2` and `MBXAccessToken = ""`.
- Sanitized build-setting check:
  - Debug reports `MBX_ACCESS_TOKEN_CONFIGURED=1`.
  - Release did not report a configured `MBX_ACCESS_TOKEN`.
- Project settings show the app target Debug configuration uses `SOOM/Config/Debug.xcconfig`, while the app target Release configuration has no `baseConfigurationReference`.
- `SOOM/Config/Debug.xcconfig` optionally includes ignored `LocalSecrets.xcconfig`, which can supply local Mapbox credentials. Release does not currently read that config path by default.

This explains simulator-vs-TestFlight divergence: Debug simulator can receive local `MBX_ACCESS_TOKEN`, while Release/TestFlight does not unless the archive command, CI, Xcode Cloud, or release build settings explicitly inject it.

Location permissions are probably not the cause of the blank/non-real map:

- `NSLocationWhenInUseUsageDescription` is present in `Info.plist`.
- Record intentionally does not request location permission on entry.
- Mapbox base-map rendering is gated by token availability, not by location permission.
- Without location permission, a real Mapbox base map should still render around the fallback/sample area when the token is valid.

No Mapbox entitlement was found or expected. The required release input is a valid Mapbox public access token, not an iOS entitlement.

### 4. Whether Activity detail map is affected

Yes, likely.

Activity detail and feed route previews use the same Mapbox token gate:

- `SOOM/Features/Workout/WorkoutDetailMapView.swift`
- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOM/Components/FeedItemCard.swift`

`WorkoutDetailMapView.hasRenderableMap` requires both:

- route coordinates count >= 2
- `MapboxAccessTokenAvailability.hasUsableToken`

If the Release/TestFlight app lacks `MBXAccessToken`, Activity detail route maps and feed route previews will fall back even when route data exists. This is separate from route persistence: route data can be present while the real map base layer is unavailable.

Share/static route previews are also token-sensitive:

- `MapboxStaticRouteURLBuilder` reads `MBXAccessToken`.
- Without a token, `StaticRoutePreviewBuilder` keeps `routeExists = true` but returns `imageURL = nil`, producing fallback visuals instead of Mapbox static images.

### 5. Minimum safe fix

Minimum safe fix for release:

1. Inject a valid Mapbox public access token into the Release/TestFlight build as `MBX_ACCESS_TOKEN`.
2. Keep the token out of committed source files and docs.
3. Verify the archived app's processed `Info.plist` has a non-empty, non-placeholder `MBXAccessToken`.

Implementation options:

- Add a release-only, ignored xcconfig and configure the Release target or archive command to use it.
- Pass `MBX_ACCESS_TOKEN` through the archive/export environment or CI/App Store Connect/Xcode Cloud secret injection.
- Add a fail-fast release archive check that fails when `MBX_ACCESS_TOKEN` is missing, empty, unresolved, or placeholder-like.

Do not fix this by committing a real token to `Info.plist`, `project.pbxproj`, source files, or docs.

Optional follow-up hardening:

- Add a release-readiness script that inspects the processed archive `Info.plist` and prints only `MBX_ACCESS_TOKEN_CONFIGURED=true/false`.
- Add a visible QA/debug-only map mode indicator for internal builds, without exposing token values.
- Consider whether Activity detail should degrade differently from Record when the Mapbox token is missing, but do not hide this release blocker.

### 6. Verification steps

Pre-archive verification:

```sh
xcodebuild -project SOOM.xcodeproj -scheme SOOM -configuration Release -showBuildSettings \
  | awk 'index($0, "MBX_ACCESS_TOKEN =") {value=$0; sub(/^.*= /, "", value); configured=(value != "" && value !~ /^\$\(/ && value !~ /your_mapbox_token_here/); print "MBX_ACCESS_TOKEN_CONFIGURED=" configured}'
```

Expected:

```text
MBX_ACCESS_TOKEN_CONFIGURED=1
```

Archive/IPA verification, without printing the token:

```sh
unzip -p build/SOOM.ipa Payload/SOOM.app/Info.plist \
  | plutil -p - \
  | awk '/MBXAccessToken/ {configured=($0 !~ /=> ""/ && $0 !~ /\$\(/ && $0 !~ /your_mapbox_token_here/); print "MBX_ACCESS_TOKEN_CONFIGURED=" configured}'
```

Expected:

```text
MBX_ACCESS_TOKEN_CONFIGURED=1
```

Device/TestFlight QA:

1. Install the same TestFlight build being evaluated.
2. Open Record.
3. Confirm a real Mapbox base map appears, not the lightweight fallback/drawn placeholder.
4. Tap current-location control and grant When In Use permission.
5. Confirm map recenters to the physical device location.
6. Start a short outdoor recording with real GPS.
7. Confirm route/location overlay remains visible while recording.
8. Save the workout.
9. Open the saved Activity detail.
10. Confirm Activity detail renders a real route-backed Mapbox map.
11. Force quit and relaunch.
12. Reopen the saved workout and confirm the real map and route still render.
13. Check feed route preview and share/static preview behavior if route preview is part of the release gate.

## Release Decision

BLOCKED.

SOOM 0010 cannot pass the physical TestFlight release gate until the Release/TestFlight build includes a usable Mapbox public token and Record plus Activity detail are verified on device with real map rendering.
