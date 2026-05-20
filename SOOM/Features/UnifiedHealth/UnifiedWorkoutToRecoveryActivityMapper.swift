import Foundation

struct UnifiedWorkoutToRecoveryActivityMapper {
    func map(_ workout: UnifiedWorkout) -> RecoveryActivity {
        RecoveryActivity(
            workoutType: mapWorkoutType(workout.workoutType),
            durationMinutes: durationMinutes(from: workout.durationSeconds),
            distanceKm: distanceKm(fromMeters: workout.distanceMeters),
            averageHeartRate: averageHeartRate(from: workout.averageHeartRate),
            relativeEffort: estimateRelativeEffort(for: workout),
            trainingLoad: estimateTrainingLoad(for: workout),
            completedAt: workout.endDate
        )
    }

    private func mapWorkoutType(_ type: UnifiedWorkoutType) -> RecoveryWorkoutType {
        switch type {
        case .running:
            return .run
        case .cycling:
            return .ride
        case .swimming:
            return .swim
        case .walking, .hiking, .strength, .yoga, .other:
            return .run
        }
    }

    private func durationMinutes(from durationSeconds: TimeInterval) -> Int {
        max(Int((durationSeconds / 60).rounded()), 1)
    }

    private func distanceKm(fromMeters meters: Double?) -> Double {
        guard let meters else { return 0 }
        return max(meters / 1_000, 0)
    }

    private func averageHeartRate(from heartRate: Double?) -> Int {
        guard let heartRate else { return 0 }
        return max(Int(heartRate.rounded()), 0)
    }

    private func estimateRelativeEffort(for workout: UnifiedWorkout) -> Int {
        let durationScore = workout.durationSeconds / 60 * 0.65
        let heartRateScore = max((workout.averageHeartRate ?? 120) - 100, 0) * 0.8
        let estimated = durationScore + heartRateScore

        return Int(clamp(estimated, lowerBound: 1, upperBound: 100).rounded())
    }

    private func estimateTrainingLoad(for workout: UnifiedWorkout) -> Double {
        let durationLoad = workout.durationSeconds / 60 * 0.9
        let heartRateLoad = max((workout.averageHeartRate ?? 120) - 100, 0) * 0.75
        let energyLoad = (workout.activeEnergyKcal ?? 0) * 0.08

        // TODO: Replace this MVP estimate with TRIMP, HR zone, sport-specific
        // load, power, and stream-based calculation once unified streams exist.
        return clamp(durationLoad + heartRateLoad + energyLoad, lowerBound: 5, upperBound: 180)
    }

    private func clamp(_ value: Double, lowerBound: Double, upperBound: Double) -> Double {
        min(max(value, lowerBound), upperBound)
    }
}
