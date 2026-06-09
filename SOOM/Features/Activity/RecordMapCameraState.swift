import CoreLocation
import Foundation

struct RecordMapCameraState: Equatable {
    let center: RecordMapCoordinate
    let zoom: Double

    static let launchScaleTargetMeters = 100
    static let launchZoom = 15.8

    static let fallback = RecordMapCameraState(
        center: RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271),
        zoom: 12.8
    )

    init(center: RecordMapCoordinate, zoom: Double) {
        self.center = center
        self.zoom = zoom
    }

    init(routeCoordinates: [RecordMapCoordinate], fallback: RecordMapCameraState = .fallback) {
        guard !routeCoordinates.isEmpty else {
            self = fallback
            return
        }

        let latitude = routeCoordinates.map(\.latitude).reduce(0, +) / Double(routeCoordinates.count)
        let longitude = routeCoordinates.map(\.longitude).reduce(0, +) / Double(routeCoordinates.count)
        let latitudeSpan = (routeCoordinates.map(\.latitude).max() ?? latitude) - (routeCoordinates.map(\.latitude).min() ?? latitude)
        let longitudeSpan = (routeCoordinates.map(\.longitude).max() ?? longitude) - (routeCoordinates.map(\.longitude).min() ?? longitude)
        let span = max(latitudeSpan, longitudeSpan)

        self.center = RecordMapCoordinate(latitude: latitude, longitude: longitude)
        self.zoom = Self.zoomEstimate(for: span)
    }

    static func launch(
        currentCoordinate: RecordMapCoordinate?,
        routeCoordinates: [RecordMapCoordinate],
        fallback: RecordMapCameraState = .fallback
    ) -> RecordMapCameraState {
        if let currentCoordinate {
            return RecordMapCameraState(center: currentCoordinate, zoom: launchZoom)
        }

        if !routeCoordinates.isEmpty {
            let latitude = routeCoordinates.map(\.latitude).reduce(0, +) / Double(routeCoordinates.count)
            let longitude = routeCoordinates.map(\.longitude).reduce(0, +) / Double(routeCoordinates.count)
            return RecordMapCameraState(
                center: RecordMapCoordinate(latitude: latitude, longitude: longitude),
                zoom: launchZoom
            )
        }

        return RecordMapCameraState(center: fallback.center, zoom: launchZoom)
    }

    var locationCoordinate: CLLocationCoordinate2D {
        center.locationCoordinate
    }

    private static func zoomEstimate(for span: Double) -> Double {
        switch span {
        case ..<0.008: return 14.4
        case ..<0.018: return 13.7
        case ..<0.04: return 12.9
        case ..<0.09: return 12.0
        default: return 11.2
        }
    }
}

enum RecordMapHeadingCameraPolicy {
    static let courseSpeedThresholdMetersPerSecond = 1.0
    static let courseSpeedThresholdKilometersPerHour = courseSpeedThresholdMetersPerSecond * 3.6
    static let animatedBearingDuration = 0.18
    static let reducedMotionBearingDuration = 0.0

    static func bearing(
        heading: RecordHeadingState,
        sessionState: RecordWorkoutSessionState?,
        lastBearing: Double?
    ) -> Double {
        switch sessionState {
        case nil:
            return 0
        case .active:
            if let speed = heading.speedMetersPerSecond,
               speed <= courseSpeedThresholdMetersPerSecond {
                return lastBearing ?? 0
            }
            if let courseBearingDegrees = heading.courseBearingDegrees,
               (heading.speedMetersPerSecond ?? 0) > courseSpeedThresholdMetersPerSecond {
                return courseBearingDegrees
            }
            if let trueHeadingDegrees = heading.trueHeadingDegrees {
                return trueHeadingDegrees
            }
            return lastBearing ?? 0
        case .paused:
            return lastBearing ?? 0
        case .finished, .cancelled:
            return 0
        }
    }

    static func cameraAnimationDuration(reduceMotionEnabled: Bool) -> Double {
        reduceMotionEnabled ? reducedMotionBearingDuration : animatedBearingDuration
    }
}

enum RecordNavigationPuckStyle {
    static let coneWidth: CGFloat = 44
    static let coneHeight: CGFloat = 56
    static let shadowBlur: CGFloat = 6

    static func usesNavigationCone(
        sessionState: RecordWorkoutSessionState?,
        canShowUserLocation: Bool
    ) -> Bool {
        guard canShowUserLocation else { return false }

        switch sessionState {
        case .active, .paused:
            return true
        case nil, .finished, .cancelled:
            return false
        }
    }
}
