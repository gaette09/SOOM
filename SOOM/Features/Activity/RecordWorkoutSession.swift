import Foundation

struct RecordRouteCoordinate: Equatable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date?

    init(latitude: Double, longitude: Double, timestamp: Date? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }

    init(mapCoordinate: RecordMapCoordinate, timestamp: Date? = nil) {
        self.init(
            latitude: mapCoordinate.latitude,
            longitude: mapCoordinate.longitude,
            timestamp: timestamp
        )
    }

    var workoutRouteCoordinate: WorkoutRouteCoordinate {
        WorkoutRouteCoordinate(
            latitude: latitude,
            longitude: longitude,
            timestamp: timestamp
        )
    }
}

struct RecordRouteCapture: Equatable {
    let coordinates: [RecordRouteCoordinate]
    let distanceMeters: Double
    let recordedAt: Date

    init(
        coordinates: [RecordRouteCoordinate] = [],
        distanceMeters: Double = 0,
        recordedAt: Date = Date()
    ) {
        self.coordinates = coordinates
        self.distanceMeters = max(0, distanceMeters)
        self.recordedAt = recordedAt
    }

    var startCoordinate: RecordRouteCoordinate? {
        coordinates.first
    }

    var endCoordinate: RecordRouteCoordinate? {
        coordinates.last
    }

    var hasRoute: Bool {
        coordinates.count >= 2
    }

    func appending(_ coordinate: RecordRouteCoordinate) -> RecordRouteCapture {
        guard let last = coordinates.last else {
            return RecordRouteCapture(
                coordinates: [coordinate],
                distanceMeters: 0,
                recordedAt: coordinate.timestamp ?? recordedAt
            )
        }

        let segmentDistance = Self.distanceMeters(from: last, to: coordinate)
        guard segmentDistance >= 0.5 else {
            return self
        }

        return RecordRouteCapture(
            coordinates: coordinates + [coordinate],
            distanceMeters: distanceMeters + segmentDistance,
            recordedAt: coordinate.timestamp ?? recordedAt
        )
    }

    func workoutRoute(workoutId: UUID, source: UnifiedDataSource = .soomLocal, createdAt: Date) -> WorkoutRoute? {
        guard hasRoute else { return nil }

        return WorkoutRoute(
            workoutId: workoutId,
            source: source,
            coordinates: coordinates.map(\.workoutRouteCoordinate),
            totalDistanceMeters: distanceMeters,
            createdAt: createdAt
        )
    }

    static func distanceMeters(from start: RecordRouteCoordinate, to end: RecordRouteCoordinate) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let latitudeDelta = (end.latitude - start.latitude) * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let haversine = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(startLatitude) * cos(endLatitude) * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return earthRadiusMeters * 2 * atan2(sqrt(haversine), sqrt(1 - haversine))
    }
}

enum RecordWorkoutSessionState: Equatable {
    case active
    case paused
    case finished
    case cancelled
}

struct RecordWorkoutSession: Identifiable, Equatable {
    let id: UUID
    let sport: RecordSportMode
    let workoutType: UnifiedWorkoutType
    let startedAt: Date
    let startedWithLocation: Bool
    var state: RecordWorkoutSessionState
    var pausedAt: Date?
    var endedAt: Date?
    var capturedRoute: RecordRouteCapture?
    var accumulatedDistanceMeters: Double
    var lastCoordinate: RecordRouteCoordinate?
    var startedCoordinate: RecordRouteCoordinate?
    var endedCoordinate: RecordRouteCoordinate?
    var currentSpeedMetersPerSecond: Double?
    var maxSpeedMetersPerSecond: Double?

