import CoreLocation
import Foundation

final class RecordLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var state: RecordLocationState
    @Published private(set) var lastButtonAction: RecordLocationButtonAction?

    private let manager: CLLocationManager
    private let fallbackCoordinate: RecordMapCoordinate
    private var headingState: RecordHeadingState = .unavailable

    init(
        manager: CLLocationManager = CLLocationManager(),
        fallbackCoordinate: RecordMapCoordinate = RecordLocationState.fallbackCoordinate
    ) {
        self.manager = manager
        self.fallbackCoordinate = fallbackCoordinate
        self.state = RecordLocationState(
            authorization: RecordLocationAuthorizationState(manager.authorizationStatus),
            coordinate: manager.location.map {
                RecordMapCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            },
            fallbackCoordinate: fallbackCoordinate,
            heading: RecordHeadingState(
                trueHeadingDegrees: nil,
                courseBearingDegrees: manager.location?.course,
                speedMetersPerSecond: manager.location?.speed
            )
        )
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        self.manager.distanceFilter = 10
        self.manager.headingFilter = 5

        if self.state.authorization == .authorized {
            startHeadingUpdatesIfAvailable()
        }
    }

    deinit {
        manager.stopUpdatingHeading()
    }

    var shouldRequestPermissionOnEntry: Bool {
        state.shouldRequestPermissionOnEntry
    }

    func handleLocationButtonTap() {
        let action = state.locationButtonAction
        lastButtonAction = action

        switch action {
        case .requestPermission:
            manager.requestWhenInUseAuthorization()
        case .updateCurrentLocation:
            manager.requestLocation()
            startHeadingUpdatesIfAvailable()
        case .keepFallback:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateState(
            authorization: RecordLocationAuthorizationState(manager.authorizationStatus),
            location: manager.location
        )

        if state.authorization == .authorized {
            manager.requestLocation()
            startHeadingUpdatesIfAvailable()
        } else {
            manager.stopUpdatingHeading()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        updateState(
            authorization: RecordLocationAuthorizationState(manager.authorizationStatus),
            location: locations.last ?? manager.location
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        updateState(
            authorization: RecordLocationAuthorizationState(manager.authorizationStatus),
            location: manager.location
        )
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let trueHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : nil
        headingState = RecordHeadingState(
            trueHeadingDegrees: trueHeading,
            courseBearingDegrees: headingState.courseBearingDegrees,
            speedMetersPerSecond: headingState.speedMetersPerSecond
        )
        updateState(
            authorization: RecordLocationAuthorizationState(manager.authorizationStatus),
            location: manager.location
        )
    }

    private func updateState(authorization: RecordLocationAuthorizationState, location: CLLocation?) {
        let coordinate = location.map {
            RecordMapCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        headingState = RecordHeadingState(
            trueHeadingDegrees: headingState.trueHeadingDegrees,
            courseBearingDegrees: location?.course ?? headingState.courseBearingDegrees,
            speedMetersPerSecond: location?.speed ?? headingState.speedMetersPerSecond
        )
        state = RecordLocationState(
            authorization: authorization,
            coordinate: coordinate,
            fallbackCoordinate: fallbackCoordinate,
            heading: headingState
        )
    }

    private func startHeadingUpdatesIfAvailable() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.startUpdatingHeading()
    }
}
