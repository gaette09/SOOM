import CoreLocation
import Foundation

protocol RecordLocationControlling: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    var location: CLLocation? { get }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var distanceFilter: CLLocationDistance { get set }
    var headingFilter: CLLocationDegrees { get set }
    var activityType: CLActivityType { get set }
    var pausesLocationUpdatesAutomatically: Bool { get set }
    var allowsBackgroundLocationUpdates: Bool { get set }
    var showsBackgroundLocationIndicator: Bool { get set }
    func requestWhenInUseAuthorization()
    func requestLocation()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func startUpdatingHeading()
    func stopUpdatingHeading()
}

extension CLLocationManager: RecordLocationControlling {}

struct RecordLocationFix: Equatable {
    let coordinate: RecordMapCoordinate
    let timestamp: Date
    let horizontalAccuracy: Double
    let speedMetersPerSecond: Double?
    let speedAccuracy: Double?
    let altitude: Double?

    init?(location: CLLocation, receivedAt: Date) {
        guard CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy.isFinite,
              (0...50).contains(location.horizontalAccuracy),
              (-5...15).contains(receivedAt.timeIntervalSince(location.timestamp)) else { return nil }
        coordinate = RecordMapCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        timestamp = location.timestamp
        horizontalAccuracy = location.horizontalAccuracy
        speedMetersPerSecond = location.speed.isFinite && location.speed >= 0 ? location.speed : nil
        speedAccuracy = location.speedAccuracy.isFinite && location.speedAccuracy >= 0 ? location.speedAccuracy : nil
        altitude = location.altitude.isFinite && location.verticalAccuracy.isFinite
            && (0...20).contains(location.verticalAccuracy) ? location.altitude : nil
    }
}

