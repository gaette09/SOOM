import Foundation

struct RecordWorkoutSummary: Equatable, Identifiable {
    let id: UUID
    let sport: RecordSportMode
    let workoutType: UnifiedWorkoutType
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: TimeInterval
    let distanceMeters: Double?
    let capturedRoute: Bool
    let routeCapture: RecordRouteCapture?

    var isTimeOnly: Bool {
        distanceMeters == nil
    }

    var workoutRoute: WorkoutRoute? {
        routeCapture?.workoutRoute(workoutId: id, createdAt: startedAt)
    }

    var distanceText: String {
        guard let distanceMeters, distanceMeters > 0 else {
            return "시간 기록"
        }

        return String(format: "%.2fkm", distanceMeters / 1_000)
    }
}

enum RecordWorkoutSummaryBuilder {
    static func makeSummary(from session: RecordWorkoutSession) -> RecordWorkoutSummary? {
        guard session.state == .finished, let endedAt = session.endedAt else {
            return nil
        }

        return RecordWorkoutSummary(
            id: session.id,
            sport: session.sport,
            workoutType: session.workoutType,
            startedAt: session.startedAt,
            endedAt: endedAt,
            durationSeconds: session.elapsedTime(referenceDate: endedAt),
            distanceMeters: session.accumulatedDistanceMeters > 0 ? session.accumulatedDistanceMeters : nil,
            capturedRoute: session.capturedRoute?.hasRoute == true,
            routeCapture: session.capturedRoute?.hasRoute == true ? session.capturedRoute : nil
        )
    }
}

struct RecordWorkoutSaveMapper {
    var dateProvider: () -> Date = Date.init

    func makeWorkout(from summary: RecordWorkoutSummary) -> UnifiedWorkout {
        let now = dateProvider()

        return UnifiedWorkout(
            id: summary.id,
            externalId: nil,
            source: .soomLocal,
            workoutType: summary.workoutType,
            startDate: summary.startedAt,
            endDate: summary.endedAt,
            durationSeconds: summary.durationSeconds,
            distanceMeters: summary.distanceMeters,
            activeEnergyKcal: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: summary.durationSeconds > 0
                ? summary.distanceMeters.map { $0 / summary.durationSeconds }
                : nil,
            elevationGainMeters: nil,
            dataQuality: .partial,
            isExcludedFromAnalysis: false,
            createdAt: now,
            updatedAt: now
        )
    }
}

struct RecordWorkoutSaver {
    let store: any UnifiedWorkoutStore
    var routeStore: (any WorkoutRoutePersistenceStoring)? = nil
    var mapper = RecordWorkoutSaveMapper()

    func save(_ summary: RecordWorkoutSummary) async throws -> UnifiedWorkout {
        let workout = mapper.makeWorkout(from: summary)
        try await store.saveWorkout(workout)
        if let route = summary.workoutRoute {
            try await routeStore?.saveRoute(route)
        }
        return workout
    }
}
