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
        endedCoordinate: RecordRouteCoordinate? = nil
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

    func recordingLocation(_ coordinate: RecordMapCoordinate, at date: Date) -> RecordWorkoutSession {
        guard state == .active else { return self }

        let routeCoordinate = RecordRouteCoordinate(mapCoordinate: coordinate, timestamp: date)
        let nextCapture = (capturedRoute ?? RecordRouteCapture(recordedAt: date)).appending(routeCoordinate)
        var copy = self
        copy.capturedRoute = nextCapture
        copy.accumulatedDistanceMeters = nextCapture.distanceMeters
        copy.lastCoordinate = nextCapture.endCoordinate
        copy.startedCoordinate = nextCapture.startCoordinate
        return copy
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
            endedCoordinate: nil
        )
    }
}
