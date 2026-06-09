import CoreLocation
import SwiftUI
import MapboxMaps
import UIKit

struct RecordMapView: View {
    let sport: RecordSportMode
    let route: RecordRouteRecommendation
    let locationState: RecordLocationState
    let recenterTrigger: Int
    let sessionState: RecordWorkoutSessionState?
    let reduceMotionEnabled: Bool
    let hidesCompass: Bool
    let accessTokenAvailable: Bool

    init(
        sport: RecordSportMode,
        route: RecordRouteRecommendation,
        locationState: RecordLocationState = .mockCurrent,
        recenterTrigger: Int = 0,
        sessionState: RecordWorkoutSessionState? = nil,
        reduceMotionEnabled: Bool = false,
        hidesCompass: Bool = false,
        accessTokenAvailable: Bool = MapboxAccessTokenAvailability.hasUsableToken
    ) {
        self.sport = sport
        self.route = route
        self.locationState = locationState
        self.recenterTrigger = recenterTrigger
        self.sessionState = sessionState
        self.reduceMotionEnabled = reduceMotionEnabled
        self.hidesCompass = hidesCompass
        self.accessTokenAvailable = accessTokenAvailable
    }

    var body: some View {
        Group {
            if shouldRenderMapbox {
                RecordMapboxSurface(
                    sport: sport,
                    route: route,
                    locationState: locationState,
                    cameraState: RecordMapCameraState.launch(
                        currentCoordinate: locationState.canShowUserLocation ? locationState.coordinate : nil,
                        routeCoordinates: route.coordinates
                    ),
                    recenterTrigger: recenterTrigger,
                    sessionState: sessionState,
                    reduceMotionEnabled: reduceMotionEnabled,
                    hidesCompass: hidesCompass
                )
            } else {
                RecordMapFallbackSurface(
                    sport: sport,
                    routeTitle: route.title,
                    routeDistance: route.distanceText
                )
            }
        }
        .onAppear(perform: logRenderingDecision)
    }

    var shouldRenderMapbox: Bool {
        accessTokenAvailable
    }

    var fallbackReason: String? {
        accessTokenAvailable ? nil : "missing-or-unusable-mapbox-token"
    }

    private func logRenderingDecision() {
        #if DEBUG
        let mode = shouldRenderMapbox ? "mapbox" : "fallback"
        let reason = fallbackReason ?? "none"
        print("[RecordMapView] mode=\(mode) tokenAvailable=\(accessTokenAvailable) routeCoordinateCount=\(route.coordinates.count) fallbackReason=\(reason)")
        #endif
    }
}

