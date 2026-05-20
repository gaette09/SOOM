import Foundation

struct HealthKitWorkoutToUnifiedWorkoutMapper {
    func map(_ workout: HealthKitWorkout, mappedAt: Date = Date()) -> UnifiedWorkout {
        UnifiedWorkout(
            id: workout.id,
            externalId: workout.id.uuidString,
            source: .appleHealthKit,
            workoutType: mapWorkoutType(workout.workoutType),
            startDate: workout.startDate,
            endDate: workout.endDate,
            durationSeconds: max(workout.duration, 0),
            distanceMeters: sanitizedPositive(workout.distance),
            activeEnergyKcal: sanitizedPositive(workout.calories),
            averageHeartRate: sanitizedPositive(workout.averageHeartRate),
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: averageSpeed(
                distanceMeters: workout.distance,
                durationSeconds: workout.duration
            ),
            elevationGainMeters: nil,
            dataQuality: dataQuality(for: workout),
            createdAt: mappedAt,
            updatedAt: mappedAt
        )
    }

    private func mapWorkoutType(_ type: HealthKitWorkoutType) -> UnifiedWorkoutType {
        switch type {
        case .running:
            return .running
        case .cycling:
            return .cycling
        case .swimming:
            return .swimming
        case .walking:
            return .walking
        case .other:
            return .other
        }
    }

    private func dataQuality(for workout: HealthKitWorkout) -> UnifiedDataQuality {
        let hasSummaryMetrics = workout.distance != nil
            || workout.averageHeartRate != nil
            || workout.calories != nil

        return hasSummaryMetrics ? .partial : .missing
    }

    private func averageSpeed(distanceMeters: Double?, durationSeconds: TimeInterval) -> Double? {
        guard
            let distanceMeters = sanitizedPositive(distanceMeters),
            durationSeconds > 0
        else {
            return nil
        }

        return distanceMeters / durationSeconds
    }

    private func sanitizedPositive(_ value: Double?) -> Double? {
        guard let value, value >= 0 else { return nil }
        return value
    }
}
