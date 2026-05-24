import Foundation
import HealthKit

struct WorkoutDetailZoneContext {
    let healthKitWorkout: HKWorkout?
    let zoneDataProvider: WorkoutZoneDataProviding?
    let splitDataProvider: WorkoutSplitDataProviding?

    static let fallback = WorkoutDetailZoneContext(
        healthKitWorkout: nil,
        zoneDataProvider: nil,
        splitDataProvider: nil
    )
}

protocol WorkoutDetailZoneContextProviding {
    func context(for workout: UnifiedWorkout) async -> WorkoutDetailZoneContext
}

struct WorkoutDetailZoneContextProvider: WorkoutDetailZoneContextProviding {
    private let workoutLookupProvider: HealthKitWorkoutLookingUp
    private let makeZoneDataProvider: () -> WorkoutZoneDataProviding
    private let makeSplitDataProvider: () -> WorkoutSplitDataProviding

    init(
        workoutLookupProvider: HealthKitWorkoutLookingUp = HealthKitWorkoutLookupProvider(),
        makeZoneDataProvider: @escaping () -> WorkoutZoneDataProviding = { WorkoutZoneDataProvider() },
        makeSplitDataProvider: @escaping () -> WorkoutSplitDataProviding = { WorkoutSplitDataProvider() }
    ) {
        self.workoutLookupProvider = workoutLookupProvider
        self.makeZoneDataProvider = makeZoneDataProvider
        self.makeSplitDataProvider = makeSplitDataProvider
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
            zoneDataProvider: makeZoneDataProvider(),
            splitDataProvider: makeSplitDataProvider()
        )
    }
}
