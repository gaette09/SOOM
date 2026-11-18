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

        guard let route, !route.coordinates.isEmpty,
              route.coordinates.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite &&
                  abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }) else {
            return StaticRoutePreview(
                imageURL: nil,
                bounds: nil,
                routeExists: false,
                fallbackStyle: fallbackStyle
            )
        }

        let previewRoute = routeMasker.mask(route: route, policy: privacyPolicy)
        let coordinates = previewRoute.coordinates.map {
            ShareRouteCoordinate(latitude: $0.latitude, longitude: $0.longitude, segmentIndex: $0.segmentIndex)
        }
        guard ShareRouteGeometry(coordinates: coordinates) != nil else {
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
            fallbackStyle: fallbackStyle,
            routeWorkoutID: route.workoutId,
            maskedCoordinates: coordinates
        )
    }
}
