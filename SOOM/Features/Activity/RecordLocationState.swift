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

enum RecordLocationButtonAction: Equatable {
    case requestPermission
    case updateCurrentLocation
    case keepFallback
}

struct RecordLocationState: Equatable {
    let authorization: RecordLocationAuthorizationState
    let coordinate: RecordMapCoordinate?
    let fallbackCoordinate: RecordMapCoordinate

    static let fallbackCoordinate = RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271)

    static let mockCurrent = RecordLocationState(
        authorization: .notDetermined,
        coordinate: nil,
        fallbackCoordinate: fallbackCoordinate
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

    var locationButtonAction: RecordLocationButtonAction {
        switch authorization {
        case .notDetermined:
            return .requestPermission
        case .authorized:
            return .updateCurrentLocation
        case .denied, .restricted, .unknown:
            return .keepFallback
        }
    }

    var recenterTarget: RecordMapCoordinate? {
        canShowUserLocation ? coordinate : nil
    }
}