    init(
        id: UUID,
        sport: RecordSportMode,
        workoutType: UnifiedWorkoutType,
        startedAt: Date,
        startedWithLocation: Bool,
        state: RecordWorkoutSessionState,
        pausedAt: Date?,
        endedAt: Date?,
        capturedRoute: RecordRouteCapture? = nil,
        accumulatedDistanceMeters: Double = 0,
        lastCoordinate: RecordRouteCoordinate? = nil,
        startedCoordinate: RecordRouteCoordinate? = nil,
        endedCoordinate: RecordRouteCoordinate? = nil,
        currentSpeedMetersPerSecond: Double? = nil,
        maxSpeedMetersPerSecond: Double? = nil
    ) {
        self.id = id
        self.sport = sport
        self.workoutType = workoutType
        self.startedAt = startedAt
        self.startedWithLocation = startedWithLocation
        self.state = state
        self.pausedAt = pausedAt
        self.endedAt = endedAt
        self.capturedRoute = capturedRoute
        self.accumulatedDistanceMeters = max(0, accumulatedDistanceMeters)
        self.lastCoordinate = lastCoordinate
        self.startedCoordinate = startedCoordinate
        self.endedCoordinate = endedCoordinate
        self.currentSpeedMetersPerSecond = currentSpeedMetersPerSecond
        self.maxSpeedMetersPerSecond = maxSpeedMetersPerSecond
    }

    var title: String {
        "\(sport.title) 기록 중"
    }

    var statusLabel: String {
        switch state {
        case .active:
            return "기록 중"
        case .paused:
            return "일시정지"
        case .finished:
            return "기록 종료"
        case .cancelled:
            return "취소됨"
        }
    }

    var usesLocalFirstStart: Bool {
        true
    }

    func elapsedTime(referenceDate: Date) -> TimeInterval {
        let endDate = endedAt ?? pausedAt ?? referenceDate
        return max(0, endDate.timeIntervalSince(startedAt))
    }

    func paused(at date: Date) -> RecordWorkoutSession {
        guard state == .active else { return self }
        var copy = self
        copy.state = .paused
        copy.pausedAt = date
        return copy
    }

    func resumed() -> RecordWorkoutSession {
        guard state == .paused else { return self }
        var copy = self
        copy.state = .active
        copy.pausedAt = nil
        return copy
    }

    func finished(at date: Date) -> RecordWorkoutSession {
        var copy = self
        copy.state = .finished
        copy.endedAt = date
        copy.pausedAt = nil
        copy.endedCoordinate = copy.lastCoordinate
        return copy
    }

    func cancelled(at date: Date) -> RecordWorkoutSession {
        var copy = self
        copy.state = .cancelled
        copy.endedAt = date
        copy.pausedAt = nil
        return copy
    }

    func recordingLocation(
        _ coordinate: RecordMapCoordinate,
        at date: Date,
        speedMetersPerSecond: Double? = nil
    ) -> RecordWorkoutSession {
        guard state == .active else { return self }

        let routeCoordinate = RecordRouteCoordinate(mapCoordinate: coordinate, timestamp: date)
        let nextCapture = (capturedRoute ?? RecordRouteCapture(recordedAt: date)).appending(routeCoordinate)
        let sanitizedSpeed = speedMetersPerSecond.flatMap { $0 >= 0 ? $0 : nil }
        var copy = self
        copy.capturedRoute = nextCapture
        copy.accumulatedDistanceMeters = nextCapture.distanceMeters
        copy.lastCoordinate = nextCapture.endCoordinate
        copy.startedCoordinate = nextCapture.startCoordinate
        copy.currentSpeedMetersPerSecond = sanitizedSpeed ?? currentSpeedMetersPerSecond
        if let sanitizedSpeed {
            copy.maxSpeedMetersPerSecond = max(maxSpeedMetersPerSecond ?? 0, sanitizedSpeed)
        }
        return copy
    }
}

struct RecordActiveHUDMetric: Equatable {
    let label: String
    let value: String
    let unit: String?

    init(label: String, value: String, unit: String? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
    }
}

