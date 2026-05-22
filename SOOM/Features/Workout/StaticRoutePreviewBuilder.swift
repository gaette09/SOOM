import Foundation

struct StaticRoutePreviewBuilder {
    private let urlBuilder: MapboxStaticRouteURLBuilder
    private let routeMasker: RoutePrivacyMasker

    init(
        urlBuilder: MapboxStaticRouteURLBuilder = MapboxStaticRouteURLBuilder(),
        routeMasker: RoutePrivacyMasker = RoutePrivacyMasker()
    ) {
        self.urlBuilder = urlBuilder
        self.routeMasker = routeMasker
    }

    func build(
        route: WorkoutRoute?,
        workoutType: UnifiedWorkoutType,
        width: Int = 640,
        height: Int = 800,
        styleID: String? = nil,
        privacyPolicy: RoutePrivacyMaskingPolicy = .defaultShare
    ) -> StaticRoutePreview {
        let fallbackStyle = StaticRouteFallbackStyle(workoutType: workoutType)

        guard let route, !route.coordinates.isEmpty else {
            return StaticRoutePreview(
                imageURL: nil,
                bounds: nil,
                routeExists: false,
                fallbackStyle: fallbackStyle
            )
        }

        let previewRoute = routeMasker.mask(route: route, policy: privacyPolicy)
        guard previewRoute.coordinates.count >= 2 else {
            return StaticRoutePreview(
                imageURL: nil,
                bounds: nil,
                routeExists: false,
                fallbackStyle: fallbackStyle
            )
        }

        return StaticRoutePreview(
            imageURL: urlBuilder.buildURL(for: previewRoute, width: width, height: height, styleID: styleID),
            bounds: previewRoute.bounds,
            routeExists: true,
            fallbackStyle: fallbackStyle
        )
    }
}
