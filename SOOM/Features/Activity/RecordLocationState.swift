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

struct RecordHeadingState: Equatable {
    static let minimumFollowSpeedMetersPerSecond = 1.0

    let trueHeadingDegrees: Double?
    let courseBearingDegrees: Double?
    let speedMetersPerSecond: Double?

    static let unavailable = RecordHeadingState(
        trueHeadingDegrees: nil,
        courseBearingDegrees: nil,
        speedMetersPerSecond: nil
    )

    init(
        trueHeadingDegrees: Double?,
        courseBearingDegrees: Double? = nil,
        speedMetersPerSecond: Double?
    ) {
        if let trueHeadingDegrees,
           trueHeadingDegrees >= 0,
           trueHeadingDegrees <= 360 {
            self.trueHeadingDegrees = trueHeadingDegrees
        } else {
            self.trueHeadingDegrees = nil
        }

        if let courseBearingDegrees,
           courseBearingDegrees >= 0,
           courseBearingDegrees <= 360 {
            self.courseBearingDegrees = courseBearingDegrees
        } else {
            self.courseBearingDegrees = nil
        }

        if let speedMetersPerSecond,
           speedMetersPerSecond >= 0 {
            self.speedMetersPerSecond = speedMetersPerSecond
        } else {
            self.speedMetersPerSecond = nil
        }
    }

    var canFollowHeading: Bool {
        (courseBearingDegrees != nil || trueHeadingDegrees != nil) &&
            (speedMetersPerSecond ?? 0) > Self.minimumFollowSpeedMetersPerSecond
    }

    var signature: String {
        "\(trueHeadingDegrees ?? -1):\(courseBearingDegrees ?? -1):\(speedMetersPerSecond ?? -1)"
    }
}

struct RecordLocationState: Equatable {
    let authorization: RecordLocationAuthorizationState
    let coordinate: RecordMapCoordinate?
    let fallbackCoordinate: RecordMapCoordinate
    let heading: RecordHeadingState

    static let fallbackCoordinate = RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271)

    static let mockCurrent = RecordLocationState(
        authorization: .notDetermined,
        coordinate: nil,
        fallbackCoordinate: fallbackCoordinate,
        heading: .unavailable
    )

    init(
        authorization: RecordLocationAuthorizationState,
        coordinate: RecordMapCoordinate?,
        fallbackCoordinate: RecordMapCoordinate,
        heading: RecordHeadingState = .unavailable
    ) {
        self.authorization = authorization
        self.coordinate = coordinate
        self.fallbackCoordinate = fallbackCoordinate
        self.heading = heading
    }

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
