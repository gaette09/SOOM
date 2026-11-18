import Foundation

struct LocalDataPresence: Codable, Equatable {
    let hasTrainingSettings: Bool
    let hasWorkouts: Bool
    let hasWorkoutRoutes: Bool
    let hasProgressionData: Bool
    let hasCheckIns: Bool
    let hasRecoverySnapshots: Bool

    init(
        hasTrainingSettings: Bool,
        hasWorkouts: Bool,
        hasWorkoutRoutes: Bool,
        hasProgressionData: Bool,
        hasCheckIns: Bool = false,
        hasRecoverySnapshots: Bool = false
    ) {
        self.hasTrainingSettings = hasTrainingSettings
        self.hasWorkouts = hasWorkouts
        self.hasWorkoutRoutes = hasWorkoutRoutes
        self.hasProgressionData = hasProgressionData
        self.hasCheckIns = hasCheckIns
        self.hasRecoverySnapshots = hasRecoverySnapshots
    }

    private enum CodingKeys: String, CodingKey {
        case hasTrainingSettings, hasWorkouts, hasWorkoutRoutes, hasProgressionData
        case hasCheckIns, hasRecoverySnapshots
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hasTrainingSettings: try values.decode(Bool.self, forKey: .hasTrainingSettings),
            hasWorkouts: try values.decode(Bool.self, forKey: .hasWorkouts),
            hasWorkoutRoutes: try values.decode(Bool.self, forKey: .hasWorkoutRoutes),
            hasProgressionData: try values.decode(Bool.self, forKey: .hasProgressionData),
            hasCheckIns: try values.decodeIfPresent(Bool.self, forKey: .hasCheckIns) ?? false,
            hasRecoverySnapshots: try values.decodeIfPresent(Bool.self, forKey: .hasRecoverySnapshots) ?? false
        )
    }

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
        // Health data enables local reset without expanding account-migration scope.
        totalDetectedTypes > 0 || hasCheckIns || hasRecoverySnapshots
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
