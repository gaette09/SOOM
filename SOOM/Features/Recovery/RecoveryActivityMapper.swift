import Foundation

struct LocalWorkoutSnapshot: Identifiable {
    let id: UUID
    let sport: WorkoutSport
    let durationMinutes: Int
    let distanceKm: Double
    let averageHeartRate: Int
    let relativeEffort: Int
    let trainingLoad: Double?
    let completedAt: Date

    init(
        id: UUID = UUID(),
        sport: WorkoutSport,
        durationMinutes: Int,
        distanceKm: Double,
        averageHeartRate: Int,
        relativeEffort: Int,
        trainingLoad: Double? = nil,
        completedAt: Date
    ) {
        self.id = id
        self.sport = sport
        self.durationMinutes = durationMinutes
        self.distanceKm = distanceKm
        self.averageHeartRate = averageHeartRate
        self.relativeEffort = relativeEffort
        self.trainingLoad = trainingLoad
        self.completedAt = completedAt
    }
}

extension LocalWorkoutSnapshot {
    static func mockRecent(referenceDate: Date = Date()) -> [LocalWorkoutSnapshot] {
        [
            LocalWorkoutSnapshot(
                sport: .bike,
                durationMinutes: 58,
                distanceKm: 22.4,
                averageHeartRate: 138,
                relativeEffort: 38,
                trainingLoad: 62,
                completedAt: Calendar.current.date(byAdding: .day, value: -6, to: referenceDate) ?? referenceDate
            ),
            LocalWorkoutSnapshot(
                sport: .run,
                durationMinutes: 44,
                distanceKm: 8.6,
                averageHeartRate: 154,
                relativeEffort: 58,
                trainingLoad: 92,
                completedAt: Calendar.current.date(byAdding: .day, value: -4, to: referenceDate) ?? referenceDate
            ),
            LocalWorkoutSnapshot(
                sport: .swim,
                durationMinutes: 42,
                distanceKm: 2.0,
                averageHeartRate: 126,
                relativeEffort: 30,
                trainingLoad: 48,
                completedAt: Calendar.current.date(byAdding: .day, value: -3, to: referenceDate) ?? referenceDate
            ),
            LocalWorkoutSnapshot(
                sport: .bike,
                durationMinutes: 82,
                distanceKm: 39.8,
                averageHeartRate: 146,
                relativeEffort: 64,
                trainingLoad: 110,
                completedAt: Calendar.current.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
            )
        ]
    }
}

struct RecoveryActivityMapper {
    func map(_ snapshot: LocalWorkoutSnapshot) -> RecoveryActivity {
        RecoveryActivity(
            workoutType: mapSport(snapshot.sport),
            durationMinutes: snapshot.durationMinutes,
            distanceKm: snapshot.distanceKm,
            averageHeartRate: snapshot.averageHeartRate,
            relativeEffort: snapshot.relativeEffort,
            trainingLoad: snapshot.trainingLoad ?? estimateTrainingLoad(
                durationMinutes: snapshot.durationMinutes,
                averageHeartRate: snapshot.averageHeartRate,
                relativeEffort: snapshot.relativeEffort
            ),
            completedAt: snapshot.completedAt
        )
    }

    func map(_ workout: Workout) -> RecoveryActivity {
        let durationMinutes = max(1, Int((workout.duration / 60).rounded()))
        let distanceKm = workout.distanceMeters / 1_000

        return RecoveryActivity(
            workoutType: mapSport(workout.sport),
            durationMinutes: durationMinutes,
            distanceKm: distanceKm,
            averageHeartRate: workout.avgHeartRate,
            relativeEffort: workout.effort,
            trainingLoad: estimateTrainingLoad(
                durationMinutes: durationMinutes,
                averageHeartRate: workout.avgHeartRate,
                relativeEffort: workout.effort
            ),
            completedAt: workout.date
        )
    }

    private func mapSport(_ sport: WorkoutSport) -> RecoveryWorkoutType {
        switch sport {
        case .swim:
            return .swim
        case .bike:
            return .ride
        case .run:
            return .run
        case .brick:
            return .brick
        }
    }

    private func estimateTrainingLoad(
        durationMinutes: Int,
        averageHeartRate: Int,
        relativeEffort: Int
    ) -> Double {
        // TODO: Replace this estimate with SOOM's validated TRIMP/load formula.
        let durationComponent = Double(durationMinutes) * 0.45
        let heartRateComponent = Double(max(0, averageHeartRate - 110)) * 0.35
        let effortComponent = Double(relativeEffort) * 0.65
        return max(12, (durationComponent + heartRateComponent + effortComponent).rounded())
    }
}
