import Foundation

struct UnifiedWorkoutToGrowthInputMapper {
    func map(_ workout: UnifiedWorkout) -> WorkoutGrowthInput {
        let durationMinutes = max(Int((workout.durationSeconds / 60).rounded()), 1)
        let distanceKm = workout.distanceMeters.map { $0 / 1_000 }
        let averageSpeedKmh = workout.averageSpeedMetersPerSecond.map { $0 * 3.6 }

        return WorkoutGrowthInput(
            id: workout.id,
            source: workout.source,
            workoutType: workout.workoutType,
            startDate: workout.startDate,
            durationMinutes: durationMinutes,
            distanceKm: distanceKm,
            averagePaceText: paceText(for: workout, distanceKm: distanceKm),
            averageSpeedKmh: averageSpeedKmh,
            averageHeartRate: workout.averageHeartRate,
            elevationGainMeters: workout.elevationGainMeters,
            activeEnergyKcal: workout.activeEnergyKcal
        )
    }

    private func paceText(for workout: UnifiedWorkout, distanceKm: Double?) -> String? {
        guard usesPace(workout.workoutType),
              let distanceKm,
              distanceKm > 0,
              workout.durationSeconds > 0 else {
            return nil
        }

        let paceSeconds = workout.durationSeconds / distanceKm
        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds.rounded()) % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }

    private func usesPace(_ type: UnifiedWorkoutType) -> Bool {
        switch type {
        case .running, .walking, .hiking:
            return true
        case .cycling, .swimming, .strength, .yoga, .other:
            return false
        }
    }
}
