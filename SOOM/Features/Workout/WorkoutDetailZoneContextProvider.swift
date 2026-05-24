import Foundation
import HealthKit

struct WorkoutDetailZoneContext {
    let healthKitWorkout: HKWorkout?
    let zoneDataProvider: WorkoutZoneDataProviding?

    static let fallback = WorkoutDetailZoneContext(
        healthKitWorkout: nil,
        zoneDataProvider: nil
    )
}

protocol WorkoutDetailZoneContextProviding {
    func context(for workout: UnifiedWorkout) async -> WorkoutDetailZoneContext
}

struct WorkoutDetailZoneContextProvider: WorkoutDetailZoneContextProviding {
    private let workoutLookupProvider: HealthKitWorkoutLookingUp
    private let makeZoneDataProvider: () -> WorkoutZoneDataProviding

    init(
        workoutLookupProvider: HealthKitWorkoutLookingUp = HealthKitWorkoutLookupProvider(),
        makeZoneDataProvider: @escaping () -> WorkoutZoneDataProviding = { WorkoutZoneDataProvider() }
    ) {
        self.workoutLookupProvider = workoutLookupProvider
        self.makeZoneDataProvider = makeZoneDataProvider
    }

    func context(for workout: UnifiedWorkout) async -> WorkoutDetailZoneContext {
        guard workout.source == .appleHealthKit,
              let externalId = workout.externalId,
              !externalId.isEmpty else {
            return .fallback
        }

        guard let healthKitWorkout = await workoutLookupProvider.lookupWorkout(externalId: externalId) else {
            return .fallback
        }

        return WorkoutDetailZoneContext(
            healthKitWorkout: healthKitWorkout,
            zoneDataProvider: makeZoneDataProvider()
        )
    }
}
