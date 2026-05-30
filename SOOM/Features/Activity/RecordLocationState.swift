import CoreLocation
import Foundation

enum RecordLocationAuthorizationState: Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case unknown

    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            self = .authorized
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .unknown
        }
    }
}

struct RecordLocationState: Equatable {
    let authorization: RecordLocationAuthorizationState
    let coordinate: RecordMapCoordinate?
    let fallbackCoordinate: RecordMapCoordinate

    static let mockCurrent = RecordLocationState(
        authorization: .notDetermined,
        coordinate: nil,
        fallbackCoordinate: RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271)
    )

    var canShowUserLocation: Bool {
        authorization == .authorized && coordinate != nil
    }

    var displayCoordinate: RecordMapCoordinate {
        coordinate ?? fallbackCoordinate
    }

    var shouldRequestPermissionOnEntry: Bool {
        false
    }
}
