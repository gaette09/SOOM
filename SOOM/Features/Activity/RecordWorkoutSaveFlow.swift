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

    var isTimeOnly: Bool {
        distanceMeters == nil
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
            distanceMeters: nil,
            capturedRoute: session.startedWithLocation
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
            averageSpeedMetersPerSecond: nil,
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
    var mapper = RecordWorkoutSaveMapper()

    func save(_ summary: RecordWorkoutSummary) async throws -> UnifiedWorkout {
        let workout = mapper.makeWorkout(from: summary)
        try await store.saveWorkout(workout)
        return workout
    }
}