struct RecordActiveHUDLayout: Equatable {
    let sport: RecordSportMode
    let elapsed: RecordActiveHUDMetric
    let primaryMetric: RecordActiveHUDMetric
    let secondaryMetrics: [RecordActiveHUDMetric]

    var compactMetrics: [RecordActiveHUDMetric] {
        [elapsed, primaryMetric]
    }

    static func make(session: RecordWorkoutSession, referenceDate: Date) -> RecordActiveHUDLayout {
        let elapsedSeconds = session.elapsedTime(referenceDate: referenceDate)
        let distanceMeters = session.accumulatedDistanceMeters
        let averageSpeed = averageSpeedMetersPerSecond(
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds
        )

        switch session.sport {
        case .cycling:
            return RecordActiveHUDLayout(
                sport: .cycling,
                elapsed: RecordActiveHUDMetric(label: "경과 시간", value: elapsedText(elapsedSeconds)),
                primaryMetric: speedMetric(label: "현재 속도", speedMetersPerSecond: session.currentSpeedMetersPerSecond),
                secondaryMetrics: [
                    distanceMetric(distanceMeters),
                    speedMetric(label: "평균 속도", speedMetersPerSecond: averageSpeed),
                    speedMetric(label: "최대 속도", speedMetersPerSecond: session.maxSpeedMetersPerSecond),
                    unavailableMetric(label: "심박수", unit: "bpm"),
                    unavailableMetric(label: "케이던스", unit: "rpm"),
                    RecordActiveHUDMetric(label: "경사도", value: "0", unit: "%"),
                    RecordActiveHUDMetric(label: "상승고도", value: "0", unit: "m")
                ]
            )
        case .running:
            return RecordActiveHUDLayout(
                sport: .running,
                elapsed: RecordActiveHUDMetric(label: "경과 시간", value: elapsedText(elapsedSeconds)),
                primaryMetric: paceMetric(label: "현재 페이스", speedMetersPerSecond: session.currentSpeedMetersPerSecond),
                secondaryMetrics: [
                    distanceMetric(distanceMeters),
                    paceMetric(label: "평균 페이스", speedMetersPerSecond: averageSpeed),
                    speedMetric(label: "현재 속도", speedMetersPerSecond: session.currentSpeedMetersPerSecond),
                    unavailableMetric(label: "심박수", unit: "bpm"),
                    unavailableMetric(label: "케이던스", unit: "spm"),
                    RecordActiveHUDMetric(label: "상승고도", value: "0", unit: "m")
                ]
            )
        case .walking:
            return RecordActiveHUDLayout(
                sport: .walking,
                elapsed: RecordActiveHUDMetric(label: "경과 시간", value: elapsedText(elapsedSeconds)),
                primaryMetric: speedMetric(label: "현재 속도", speedMetersPerSecond: session.currentSpeedMetersPerSecond),
                secondaryMetrics: [
                    distanceMetric(distanceMeters),
                    speedMetric(label: "평균 속도", speedMetersPerSecond: averageSpeed),
                    unavailableMetric(label: "현재 고도", unit: "m"),
                    unavailableMetric(label: "심박수", unit: "bpm")
                ]
            )
        }
    }

    private static func averageSpeedMetersPerSecond(
        distanceMeters: Double,
        elapsedSeconds: TimeInterval
    ) -> Double? {
        guard distanceMeters > 0, elapsedSeconds > 0 else { return nil }
        return distanceMeters / elapsedSeconds
    }

    private static func distanceMetric(_ distanceMeters: Double) -> RecordActiveHUDMetric {
        RecordActiveHUDMetric(
            label: "거리",
            value: String(format: "%.2f", distanceMeters / 1_000),
            unit: "km"
        )
    }

    private static func speedMetric(
        label: String,
        speedMetersPerSecond: Double?
    ) -> RecordActiveHUDMetric {
        guard let speedMetersPerSecond else {
            return unavailableMetric(label: label, unit: "km/h")
        }

        return RecordActiveHUDMetric(
            label: label,
            value: String(format: "%.1f", speedMetersPerSecond * 3.6),
            unit: "km/h"
        )
    }

