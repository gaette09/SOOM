import CoreLocation
import Foundation

protocol OnboardingLocationPermissionRequesting {
    func requestWhenInUseAuthorization()
}

/// Minimal, standalone location-permission primer for onboarding.
/// Deliberately does NOT reuse `RecordLocationManager` — that class is
/// tightly coupled to Record's own map/heading state machine
/// (`RecordLocationState`, button-driven request flow) and would drag in
/// unrelated complexity for a screen that only needs to ask once.
/// `requestWhenInUseAuthorization()` has no completion callback in
/// CoreLocation, and onboarding advances regardless of the outcome, so no
/// delegate callback handling is needed — the empty `CLLocationManagerDelegate`
/// conformance below only exists to satisfy `CLLocationManager.delegate`'s
/// expectations, not to observe the result.
final class OnboardingLocationPermissionRequester: NSObject, OnboardingLocationPermissionRequesting, CLLocationManagerDelegate {
    private let manager: CLLocationManager

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        self.manager.delegate = self
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }
}
