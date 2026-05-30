import Foundation

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
        return copy
    }

    func cancelled(at date: Date) -> RecordWorkoutSession {
        var copy = self
        copy.state = .cancelled
        copy.endedAt = date
        copy.pausedAt = nil
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

        return RecordWorkoutSession(
            id: idProvider(),
            sport: sport,
            workoutType: command.workoutType,
            startedAt: dateProvider(),
            startedWithLocation: command.startsWithRouteCapture,
            state: .active,
            pausedAt: nil,
            endedAt: nil
        )
    }
}
