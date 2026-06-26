# SOOM Build 6 Map Style Deep Trace

Date: 2026-06-26

## Context

Physical TestFlight Build 6 verification showed:

- Record map uses the SOOM custom Mapbox style.
- Activity Detail map still does not use the SOOM custom style.
- Feed map still does not use the SOOM custom style.
- Share map still does not use the SOOM custom style.

Expected style:

```text
mapbox://styles/gaette09/cmqtub3xc004m01rg7s331tq2
```

## Summary

Build 6 did include the shared Mapbox style in `WorkoutDetailMapView`, and that component now creates Mapbox `MapView` with `SOOMMapboxConfiguration.styleURI`.

The failed surfaces are not all using that component:

- Activity Detail route workouts use `WorkoutMapSheetScaffold` -> `WorkoutMapBackground`, which is SwiftUI MapKit.
- Feed detail for linked route workouts also uses `WorkoutMapSheetScaffold` -> `WorkoutMapBackground`, which is SwiftUI MapKit.
- Feed list cards use `FeedItemCard` -> `FeedReferenceRoutePreview` -> `WorkoutDetailMapView`, but with a synthetic local route, not the saved route image/static URL from feed DTOs.
- Share export uses `ShareableWorkoutCardRenderer` -> SwiftUI `ImageRenderer` -> `ShareableWorkoutCardView` -> `StaticRoutePreviewSurface` -> `AsyncImage` for a Mapbox Static Images URL. It is not a live Mapbox SDK renderer and has an async image timing/fallback risk.

The primary issue is wrong rendering paths, not the Release Mapbox token or missing style constant. Record works because it is on the live Mapbox path.

## 1. Activity Detail Visible Map

### Exact component

For route workouts, `WorkoutDetailView` selects the map-sheet presentation:

- `SOOM/Features/Activity/DetailViews.swift:17-22`

```swift
if detailMapRoute != nil {
    WorkoutMapSheetScaffold(workout: workout, navigationTitle: "운동 상세") {
        detailContent(showsHeader: false, presentationStyle: .mapSheet)
    }
}
```

The standalone hero map is only rendered when `presentationStyle == .standalone`:

- `SOOM/Features/Activity/WorkoutDetailContent.swift:59-61`

```swift
if presentationStyle == .standalone {
    ActivityDetailHeroMap(workout: workout, route: mapRoute)
}
```

That means the Build 6 fix to `WorkoutDetailMapView` does not affect the normal route-workout Activity Detail screen, because that screen is in `.mapSheet`.

### Renderer type

`WorkoutMapSheetScaffold` renders `WorkoutMapBackground` as the visible full-screen map:

- `SOOM/Features/Activity/WorkoutMapSheetScaffold.swift:42-43`

`WorkoutMapBackground` imports MapKit and uses SwiftUI `Map` with `MapPolyline` and `Marker`:

- `SOOM/Features/Activity/WorkoutMapControls.swift:1`
- `SOOM/Features/Activity/WorkoutMapControls.swift:54-79`

This is MapKit, not Mapbox, so it cannot display the SOOM Mapbox style.

### Why Build 6 failed here

Wrong code path. The visible Activity Detail map is not `ActivityDetailHeroMap`/`WorkoutDetailMapView` for route workouts. It is `WorkoutMapBackground`.

### Minimum safe fix

Replace the map-sheet background renderer with a Mapbox-backed route map that uses `SOOMMapboxConfiguration.styleURI`.

The lowest-risk shape is to keep `WorkoutMapSheetScaffold` and its bottom sheet/controls intact, but swap only `WorkoutMapBackground` from MapKit `Map` to a Mapbox `MapView` route background, or route it through a shared Mapbox route-map component that can be reused by `WorkoutDetailMapView`.

## 2. Feed Visible Map

There are two feed map surfaces.

### Feed detail

For a feed post linked to a workout with route points, `FeedPostDetailView` also uses the map-sheet scaffold:

- `SOOM/Features/Feed/FeedPostDetailContent.swift:6-11`

```swift
if let workout = post.linkedWorkout, !workout.route.isEmpty {
    WorkoutMapSheetScaffold(workout: workout, navigationTitle: "피드 상세") {
        FeedPostDetailContent(post: post)
    }
}
```