private struct RecordMapboxSurface: UIViewRepresentable {
    let sport: RecordSportMode
    let route: RecordRouteRecommendation
    let locationState: RecordLocationState
    let cameraState: RecordMapCameraState
    let recenterTrigger: Int
    let sessionState: RecordWorkoutSessionState?
    let reduceMotionEnabled: Bool
    let hidesCompass: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MapView {
        MapboxAccessTokenAvailability.configureMapboxOptionsIfNeeded()

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
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.compass.visibility = hidesCompass ? .hidden : .adaptive
        mapView.ornaments.options.logo.position = .bottomLeading
        mapView.ornaments.options.logo.margins = CGPoint(
            x: RecordMapOrnamentLayout.horizontalInset,
            y: RecordMapOrnamentLayout.bottomInset
        )
        mapView.ornaments.options.attributionButton.position = .bottomTrailing
        mapView.ornaments.options.attributionButton.margins = CGPoint(
            x: RecordMapOrnamentLayout.horizontalInset,
            y: RecordMapOrnamentLayout.bottomInset
        )
        mapView.gestures.options.rotateEnabled = false
        mapView.gestures.options.pitchEnabled = false
        context.coordinator.configure(
            mapView: mapView,
            route: route,
            locationState: locationState,
            cameraState: cameraState,
            sessionState: sessionState,
            reduceMotionEnabled: reduceMotionEnabled,
            hidesCompass: hidesCompass,
            tint: UIColor(SOOMColor.green)
        )
        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        mapView.ornaments.options.compass.visibility = hidesCompass ? .hidden : .adaptive
        context.coordinator.configure(
            mapView: mapView,
            route: route,
            locationState: locationState,
            cameraState: cameraState,
            sessionState: sessionState,
            reduceMotionEnabled: reduceMotionEnabled,
            hidesCompass: hidesCompass,
            tint: UIColor(SOOMColor.green)
        )
        context.coordinator.recenterIfNeeded(
            mapView: mapView,
            trigger: recenterTrigger,
            locationState: locationState,
            fallbackCamera: cameraState,
            sessionState: sessionState,
            reduceMotionEnabled: reduceMotionEnabled
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
        private var currentLocationState: RecordLocationState?
        private var lastAppliedBearing: Double?
        private var pulseTimer: Timer?
        private var pulseStartedAt: Date?

        deinit {
            pulseTimer?.invalidate()
        }

        func configure(
            mapView: MapView,
            route: RecordRouteRecommendation,
            locationState: RecordLocationState,
            cameraState: RecordMapCameraState,
            sessionState: RecordWorkoutSessionState?,
            reduceMotionEnabled: Bool,
            hidesCompass: Bool,
            tint: UIColor
        ) {
            let signature = [
                route.coordinates.map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|"),
                "\(locationState.displayCoordinate.latitude),\(locationState.displayCoordinate.longitude)",
                locationState.heading.signature,
                sessionState.map(String.init(describing:)) ?? "not-started",
                "\(reduceMotionEnabled)",
                "\(hidesCompass)"
            ].joined(separator: "#")
            guard signature != lastSignature else { return }
            lastSignature = signature

            if routeManager == nil {
                routeManager = mapView.annotations.makePolylineAnnotationManager()
            }
            if locationManager == nil {
                locationManager = mapView.annotations.makeCircleAnnotationManager()
            }
            configureNavigationPuck(
                mapView: mapView,
                locationState: locationState,
                sessionState: sessionState
            )

            if route.coordinates.count >= 2 {
                var routeAnnotation = PolylineAnnotation(
                    lineCoordinates: route.coordinates.map(\.locationCoordinate)
                )
                routeAnnotation.lineColor = StyleColor(tint)
                routeAnnotation.lineWidth = 4.0
                routeAnnotation.lineOpacity = 0.78
                routeManager?.annotations = [routeAnnotation]
            } else {
                routeManager?.annotations = []
            }

            currentLocationState = locationState
            if RecordNavigationPuckStyle.usesNavigationCone(
                sessionState: sessionState,
                canShowUserLocation: locationState.canShowUserLocation
            ) {
                locationManager?.annotations = []
                pulseTimer?.invalidate()
                pulseTimer = nil
                pulseStartedAt = nil
            } else {
                locationManager?.annotations = locationAnnotations(
                    for: locationState,
                    pulseProgress: 0
                )
                updatePulseTimerIfNeeded()
            }

            setCamera(
                on: mapView,
                cameraState: cameraState,
                locationState: locationState,
                sessionState: sessionState,
                reduceMotionEnabled: reduceMotionEnabled
            )
        }

        func recenterIfNeeded(
            mapView: MapView,
            trigger: Int,
            locationState: RecordLocationState,
            fallbackCamera: RecordMapCameraState,
            sessionState: RecordWorkoutSessionState?,
            reduceMotionEnabled: Bool
        ) {
            guard trigger != lastRecenterTrigger else { return }
            lastRecenterTrigger = trigger

            let center = locationState.displayCoordinate.locationCoordinate
            let bearing = cameraBearing(
                locationState: locationState,
                sessionState: sessionState,
                reduceMotionEnabled: reduceMotionEnabled
            )
            mapView.mapboxMap.setCamera(
                to: CameraOptions(
                    center: center,
                    padding: UIEdgeInsets(top: 96, left: 32, bottom: 190, right: 32),
                    zoom: max(fallbackCamera.zoom, RecordMapCameraState.launchZoom),
                    bearing: bearing,
                    pitch: 0
                )
            )
        }

        private func setCamera(
            on mapView: MapView,
            cameraState: RecordMapCameraState,
            locationState: RecordLocationState,
            sessionState: RecordWorkoutSessionState?,
            reduceMotionEnabled: Bool
        ) {
            let bearing = cameraBearing(
                locationState: locationState,
                sessionState: sessionState,
                reduceMotionEnabled: reduceMotionEnabled
            )
            mapView.mapboxMap.setCamera(
                to: CameraOptions(
                    center: cameraState.locationCoordinate,
                    padding: UIEdgeInsets(top: 96, left: 32, bottom: 190, right: 32),
                    zoom: CGFloat(cameraState.zoom),
                    bearing: bearing,
                    pitch: 0
                )
            )
        }

        private func cameraBearing(
            locationState: RecordLocationState,
            sessionState: RecordWorkoutSessionState?,
            reduceMotionEnabled: Bool
        ) -> Double {
            _ = RecordMapHeadingCameraPolicy.cameraAnimationDuration(
                reduceMotionEnabled: reduceMotionEnabled
            )
            let bearing = RecordMapHeadingCameraPolicy.bearing(
                heading: locationState.heading,
                sessionState: sessionState,
                lastBearing: lastAppliedBearing
            )
            lastAppliedBearing = bearing
            return bearing
        }

        private func configureNavigationPuck(
            mapView: MapView,
            locationState: RecordLocationState,
            sessionState: RecordWorkoutSessionState?
        ) {
            guard RecordNavigationPuckStyle.usesNavigationCone(
                sessionState: sessionState,
                canShowUserLocation: locationState.canShowUserLocation
            ) else {
                mapView.location.options.puckType = nil
                mapView.location.options.puckBearingEnabled = false
                return
            }

            mapView.location.options.puckType = .puck2D(
                Puck2DConfiguration(
                    topImage: RecordNavigationPuckImageFactory.makeConeImage(
                        color: UIColor(SOOMColor.accent)
                    ),
                    bearingImage: nil,
                    shadowImage: nil,
                    pulsing: nil,
                    showsAccuracyRing: false,
                    opacity: 1
                )
            )
            mapView.location.options.puckBearing = .course
            mapView.location.options.puckBearingEnabled = true
        }

        private func updatePulseTimerIfNeeded() {
            guard let currentLocationState,
                  RecordCurrentLocationMarkerStyle.isPulseEnabled(
                    canShowUserLocation: currentLocationState.canShowUserLocation,
                    reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
                  ) else {
                pulseTimer?.invalidate()
                pulseTimer = nil
                pulseStartedAt = nil
                return
            }

            guard pulseTimer == nil else { return }
            pulseStartedAt = Date()
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
                guard let self,
                      let currentLocationState = self.currentLocationState,
                      let pulseStartedAt = self.pulseStartedAt else { return }

                let elapsed = Date().timeIntervalSince(pulseStartedAt)
                let progress = elapsed.truncatingRemainder(dividingBy: RecordCurrentLocationMarkerStyle.pulseDurationSeconds) / RecordCurrentLocationMarkerStyle.pulseDurationSeconds
                self.locationManager?.annotations = self.locationAnnotations(
                    for: currentLocationState,
                    pulseProgress: progress
                )
            }
        }

        private func locationAnnotations(
            for locationState: RecordLocationState,
            pulseProgress: Double
        ) -> [CircleAnnotation] {
            let displayCoordinate = locationState.displayCoordinate.locationCoordinate
            let tint = markerTint(for: locationState)
            var annotations: [CircleAnnotation] = []

            if RecordCurrentLocationMarkerStyle.isPulseEnabled(
                canShowUserLocation: locationState.canShowUserLocation,
                reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
            ) {
                var pulse = CircleAnnotation(id: "record-current-location-pulse", centerCoordinate: displayCoordinate)
                pulse.circleRadius = RecordCurrentLocationMarkerStyle.pulseRadius(progress: pulseProgress)
                pulse.circleColor = StyleColor(UIColor(tint.opacity(RecordCurrentLocationMarkerStyle.pulseOpacity(progress: pulseProgress))))
                annotations.append(pulse)
            }

            var halo = CircleAnnotation(id: "record-current-location-halo", centerCoordinate: displayCoordinate)
            halo.circleRadius = locationState.canShowUserLocation ? RecordCurrentLocationMarkerStyle.staticHaloRadius : 16
            halo.circleColor = StyleColor(UIColor(tint.opacity(locationState.canShowUserLocation ? 0.18 : 0.08)))
            halo.circleStrokeColor = StyleColor(UIColor(SOOMColor.white.opacity(0.55)))
            halo.circleStrokeWidth = 1
            annotations.append(halo)

            var dot = CircleAnnotation(id: "record-current-location-dot", centerCoordinate: displayCoordinate)
            dot.circleRadius = locationState.canShowUserLocation ? RecordCurrentLocationMarkerStyle.dotRadius : RecordCurrentLocationMarkerStyle.fallbackDotRadius
            dot.circleColor = StyleColor(UIColor(tint))
            dot.circleStrokeColor = StyleColor(UIColor.white)
            dot.circleStrokeWidth = 2
            annotations.append(dot)

            return annotations
        }

        private func markerTint(for locationState: RecordLocationState) -> Color {
            locationState.canShowUserLocation ? SOOMColor.accent : SOOMColor.secondaryInk
        }
    }
}

