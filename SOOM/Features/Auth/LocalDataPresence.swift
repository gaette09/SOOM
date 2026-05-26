import Foundation

struct LocalDataPresence: Codable, Equatable {
    let hasTrainingSettings: Bool
    let hasWorkouts: Bool
    let hasWorkoutRoutes: Bool
    let hasProgressionData: Bool

    static let empty = LocalDataPresence(
        hasTrainingSettings: false,
        hasWorkouts: false,
        hasWorkoutRoutes: false,
        hasProgressionData: false
    )

    var totalDetectedTypes: Int {
        [
            hasTrainingSettings,
            hasWorkouts,
            hasWorkoutRoutes,
            hasProgressionData
        ].filter { $0 }.count
    }

    var hasAnyData: Bool {
        totalDetectedTypes > 0
    }

    var eligibleDataTypes: [UserOwnershipEligibleDataType] {
        var dataTypes: [UserOwnershipEligibleDataType] = []

        if hasTrainingSettings {
            dataTypes.append(.trainingSettings)
        }

        if hasWorkouts {
            dataTypes.append(.workouts)
        }

        if hasWorkoutRoutes {
            dataTypes.append(.workoutRoutes)
            dataTypes.append(.courseIdentities)
        }

        if hasProgressionData {
            dataTypes.append(.progressionSummaries)
        }

        return dataTypes
    }
}