    private static func paceMetric(
        label: String,
        speedMetersPerSecond: Double?
    ) -> RecordActiveHUDMetric {
        guard let speedMetersPerSecond, speedMetersPerSecond > 0.5 else {
            return unavailableMetric(label: label, unit: "/km")
        }

        let paceSeconds = Int((1_000 / speedMetersPerSecond).rounded())
        return RecordActiveHUDMetric(
            label: label,
            value: String(format: "%d'%02d\"", paceSeconds / 60, paceSeconds % 60),
            unit: "/km"
        )
    }

    private static func unavailableMetric(label: String, unit: String? = nil) -> RecordActiveHUDMetric {
        RecordActiveHUDMetric(label: label, value: "--", unit: unit)
    }

    private static func elapsedText(_ elapsedSeconds: TimeInterval) -> String {
        let elapsed = Int(max(0, elapsedSeconds))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}

enum RecordActiveHUDMode: Equatable {
    case compact
    case expanded

    static let defaultMode: RecordActiveHUDMode = .compact
}

enum RecordActiveHUDModeTransition {
    static func expand(from mode: RecordActiveHUDMode) -> RecordActiveHUDMode {
        .expanded
    }

    static func collapse(from mode: RecordActiveHUDMode) -> RecordActiveHUDMode {
        .compact
    }

    static func modeAfterPauseResume(_ mode: RecordActiveHUDMode) -> RecordActiveHUDMode {
        mode
    }

    static func modeAfterFinish(_ mode: RecordActiveHUDMode) -> RecordActiveHUDMode {
        .compact
    }
}

struct RecordWorkoutStartCommand: Equatable {
    let sport: RecordSportMode
    let workoutType: UnifiedWorkoutType
    let locationAuthorization: RecordLocationAuthorizationState
    let hasLocationCoordinate: Bool

    var canStartLocalFirst: Bool {
        true
    }

    var startsWithRouteCapture: Bool {
        locationAuthorization == .authorized && hasLocationCoordinate
    }
}

struct RecordWorkoutSessionStarter {
    var idProvider: () -> UUID = UUID.init
    var dateProvider: () -> Date = Date.init

    func makeStartCommand(
        sport: RecordSportMode,
        locationState: RecordLocationState
    ) -> RecordWorkoutStartCommand {
        RecordWorkoutStartCommand(
            sport: sport,
            workoutType: sport.workoutType,
            locationAuthorization: locationState.authorization,
            hasLocationCoordinate: locationState.coordinate != nil
        )
    }

    func start(
        sport: RecordSportMode,
        locationState: RecordLocationState
    ) -> RecordWorkoutSession {
        let command = makeStartCommand(sport: sport, locationState: locationState)
        let startedAt = dateProvider()
        let initialCoordinate = locationState.coordinate.map {
            RecordRouteCoordinate(mapCoordinate: $0, timestamp: startedAt)
        }
        let capture = initialCoordinate.map {
            RecordRouteCapture(coordinates: [$0], distanceMeters: 0, recordedAt: startedAt)
        }

        return RecordWorkoutSession(
            id: idProvider(),
            sport: sport,
            workoutType: command.workoutType,
            startedAt: startedAt,
            startedWithLocation: command.startsWithRouteCapture,
            state: .active,
            pausedAt: nil,
            endedAt: nil,
            capturedRoute: capture,
            accumulatedDistanceMeters: 0,
            lastCoordinate: initialCoordinate,
            startedCoordinate: initialCoordinate,
            endedCoordinate: nil,
            currentSpeedMetersPerSecond: locationState.heading.speedMetersPerSecond,
            maxSpeedMetersPerSecond: locationState.heading.speedMetersPerSecond
        )
    }
}