So Feed Detail has the same root cause as Activity Detail: `WorkoutMapSheetScaffold` -> `WorkoutMapBackground` -> MapKit.

### Feed list card

The feed list card path is:

- `FeedItemCard.mediaPreview`
- `FeedReferenceMediaPreview`
- `FeedReferenceRoutePreview`
- `WorkoutDetailMapView`

Evidence:

- `SOOM/Components/FeedItemCard.swift:89-100`
- `SOOM/Components/FeedItemCard.swift:257-266`
- `SOOM/Components/FeedItemCard.swift:360-372`

`FeedReferenceMediaPreview` does not pass an existing static image URL into the map. It creates a synthetic local `WorkoutRoute` from `FeedPreviewRouteFactory`:

- `SOOM/Components/FeedItemCard.swift:277-338`

Feed DTO and draft mapping explicitly set `StaticRoutePreview.imageURL` to nil:

- `SOOM/Features/Feed/FeedPostDTO.swift:125-145`
- `SOOM/Features/Feed/FeedShareDraft.swift:37-59`

This means feed list cards are not rendering the real workout route or a persisted static Mapbox image. They render a synthetic preview route through `WorkoutDetailMapView`.

### Why Build 6 failed here

For feed detail, the issue is the same wrong code path as Activity Detail: MapKit sheet background.

For feed list cards, the code path should now create a Mapbox `WorkoutDetailMapView` with the shared style. If the physical observation was specifically the feed list card, likely causes are:

- the observed screen was actually Feed Detail, not the feed card;
- the card fell back because `MapboxAccessTokenAvailability.hasUsableToken` returned false at runtime;
- the Mapbox style load was still pending or failed on-device;
- or the visible "map" being evaluated was a feed DTO/draft preview that only carries fallback metadata, not a real route/static map image.

It is not a cached static URL issue for feed list cards because DTO/draft feed previews do not persist or use `imageURL`.

### Minimum safe fix

- Fix `WorkoutMapBackground` first; that fixes Feed Detail and Activity Detail together.
- Add a device-verifiable marker or temporary QA log around `FeedReferenceRoutePreview`/`WorkoutDetailMapView` to confirm whether the feed list card is taking the live Mapbox path or fallback path.
- If feed list cards must show real saved route geography, stop using `FeedPreviewRouteFactory` for workout-session cards that have actual route data; pass the actual route or a generated static Mapbox URL instead.

## 3. Share Visible Map

### Exact renderer

Activity Detail builds the share card from `ShareableWorkoutCardBuilder`:

- `SOOM/Features/Activity/DetailViews.swift:63-70`

The composer defaults to map-photo background:

- `SOOM/Features/Activity/WorkoutDetailContent.swift:581-590`

When sharing, `WorkoutDetailContent` uses:

- `ShareCardComposer.share(...)`
- `renderShareImage(card, tint)`
- default renderer `ShareableWorkoutCardRenderer().render(card:tint:)`

The renderer is SwiftUI `ImageRenderer`, not Mapbox:

- `SOOM/Features/Workout/ShareableWorkoutCardRenderer.swift:13-22`

The share card map background path is:

- `ShareableWorkoutCardView.backgroundLayer`
- `StaticRoutePreviewSurface`
- `AsyncImage(url: preview.imageURL)`

Evidence:

- `SOOM/Components/ShareableWorkoutCardView.swift:119-125`
- `SOOM/Components/ShareableWorkoutCardView.swift:297-340`

### Static URL style

`StaticRoutePreviewBuilder` builds `imageURL` through `MapboxStaticRouteURLBuilder`:

- `SOOM/Features/Workout/StaticRoutePreviewBuilder.swift:44-48`

`MapboxStaticRouteURLBuilder` defaults to `SOOMMapboxConfiguration.staticImagesStyleID`:

- `SOOM/Features/Workout/MapboxStaticRouteURLBuilder.swift:7-10`

and constructs:

```text
https://api.mapbox.com/styles/v1/{owner/style-id}/static/...
```

That syntax is correct for Mapbox Static Images. The shared style ID path is not the obvious bug.

### Why Build 6 failed here

