import Foundation

struct RecordRouteCoordinate: Equatable, Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date?
    let segmentIndex: Int
    var cumulativeDistanceMeters: Double?
    var measuredSpeedMetersPerSecond: Double?
    var altitude: Double?

    init(latitude: Double, longitude: Double, timestamp: Date? = nil, segmentIndex: Int = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.segmentIndex = segmentIndex
    }

    init(mapCoordinate: RecordMapCoordinate, timestamp: Date? = nil, segmentIndex: Int = 0) {
        self.init(
            latitude: mapCoordinate.latitude,
            longitude: mapCoordinate.longitude,
            timestamp: timestamp,
            segmentIndex: segmentIndex
        )
    }

    var workoutRouteCoordinate: WorkoutRouteCoordinate {
        WorkoutRouteCoordinate(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            timestamp: timestamp,
            segmentIndex: segmentIndex
        )
    }
}

struct RecordRouteCapture: Equatable, Codable {
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

    var coordinateSegments: [[RecordRouteCoordinate]] {
        coordinates.reduce(into: []) { segments, coordinate in
            if segments.last?.last?.segmentIndex == coordinate.segmentIndex {
                segments[segments.count - 1].append(coordinate)
            } else {
                segments.append([coordinate])
            }
        }
    }

    var hasRoute: Bool {
        coordinateSegments.contains { $0.count >= 2 }
    }

