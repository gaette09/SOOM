import CoreLocation
import SwiftUI
import MapboxMaps

struct RecordMapView: View {
    let sport: RecordSportMode
    let route: RecordRouteRecommendation
    let locationState: RecordLocationState
    let recenterTrigger: Int
    let accessTokenAvailable: Bool

    init(
        sport: RecordSportMode,
        route: RecordRouteRecommendation,
        locationState: RecordLocationState = .mockCurrent,
        recenterTrigger: Int = 0,
        accessTokenAvailable: Bool = MapboxAccessTokenAvailability.hasUsableToken
    ) {
        self.sport = sport
        self.route = route
        self.locationState = locationState
        self.recenterTrigger = recenterTrigger
        self.accessTokenAvailable = accessTokenAvailable
    }

    var body: some View {
        if shouldRenderMapbox {
            RecordMapboxSurface(
                sport: sport,
                route: route,
                locationState: locationState,
                cameraState: RecordMapCameraState(routeCoordinates: route.coordinates),
                recenterTrigger: recenterTrigger
            )
        } else {
            RecordMapFallbackSurface(
                sport: sport,
                routeTitle: route.title,
                routeDistance: route.distanceText
            )
        }
    }

    var shouldRenderMapbox: Bool {
        accessTokenAvailable && route.coordinates.count >= 2
    }
}

private struct RecordMapboxSurface: UIViewRepresentable {
    let sport: RecordSportMode
    let route: RecordRouteRecommendation
    let locationState: RecordLocationState
    let cameraState: RecordMapCameraState
    let recenterTrigger: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(
            frame: .zero,
            mapInitOptions: MapInitOptions(
                cameraOptions: CameraOptions(
                    center: cameraState.locationCoordinate,
                    padding: UIEdgeInsets(top: 96, left: 32, bottom: 190, right: 32),
                    zoom: CGFloat(cameraState.zoom),
                    bearing: 0,
                    pitch: 0
                ),
                styleURI: .light
            )
        )
        mapView.ornaments.options.logo.margins = CGPoint(x: 12, y: 16)
        mapView.ornaments.options.attributionButton.margins = CGPoint(x: 12, y: 16)
        mapView.gestures.options.rotateEnabled = false
        mapView.gestures.options.pitchEnabled = false
        context.coordinator.configure(
            mapView: mapView,
            route: route,
            locationState: locationState,
            cameraState: cameraState,
            tint: UIColor(sportTint)
        )
        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.configure(
            mapView: mapView,
            route: route,
            locationState: locationState,
            cameraState: cameraState,
            tint: UIColor(sportTint)
        )
        context.coordinator.recenterIfNeeded(
            mapView: mapView,
            trigger: recenterTrigger,
            locationState: locationState,
            fallbackCamera: cameraState
        )
    }

    private var sportTint: Color {
        switch sport {
        case .cycling:
            return SOOMColor.bike
        case .running:
            return SOOMColor.run
        case .walking:
            return SOOMColor.blue
        }
    }

    final class Coordinator {
        private var routeManager: PolylineAnnotationManager?
        private var locationManager: CircleAnnotationManager?
        private var lastSignature: String?
        private var lastRecenterTrigger: Int?

        func configure(
            mapView: MapView,
            route: RecordRouteRecommendation,
            locationState: RecordLocationState,
            cameraState: RecordMapCameraState,
            tint: UIColor
        ) {
            let signature = [
                route.coordinates.map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|"),
                "\(locationState.displayCoordinate.latitude),\(locationState.displayCoordinate.longitude)"
            ].joined(separator: "#")
            guard signature != lastSignature else { return }
            lastSignature = signature

            if routeManager == nil {
                routeManager = mapView.annotations.makePolylineAnnotationManager()
            }
            if locationManager == nil {
                locationManager = mapView.annotations.makeCircleAnnotationManager()
            }

            var routeAnnotation = PolylineAnnotation(
                lineCoordinates: route.coordinates.map(\.locationCoordinate)
            )
            routeAnnotation.lineColor = StyleColor(tint)
            routeAnnotation.lineWidth = 5.2
            routeAnnotation.lineOpacity = 0.88
            routeManager?.annotations = [routeAnnotation]

            let displayCoordinate = locationState.displayCoordinate.locationCoordinate
            var halo = CircleAnnotation(id: "record-current-location-halo", centerCoordinate: displayCoordinate)
            halo.circleRadius = 22
            halo.circleColor = StyleColor(UIColor(SOOMColor.blue.opacity(0.16)))
            halo.circleStrokeColor = StyleColor(UIColor(SOOMColor.white.opacity(0.55)))
            halo.circleStrokeWidth = 1

            var dot = CircleAnnotation(id: "record-current-location-dot", centerCoordinate: displayCoordinate)
            dot.circleRadius = locationState.canShowUserLocation ? 7 : 6
            dot.circleColor = StyleColor(UIColor(SOOMColor.blue))
            dot.circleStrokeColor = StyleColor(UIColor.white)
            dot.circleStrokeWidth = 2
            locationManager?.annotations = [halo, dot]

            setCamera(on: mapView, cameraState: cameraState)
        }

        func recenterIfNeeded(
            mapView: MapView,
            trigger: Int,
            locationState: RecordLocationState,
            fallbackCamera: RecordMapCameraState
        ) {
            guard trigger != lastRecenterTrigger else { return }
            lastRecenterTrigger = trigger

            let center = locationState.displayCoordinate.locationCoordinate
            mapView.mapboxMap.setCamera(
                to: CameraOptions(
                    center: center,
                    padding: UIEdgeInsets(top: 96, left: 32, bottom: 190, right: 32),
                    zoom: max(fallbackCamera.zoom, 13.2),
                    bearing: 0,
                    pitch: 0
                )
            )
        }

        private func setCamera(on mapView: MapView, cameraState: RecordMapCameraState) {
            mapView.mapboxMap.setCamera(
                to: CameraOptions(
                    center: cameraState.locationCoordinate,
                    padding: UIEdgeInsets(top: 96, left: 32, bottom: 190, right: 32),
                    zoom: CGFloat(cameraState.zoom),
                    bearing: 0,
                    pitch: 0
                )
            )
        }
    }
}