Share export bypasses live Mapbox entirely. It depends on an `AsyncImage` inside a SwiftUI view that is synchronously rendered by `ImageRenderer`.

Risk points:

- `ImageRenderer` can capture the `.empty` placeholder state before `AsyncImage` finishes loading.
- If `preview.imageURL` is nil, it uses a gradient fallback.
- The route line drawn over the background is `ShareCardRouteLine`, a custom SwiftUI shape, not the actual workout route.
- Feed DTO/draft previews store `imageURL: nil`, so any feed/share path based on those models cannot load a Mapbox static map unless rebuilt from a real route.

This is a share-card renderer bypass/timing problem, not a Mapbox SDK style problem.

### Minimum safe fix

Make share rendering deterministic:

- Generate the static Mapbox URL with `MapboxStaticRouteURLBuilder` using the shared static style ID.
- Fetch the static map image before rendering the share card.
- Pass a loaded `UIImage` or image data into `ShareableWorkoutCardView`/renderer so `ImageRenderer` never captures `AsyncImage.empty`.
- Keep the current fallback only for nil URL or failed image fetch.

If share cards are expected to show actual route geometry, also replace `ShareCardRouteLine` with a renderer that draws the actual masked route over the static image, or rely on the Static Images GeoJSON overlay and remove the decorative route-line ambiguity.

## 4. Cache And Artifact Assessment

### Cache

No explicit `URLCache` or `NSCache` route image cache was found in app code. Static map loading is currently `AsyncImage`, which uses system loading behavior.

Because the custom style changes the static URL path from any old style to `gaette09/cmqtub3xc004m01rg7s331tq2`, a stale URL cache is not the leading explanation for new share cards built after Build 6.

Possible stale state remains if an existing in-memory/share model was created before the style change, but app relaunch/new TestFlight build should rebuild the Activity Detail share card from `ShareableWorkoutCardBuilder`.

### Release artifact

Record works on Build 6, which proves the Release token and shared Mapbox style are present enough for live Mapbox rendering. The remaining failures are therefore rendering-path specific.

## 5. Minimum Safe Fix Set

### Detail

Replace `WorkoutMapBackground` MapKit rendering with a Mapbox renderer that uses `SOOMMapboxConfiguration.styleURI`.

Keep:

- `WorkoutMapSheetScaffold`
- bottom sheet behavior
- controls
- route camera initialization semantics

Change only the background map implementation.

### Feed

Fixing `WorkoutMapBackground` fixes Feed Detail.

For Feed list cards, verify whether the reported failure was feed list or feed detail. If it was feed list:

- instrument/inspect `WorkoutDetailMapView.hasRenderableMap` on device;
- ensure token availability returns true before rendering feed card maps;
- decide whether feed cards should use real workout route data instead of `FeedPreviewRouteFactory` synthetic routes.

### Share

Replace share export's async map background dependency with a preloaded static Mapbox image.

Minimum implementation direction:

- extend the share renderer/composer to fetch `StaticRoutePreview.imageURL` before `ImageRenderer`;
- pass loaded image into a share-card rendering path;
- preserve the existing static URL builder and shared style constant;
- add a test that generated share-card static URLs contain `SOOMMapboxConfiguration.staticImagesStyleID`.

## 6. Verification Steps

1. Build and install a device/TestFlight build with the map-sheet background migrated to Mapbox.
2. On iPhone, verify Record still uses the SOOM custom style.
3. Open Activity Detail for a route workout and verify the full-bleed sheet map uses the SOOM custom style before expanding/collapsing the sheet.
4. Open Feed Detail for a linked workout and verify the full-bleed sheet map uses the SOOM custom style.
5. Open Feed list and verify whether the card preview is using live Mapbox or fallback; if fallback, capture token availability and map creation logs.
6. Open Share composer with map-photo selected and wait for the preview image to load.
7. Export/share the card and verify the exported image, not just the preview, contains the SOOM custom static map style.
8. Re-run focused tests:
   - `MapboxStaticRouteURLBuilderTests`
   - `StaticRoutePreviewBuilderTests`
   - `ShareableWorkoutCardBuilderTests`
   - any new share renderer image-loading tests

