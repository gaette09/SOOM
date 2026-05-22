import Foundation

struct StaticRoutePreviewBuilder {
    private let urlBuilder: MapboxStaticRouteURLBuilder

    init(urlBuilder: MapboxStaticRouteURLBuilder = MapboxStaticRouteURLBuilder()) {
        self.urlBuilder = urlBuilder
    }

    func build(
        route: WorkoutRoute?,
        workoutType: UnifiedWorkoutType,
        width: Int = 640,
        height: Int = 800,
        styleID: String? = nil
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

        return StaticRoutePreview(
            imageURL: urlBuilder.buildURL(for: route, width: width, height: height, styleID: styleID),
            bounds: route.bounds,
            routeExists: true,
            fallbackStyle: fallbackStyle
        )
    }
}