private enum RecordNavigationPuckImageFactory {
    static func makeConeImage(color: UIColor) -> UIImage {
        let size = CGSize(
            width: RecordNavigationPuckStyle.coneWidth,
            height: RecordNavigationPuckStyle.coneHeight
        )
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.setShadow(
                offset: CGSize(width: 0, height: 3),
                blur: RecordNavigationPuckStyle.shadowBlur,
                color: UIColor.black.withAlphaComponent(0.22).cgColor
            )

            let cone = UIBezierPath()
            cone.move(to: CGPoint(x: size.width / 2, y: 4))
            cone.addCurve(
                to: CGPoint(x: size.width - 6, y: size.height - 10),
                controlPoint1: CGPoint(x: size.width - 2, y: 16),
                controlPoint2: CGPoint(x: size.width - 3, y: size.height - 24)
            )
            cone.addCurve(
                to: CGPoint(x: size.width / 2, y: size.height - 18),
                controlPoint1: CGPoint(x: size.width - 14, y: size.height - 3),
                controlPoint2: CGPoint(x: size.width - 24, y: size.height - 10)
            )
            cone.addCurve(
                to: CGPoint(x: 6, y: size.height - 10),
                controlPoint1: CGPoint(x: 24, y: size.height - 10),
                controlPoint2: CGPoint(x: 14, y: size.height - 3)
            )
            cone.addCurve(
                to: CGPoint(x: size.width / 2, y: 4),
                controlPoint1: CGPoint(x: 3, y: size.height - 24),
                controlPoint2: CGPoint(x: 2, y: 16)
            )
            cone.close()

            color.withAlphaComponent(0.94).setFill()
            cone.fill()

            UIColor.white.withAlphaComponent(0.72).setStroke()
            cone.lineWidth = 2
            cone.stroke()

            cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            let dotRect = CGRect(
                x: size.width / 2 - 5,
                y: size.height / 2 + 3,
                width: 10,
                height: 10
            )
            UIColor.white.withAlphaComponent(0.92).setFill()
            UIBezierPath(ovalIn: dotRect).fill()
        }
    }
}