    func appending(_ coordinate: RecordRouteCoordinate, distanceOverrideMeters: Double? = nil) -> RecordRouteCapture {
        guard let last = coordinates.last else {
            return RecordRouteCapture(
                coordinates: [coordinate],
                distanceMeters: 0,
                recordedAt: coordinate.timestamp ?? recordedAt
            )
        }

        let isNewSegment = coordinate.segmentIndex != last.segmentIndex
        let measuredDistance = distanceOverrideMeters.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let segmentDistance = isNewSegment ? 0 : (measuredDistance ?? Self.distanceMeters(from: last, to: coordinate))
        guard isNewSegment || segmentDistance >= 0.5 || (measuredDistance ?? 0) > 0 else {
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

enum RecordWorkoutSessionState: String, Equatable, Codable {
    case active
    case paused
    case finished
    case cancelled
}

struct RecordWorkoutSession: Identifiable, Equatable, Codable {
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
    var accumulatedPausedSeconds: TimeInterval = 0
    var recordingResumedAt: Date?
    var routeSegmentIndex: Int = 0
    var lastLocationTimestamp: Date?
    var lastHorizontalAccuracy: Double?
    var lastSpeedAccuracy: Double?
    var coachCheckpoint: CoachCheckpoint?

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
        self.lastLocationTimestamp = lastCoordinate?.timestamp
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
        let endDate = pausedAt ?? endedAt ?? referenceDate
        return max(0, endDate.timeIntervalSince(startedAt) - accumulatedPausedSeconds)
    }

    func wallClockElapsedTime(referenceDate: Date) -> TimeInterval {
        max(0, (endedAt ?? referenceDate).timeIntervalSince(startedAt))
    }

    func paused(at date: Date) -> RecordWorkoutSession {
        guard state == .active else { return self }
        var copy = self
        copy.state = .paused
        copy.pausedAt = max(date, recordingResumedAt ?? startedAt)
        copy.currentSpeedMetersPerSecond = nil
        return copy
    }

    func resumed(at date: Date = Date()) -> RecordWorkoutSession {
        guard state == .paused else { return self }
        var copy = self
        copy.state = .active
        let resumedAt = max(date, pausedAt ?? startedAt)
        copy.accumulatedPausedSeconds += max(0, resumedAt.timeIntervalSince(pausedAt ?? resumedAt))
        copy.recordingResumedAt = resumedAt
        copy.routeSegmentIndex += 1
        copy.pausedAt = nil
        return copy
    }

    func finished(at date: Date) -> RecordWorkoutSession {
        var copy = self
        copy.state = .finished
        copy.endedAt = max(date, startedAt)
        if let pausedAt { copy.accumulatedPausedSeconds += max(0, date.timeIntervalSince(pausedAt)) }
        copy.pausedAt = nil
        copy.endedCoordinate = copy.lastCoordinate
        return copy
    }

    func cancelled(at date: Date) -> RecordWorkoutSession {
        var copy = self
        copy.state = .cancelled
        copy.endedAt = max(date, startedAt)
        if let pausedAt { copy.accumulatedPausedSeconds += max(0, date.timeIntervalSince(pausedAt)) }
        copy.pausedAt = nil
        return copy
    }

    func recordingLocation(
        _ coordinate: RecordMapCoordinate,
        at date: Date,
        speedMetersPerSecond: Double? = nil,
        horizontalAccuracy: Double? = nil,
        speedAccuracy: Double? = nil,
        altitude: Double? = nil
    ) -> RecordWorkoutSession {
        guard state == .active, date >= (recordingResumedAt ?? startedAt),
              coordinate.latitude.isFinite, (-90...90).contains(coordinate.latitude),
              coordinate.longitude.isFinite, (-180...180).contains(coordinate.longitude),
              lastLocationTimestamp.map({ date > $0 }) ?? true else { return self }

        // Accuracy is optional for older checkpoints and callers, but live GPS
        // fixes must meet a stricter distance-quality threshold.
        if let accuracy = horizontalAccuracy,
           !accuracy.isFinite || accuracy < 0 || accuracy > 25 { return self }
        let speedLimit: Double = sport == .cycling ? 40 : (sport == .walking ? 5 : 12)
        let sanitizedSpeed = speedMetersPerSecond.flatMap {
            $0.isFinite && (0...speedLimit).contains($0) ? $0 : nil
        }
        if let last = lastCoordinate, last.segmentIndex == routeSegmentIndex,
           let timestamp = last.timestamp {
            let elapsed = date.timeIntervalSince(timestamp)
            let next = RecordRouteCoordinate(mapCoordinate: coordinate, timestamp: date)
            let distance = RecordRouteCapture.distanceMeters(from: last, to: next)
            let uncertainty = max(horizontalAccuracy ?? 0, lastHorizontalAccuracy ?? 0)
            // Reject isolated jumps without advancing the accepted anchor. The
            // next good fix then cannot add the return leg of that GPS spike.
            if elapsed > 0 && elapsed <= 30 && distance > speedLimit * elapsed + uncertainty { return self }
            if let speed = sanitizedSpeed, speed < 0.5,
               distance <= max(5, uncertainty * 2) {
                var stationary = self
                stationary.currentSpeedMetersPerSecond = speed
                stationary.lastSpeedAccuracy = nil
                return stationary
            }
            // With no Doppler speed, movement inside the accuracy radius is
            // uncertain; wait for a real displacement instead of adding noise.
            if horizontalAccuracy != nil && sanitizedSpeed == nil && distance < max(3, uncertainty) { return self }
        }
        var segment = routeSegmentIndex
        if let lastTimestamp = lastLocationTimestamp, date.timeIntervalSince(lastTimestamp) > 30 {
            segment = max(segment, (lastCoordinate?.segmentIndex ?? 0) + 1)
        }
        var routeCoordinate = RecordRouteCoordinate(mapCoordinate: coordinate, timestamp: date, segmentIndex: segment)
        var measuredDistance: Double?
        let speedAccuracyLimit = sport == .cycling ? 1.5 : 0.75
        if segment == routeSegmentIndex, let previous = lastCoordinate,
           let timestamp = previous.timestamp, let previousSpeed = currentSpeedMetersPerSecond,
           let speed = sanitizedSpeed, let speedAccuracy, let lastSpeedAccuracy,
           (0...speedAccuracyLimit).contains(speedAccuracy),
           (0...speedAccuracyLimit).contains(lastSpeedAccuracy), horizontalAccuracy != nil {
            let interval = date.timeIntervalSince(timestamp)
            if interval > 0 && interval <= 15 {
                // Accurate GNSS velocity avoids accumulating each sideways GPS
                // wobble as extra running distance. Keep the raw route points.
                measuredDistance = (previousSpeed + speed) / 2 * interval
            }
        }
        let capture = capturedRoute ?? RecordRouteCapture(recordedAt: date)
        routeCoordinate.cumulativeDistanceMeters = capture.distanceMeters + (
            capture.endCoordinate.flatMap { last in
                last.segmentIndex == segment ? measuredDistance ?? RecordRouteCapture.distanceMeters(from: last, to: routeCoordinate) : 0
            } ?? 0)
        if let accuracy = speedAccuracy, (0...speedAccuracyLimit).contains(accuracy) {
            routeCoordinate.measuredSpeedMetersPerSecond = sanitizedSpeed
        }
        routeCoordinate.altitude = altitude.flatMap { $0.isFinite ? $0 : nil }
        let nextCapture = capture.appending(routeCoordinate, distanceOverrideMeters: measuredDistance)
        var copy = self
        copy.lastLocationTimestamp = date
        copy.lastHorizontalAccuracy = horizontalAccuracy
        copy.lastSpeedAccuracy = speedAccuracy
        copy.routeSegmentIndex = segment
        copy.capturedRoute = nextCapture
        copy.accumulatedDistanceMeters = nextCapture.distanceMeters
        copy.lastCoordinate = nextCapture.endCoordinate
        copy.startedCoordinate = nextCapture.startCoordinate
        copy.currentSpeedMetersPerSecond = sanitizedSpeed
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
                elapsed: RecordActiveHUDMetric(label: "운동 시간", value: elapsedText(elapsedSeconds)),
                primaryMetric: speedMetric(label: "현재 속도", speedMetersPerSecond: session.currentSpeedMetersPerSecond),
                secondaryMetrics: [
                    distanceMetric(distanceMeters),
                    speedMetric(label: "평균 속도", speedMetersPerSecond: averageSpeed),
                    speedMetric(label: "최대 속도", speedMetersPerSecond: session.maxSpeedMetersPerSecond),
                    unavailableMetric(label: "심박수", unit: "bpm"),
                    unavailableMetric(label: "케이던스", unit: "rpm"),
                    unavailableMetric(label: "경사도", unit: "%"),
                    unavailableMetric(label: "상승고도", unit: "m")
                ]
            )
        case .running:
            return RecordActiveHUDLayout(
                sport: .running,
                elapsed: RecordActiveHUDMetric(label: "운동 시간", value: elapsedText(elapsedSeconds)),
                primaryMetric: paceMetric(label: "현재 페이스", speedMetersPerSecond: session.currentSpeedMetersPerSecond),
                secondaryMetrics: [
                    distanceMetric(distanceMeters),
                    paceMetric(label: "평균 페이스", speedMetersPerSecond: averageSpeed),
                    speedMetric(label: "현재 속도", speedMetersPerSecond: session.currentSpeedMetersPerSecond),
                    unavailableMetric(label: "심박수", unit: "bpm"),
                    unavailableMetric(label: "케이던스", unit: "spm"),
                    unavailableMetric(label: "상승고도", unit: "m")
                ]
            )
        case .walking:
            return RecordActiveHUDLayout(
                sport: .walking,
                elapsed: RecordActiveHUDMetric(label: "운동 시간", value: elapsedText(elapsedSeconds)),
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
        let initialCoordinate: RecordRouteCoordinate?
        if locationState.authorization == .authorized, let coordinate = locationState.coordinate,
           let timestamp = locationState.locationTimestamp,
           let accuracy = locationState.horizontalAccuracy, (0...25).contains(accuracy),
           (0...15).contains(startedAt.timeIntervalSince(timestamp)) {
            initialCoordinate = RecordRouteCoordinate(mapCoordinate: coordinate, timestamp: startedAt)
        } else {
            initialCoordinate = nil
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