final class RecordLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var state: RecordLocationState
    @Published private(set) var lastButtonAction: RecordLocationButtonAction?
    @Published private(set) var recordingUpdates: [RecordLocationFix] = []
    @Published private(set) var recordingStatusMessage: String?
    private(set) var isCollectingLocation = false

    private let isDemo: Bool
    private let manager: any RecordLocationControlling
    private let fallbackCoordinate: RecordMapCoordinate
    private let now: () -> Date
    private let headingAvailable: Bool
    private let supportsBackgroundRecording: Bool
    private var wantsRecording = false
    private var lastAcceptedTimestamp: Date?
    private var headingState: RecordHeadingState = .unavailable

    init(
        manager: any RecordLocationControlling = CLLocationManager(),
        isDemo: Bool = false,
        fallbackCoordinate: RecordMapCoordinate = RecordLocationState.fallbackCoordinate,
        now: @escaping () -> Date = Date.init,
        headingAvailable: Bool = CLLocationManager.headingAvailable(),
        supportsBackgroundRecording: Bool = (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") == true
    ) {
        self.isDemo = isDemo
        self.manager = manager
        self.fallbackCoordinate = fallbackCoordinate
        self.now = now
        self.headingAvailable = headingAvailable
        self.supportsBackgroundRecording = supportsBackgroundRecording
        let authorization = RecordLocationAuthorizationState(manager.authorizationStatus)
        let fix = (isDemo ? nil : manager.location).flatMap { RecordLocationFix(location: $0, receivedAt: now()) }
        self.state = RecordLocationState(
            authorization: authorization,
            coordinate: authorization == .authorized ? fix?.coordinate : nil,
            fallbackCoordinate: fallbackCoordinate,
            locationTimestamp: fix?.timestamp,
            horizontalAccuracy: fix?.horizontalAccuracy
        )
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.headingFilter = 5
        manager.activityType = .fitness
    }

    deinit {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        manager.allowsBackgroundLocationUpdates = false
    }

    var shouldRequestPermissionOnEntry: Bool { state.shouldRequestPermissionOnEntry }

    /// Only an explicitly started, active workout enables continuous/background location.
    func setRecording(_ recording: Bool) {
        if wantsRecording != recording { lastAcceptedTimestamp = nil }
        wantsRecording = recording
        applyRecordingPolicy()
    }

    func shutdown() {
        setRecording(false)
        manager.stopUpdatingHeading()
    }

    func handleLocationButtonTap() {
        guard !isDemo else {
            recordingStatusMessage = "데모에서는 실제 위치를 사용하지 않고 시간을 기록해요. 샘플 운동에서 경로를 확인할 수 있어요."
            return
        }
        let action = state.locationButtonAction
        lastButtonAction = action
        switch action {
        case .requestPermission: manager.requestWhenInUseAuthorization()
        case .updateCurrentLocation:
            manager.requestLocation()
            startHeadingUpdatesIfAvailable()
        case .keepFallback: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshAuthorization()
    }

    func refreshAuthorization() {
        let authorization = RecordLocationAuthorizationState(manager.authorizationStatus)
        if authorization != .authorized {
            headingState = .unavailable
            state = RecordLocationState(authorization: authorization, coordinate: nil, fallbackCoordinate: fallbackCoordinate)
            recordingUpdates = []
            lastAcceptedTimestamp = nil
        } else {
            state = RecordLocationState(authorization: authorization, coordinate: state.coordinate, fallbackCoordinate: fallbackCoordinate, heading: state.heading, locationTimestamp: state.locationTimestamp, horizontalAccuracy: state.horizontalAccuracy)
        }
        applyRecordingPolicy()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        receiveLocations(locations)
    }

    func receiveLocations(_ locations: [CLLocation]) {
        guard state.authorization == .authorized else { return }
        let receivedAt = now()
        let fixes = locations.compactMap { RecordLocationFix(location: $0, receivedAt: receivedAt) }
            .sorted { $0.timestamp < $1.timestamp }
        guard let latest = fixes.last else {
            if wantsRecording { recordingStatusMessage = "정확한 위치를 기다리고 있어요. 시간 기록은 계속됩니다." }
            return
        }
        headingState = RecordHeadingState(trueHeadingDegrees: headingState.trueHeadingDegrees, courseBearingDegrees: locations.last?.course, speedMetersPerSecond: latest.speedMetersPerSecond)
        state = RecordLocationState(authorization: .authorized, coordinate: latest.coordinate, fallbackCoordinate: fallbackCoordinate, heading: headingState, locationTimestamp: latest.timestamp, horizontalAccuracy: latest.horizontalAccuracy)
        guard isCollectingLocation else { return }
        var accepted: [RecordLocationFix] = []
        for fix in fixes where lastAcceptedTimestamp.map({ fix.timestamp > $0 }) ?? true {
            accepted.append(fix)
            lastAcceptedTimestamp = fix.timestamp
        }
        if !accepted.isEmpty {
            recordingStatusMessage = nil
            recordingUpdates = accepted
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if wantsRecording { recordingStatusMessage = "위치를 받지 못하고 있어요. 시간은 기록되며 위치가 돌아오면 경로를 이어갑니다." }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        headingState = RecordHeadingState(trueHeadingDegrees: newHeading.trueHeading, courseBearingDegrees: headingState.courseBearingDegrees, speedMetersPerSecond: headingState.speedMetersPerSecond)
        state = RecordLocationState(authorization: state.authorization, coordinate: state.coordinate, fallbackCoordinate: fallbackCoordinate, heading: headingState, locationTimestamp: state.locationTimestamp, horizontalAccuracy: state.horizontalAccuracy)
    }

    private func applyRecordingPolicy() {
        let shouldCollect = !isDemo && wantsRecording && state.authorization == .authorized
        if shouldCollect && !isCollectingLocation {
            manager.pausesLocationUpdatesAutomatically = false
            manager.allowsBackgroundLocationUpdates = supportsBackgroundRecording
            manager.showsBackgroundLocationIndicator = supportsBackgroundRecording
            manager.startUpdatingLocation()
            startHeadingUpdatesIfAvailable()
            recordingStatusMessage = "정확한 위치를 기다리고 있어요. 시간 기록은 계속됩니다."
        } else if !shouldCollect {
            recordingUpdates = []
            manager.stopUpdatingLocation()
            manager.stopUpdatingHeading()
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            manager.pausesLocationUpdatesAutomatically = true
            recordingStatusMessage = wantsRecording ? "위치 권한이 없어 시간만 기록하고 있어요. 위치 버튼에서 권한을 확인할 수 있어요." : nil
        }
        isCollectingLocation = shouldCollect
    }

    private func startHeadingUpdatesIfAvailable() {
        guard headingAvailable else { return }
        manager.startUpdatingHeading()
    }
}
