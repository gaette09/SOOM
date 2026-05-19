import Foundation
import HealthKit

struct HealthKitWorkout: Identifiable, Equatable {
    let id: UUID
    let workoutType: HealthKitWorkoutType
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distance: Double?
    let averageHeartRate: Double?
    let calories: Double?
}

enum HealthKitWorkoutType: String, Equatable {
    case running
    case cycling
    case swimming
    case walking
    case other

    init(activityType: HKWorkoutActivityType) {
        switch activityType {
        case .running:
            self = .running
        case .cycling:
            self = .cycling
        case .swimming:
            self = .swimming
        case .walking:
            self = .walking
        default:
            self = .other
        }
    }

    var displayName: String {
        switch self {
        case .running:
            return "러닝"
        case .cycling:
            return "사이클"
        case .swimming:
            return "수영"
        case .walking:
            return "걷기"
        case .other:
            return "기타 운동"
        }
    }
}

extension HealthKitWorkout {
    init(workout: HKWorkout) {
        self.init(
            id: workout.uuid,
            workoutType: HealthKitWorkoutType(activityType: workout.workoutActivityType),
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            distance: workout.totalDistance?.doubleValue(for: .meter()),
            averageHeartRate: nil,
            calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        )
    }
}
