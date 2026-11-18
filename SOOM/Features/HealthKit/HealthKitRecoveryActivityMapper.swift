import Foundation

struct HealthKitRecoveryActivityMapper {
    func map(_ workout: HealthKitWorkout) -> RecoveryActivity {
        RecoveryActivity(
            workoutType: mapWorkoutType(workout.workoutType),
            durationMinutes: durationMinutes(from: workout.duration),
            distanceKm: distanceKm(fromMeters: workout.distance),
            averageHeartRate: averageHeartRate(from: workout.averageHeartRate),
            relativeEffort: estimateRelativeEffort(for: workout),
            trainingLoad: estimateTrainingLoad(for: workout),
            completedAt: workout.endDate
        )
    }

    private func mapWorkoutType(_ type: HealthKitWorkoutType) -> RecoveryWorkoutType {
        switch type {
        case .running:
            return .run
        case .cycling:
            return .ride
        case .swimming:
            return .swim
        case .walking, .other:
            return .run
        }
    }

    private func durationMinutes(from duration: TimeInterval) -> Int {
        guard duration.isFinite, duration > 0 else { return 0 }
        return max(Int(min(duration / 60, Double(Int.max / 2)).rounded()), 1)
    }

    private func distanceKm(fromMeters meters: Double?) -> Double {
        guard let meters, meters.isFinite else { return 0 }
        return max(meters / 1_000, 0)
    }

    private func averageHeartRate(from heartRate: Double?) -> Int {
        guard let heartRate, heartRate.isFinite, heartRate > 0, heartRate < Double(Int.max / 2) else { return 0 }
        return max(Int(heartRate.rounded()), 0)
    }

    private func estimateRelativeEffort(for workout: HealthKitWorkout) -> Int {
        guard workout.duration.isFinite, workout.duration > 0 else { return 0 }
        let durationScore = workout.duration / 60 * 0.65
        let heartRateScore = max((workout.averageHeartRate.flatMap { $0.isFinite ? $0 : nil } ?? 0) - 100, 0) * 0.8
        let estimated = durationScore + heartRateScore
        return Int(clamp(estimated, lowerBound: 1, upperBound: 100).rounded())
    }

    private func estimateTrainingLoad(for workout: HealthKitWorkout) -> Double {
        guard workout.duration.isFinite, workout.duration > 0 else { return 0 }
        let durationLoad = workout.duration / 60 * 0.9
        let heartRateLoad = max((workout.averageHeartRate.flatMap { $0.isFinite ? $0 : nil } ?? 0) - 100, 0) * 0.75
        let calorieLoad = max(workout.calories.flatMap { $0.isFinite ? $0 : nil } ?? 0, 0) * 0.08

        // TODO: Replace this MVP estimate with TRIMP / HR zone based load once
        // HealthKit heart-rate samples and workout segments are available.
        return clamp(durationLoad + heartRateLoad + calorieLoad, lowerBound: 5, upperBound: 180)
    }

    private func clamp(_ value: Double, lowerBound: Double, upperBound: Double) -> Double {
        min(max(value, lowerBound), upperBound)
    }
}
