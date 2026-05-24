import Foundation
import HealthKit

protocol HealthKitWorkoutLookingUp {
    func lookupWorkout(externalId: String) async -> HKWorkout?
}

final class HealthKitWorkoutLookupProvider: HealthKitWorkoutLookingUp {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func lookupWorkout(externalId: String) async -> HKWorkout? {
        guard HKHealthStore.isHealthDataAvailable(),
              let uuid = UUID(uuidString: externalId) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: HKQuery.predicateForObject(with: uuid),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                guard error == nil else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: samples?.first as? HKWorkout)
            }

            healthStore.execute(query)
        }
    }
}
