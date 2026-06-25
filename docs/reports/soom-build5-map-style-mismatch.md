# SOOM Build 5 Map Style Mismatch Investigation

Date: 2026-06-26
Build under investigation: TestFlight Build 5
Expected Mapbox style: `mapbox://styles/gaette09/cmqtub3xc004m01rg7s331tq2`

## Summary

Build 5 contains the shared SOOM Mapbox style configuration, and the Record screen uses it through the intended path.

The Feed route preview and Activity Detail map do not have independent style configuration. Both render through `WorkoutDetailMapView`, so the physical TestFlight mismatch points to the shared detail/feed live-map path, not to a separate feed static-map style literal.

The static image URL builder is already configured to use the SOOM style ID for newly generated static URLs. Any static route image that still appears with an old/default style is most likely coming from a stale URL/cache or a surface that is not actually using the static URL builder.

## Files Inspected

- `SOOM/Features/Workout/SOOMMapboxConfiguration.swift`
- `SOOM/Features/Activity/RecordMapView.swift`
- `SOOM/Features/Workout/WorkoutDetailMapView.swift`
- `SOOM/Features/Workout/MapboxStaticRouteURLBuilder.swift`
- `SOOM/Features/Workout/StaticRoutePreviewBuilder.swift`
- `SOOM/Features/Workout/ShareableWorkoutCardBuilder.swift`
- `SOOM/Components/FeedItemCard.swift`
- `SOOM/Components/ShareableWorkoutCardView.swift`
- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOM/Features/Workout/WorkoutDetailMapOverlay.swift`
- `SOOM/Features/Feed/FeedPostDTO.swift`
- `SOOM/Features/Feed/FeedShareDraft.swift`
- `SOOMTests/MapboxStaticRouteURLBuilderTests.swift`
- `SOOMTests/StaticRoutePreviewBuilderTests.swift`
- `SOOMTests/ShareableWorkoutCardBuilderTests.swift`

## Findings

### 1. Why Record Uses the Shared Style Correctly

`RecordMapView` renders its Mapbox surface through `RecordMapboxSurface`.

`SOOM/Features/Activity/RecordMapView.swift` creates a `MapView` with:

- `MapboxAccessTokenAvailability.configureMapboxOptionsIfNeeded()`
- `MapInitOptions(cameraOptions: ..., styleURI: SOOMMapboxConfiguration.styleURI)`

Relevant lines:

- `RecordMapView.swift:95`
- `RecordMapView.swift:97`
- `RecordMapView.swift:99`
- `RecordMapView.swift:107`

This path gives Mapbox both the initial camera and the SOOM style URI at map construction time. The TestFlight observation that Record uses the custom style confirms the Release token and the shared style URI are present and usable on device.

### 2. Why Feed Static Route Map Still Looks Old/Default

The feed card route preview is not using the static image URL builder in the inspected runtime path.

`FeedReferenceMediaPreview` creates a synthetic route via `FeedPreviewRouteFactory.route(...)`, then `FeedReferenceRoutePreview` renders:

```swift
WorkoutDetailMapView(route: route, fallbackStyle: routeStyle, tint: tint)
```

Relevant lines:

- `FeedItemCard.swift:257`
- `FeedItemCard.swift:261`
- `FeedItemCard.swift:371`

Feed DTO and draft mapping also intentionally set `StaticRoutePreview.imageURL` to `nil`:

- `FeedPostDTO.swift:127`
- `FeedPostDTO.swift:128`
- `FeedShareDraft.swift:41`
- `FeedShareDraft.swift:42`

So the feed symptom is not caused by a hardcoded static Mapbox style in the feed card. It is the same live `WorkoutDetailMapView` issue seen on Activity Detail, or a fallback/synthetic preview being mistaken for a static Mapbox image.

For share-card static images, the builder is already pointed at the SOOM style:

- `SOOMMapboxConfiguration.staticImagesStyleID = "gaette09/cmqtub3xc004m01rg7s331tq2"`
- `MapboxStaticRouteURLBuilder` defaults to `SOOMMapboxConfiguration.staticImagesStyleID`
- generated URLs use `https://api.mapbox.com/styles/v1/\(style)/static/...`

Relevant lines:

- `SOOMMapboxConfiguration.swift:5`
- `SOOMMapboxConfiguration.swift:6`
- `MapboxStaticRouteURLBuilder.swift:7`
- `MapboxStaticRouteURLBuilder.swift:9`
- `MapboxStaticRouteURLBuilder.swift:31`
- `MapboxStaticRouteURLBuilder.swift:33`

No runtime call site was found passing an old style ID into `StaticRoutePreviewBuilder` or `MapboxStaticRouteURLBuilder`. The only explicit `mapbox/light-v11` usage found is a unit test override in `MapboxStaticRouteURLBuilderTests`.

