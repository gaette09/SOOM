import CoreLocation
import Foundation

struct RecordMapCameraState: Equatable {
    let center: RecordMapCoordinate
    let zoom: Double

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
