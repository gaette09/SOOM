import Foundation

struct WorkoutTypeMetricProfile: Equatable {
    let workoutType: UnifiedWorkoutType
    let primaryMetrics: [WorkoutGrowthMetricType]
    let secondaryMetrics: [WorkoutGrowthMetricType]

    var orderedMetrics: [WorkoutGrowthMetricType] {
        primaryMetrics + secondaryMetrics
    }

    init(workoutType: UnifiedWorkoutType) {
        self.workoutType = workoutType

        switch workoutType {
        case .running:
            primaryMetrics = [.distance, .duration, .pace]
            secondaryMetrics = [.heartRateEfficiency, .elevation]
        case .cycling:
            primaryMetrics = [.distance, .duration, .speed, .elevation]
            secondaryMetrics = [.heartRateEfficiency]
        case .swimming:
            primaryMetrics = [.distance, .duration, .pace100m]
            secondaryMetrics = []
        case .walking, .hiking:
            primaryMetrics = [.distance, .duration, .pace]
            secondaryMetrics = [.elevation, .heartRateEfficiency]
        case .strength, .yoga:
            primaryMetrics = [.duration, .consistency]
            secondaryMetrics = [.heartRateEfficiency]
        case .other:
            primaryMetrics = [.distance, .duration, .speed]
            secondaryMetrics = [.heartRateEfficiency, .elevation]
        }
    }
}