### 3. Why Activity Detail Map Still Looks Old/Default

Activity Detail renders through `WorkoutDetailMapView`:

- `WorkoutDetailContent.swift:348`
- `WorkoutDetailMapOverlay.swift:9`

`WorkoutDetailMapView` creates a Mapbox `MapView` with:

```swift
MapInitOptions(styleURI: SOOMMapboxConfiguration.styleURI)
```

Relevant lines:

- `WorkoutDetailMapView.swift:45`
- `WorkoutDetailMapView.swift:47`
- `WorkoutDetailMapView.swift:49`

Unlike Record, this path does not pass initial camera options into the same initializer, and it does not explicitly reapply or verify the style after the MapView is created. Its update path only reconfigures route annotations and camera:

- `WorkoutDetailMapView.swift:55`
- `WorkoutDetailMapView.swift:59`
- `WorkoutDetailMapView.swift:60`

There is no old/default Mapbox style literal in the app code outside a test-only override, so the mismatch is unlikely to be a second hardcoded style. The strongest code-level explanation is that `WorkoutDetailMapView`'s map creation/update lifecycle can still display the SDK default/base style on device even though it receives the shared style URI at initialization. Feed route previews inherit this because they reuse the same view.

### 4. Code Path vs Cache vs URL Encoding vs Build Artifact

Current evidence by category:

- Code path: likely for Activity Detail and feed card previews. Both converge on `WorkoutDetailMapView`.
- Cache: possible for share-card `AsyncImage` static route previews if an existing URL/image was generated before Build 5 and cached. Less likely for the feed card path because it does not use `imageURL`.
- URL encoding: not the primary issue. The static style path format is correct for Mapbox Static Images: `styles/v1/gaette09/cmqtub3xc004m01rg7s331tq2/static/...`.
- Static style ID: correct for newly generated static URLs.
- TestFlight build artifact: unlikely as the main cause because Record uses the custom style correctly on the same physical Build 5, and prior Build 5 archive inspection found the shared style string present.
- Token/entitlements: unlikely as the main cause because Record loads Mapbox on device. If token were missing, Record would also be affected.

## Minimum Safe Fix

1. Make `WorkoutDetailMapView` apply the shared style as explicitly as `RecordMapView`.

   Use a single shared configuration entry point so both live maps construct `MapInitOptions` consistently. At minimum, change the detail/feed map path to use an explicit style load/apply step on creation and update, then configure annotations after the style is loaded.

2. Add a guard in `WorkoutDetailMapView` so updates cannot silently continue with a non-SOOM style.

   A debug-only assertion or redacted diagnostic log is enough. It should report only whether the expected style is active, never token values.

3. Keep static URL generation centralized.

   No additional style literals should be introduced. New static URLs should continue to use `SOOMMapboxConfiguration.staticImagesStyleID`.

4. If a QA surface is actually a share-card static image, regenerate the static preview URL after the style fix and clear image cache/persisted drafts before retesting.

## Verification Steps

1. Build and run on iPhone simulator:

   ```sh
   xcodebuild -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
   ```

2. Add or run focused tests confirming:

   - `MapboxStaticRouteURLBuilder` default URL prefix is `https://api.mapbox.com/styles/v1/gaette09/cmqtub3xc004m01rg7s331tq2/static/`
   - `StaticRoutePreviewBuilder` does not override the default style ID
   - feed DTO/draft paths intentionally do not persist stale static image URLs

3. Archive the Release build and inspect without printing secrets:

   - `MBXAccessToken` is configured in the archived Info.plist.
   - the archived app binary contains `cmqtub3xc004m01rg7s331tq2`.
   - no token value is printed.

4. Install a fresh TestFlight build on device.

   Remove the app first if validating static image cache behavior. Then verify:

   - Record map shows the SOOM custom style.
   - Activity Detail hero map shows the SOOM custom style.
   - Activity Detail overlay map shows the SOOM custom style.
   - Feed route preview card shows the SOOM custom style.
   - Share-card map-photo preview, if tested, uses a newly generated static URL with the SOOM style path.

5. If feed still differs after the live-map fix, capture whether the visible surface is:

   - `WorkoutDetailMapView` live Mapbox map,
   - `WorkoutDetailMapFallback` gradient fallback,
   - `AsyncImage` static route preview from `ShareableWorkoutCardView`,
   - or a persisted/static image URL from outside the inspected call sites.

## Release Blocker Status

This remains a release blocker for Build 5 because two shipped route-map surfaces do not match the intended SOOM Mapbox style on physical TestFlight. The minimum next task is to make `WorkoutDetailMapView` enforce the shared Mapbox style the same way the Record map path does, then ship a new TestFlight build for device QA.
