import Foundation
import HealthKit

protocol HealthKitWorkoutFetching {
    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkout]
}

final class HealthKitWorkoutFetcher: HealthKitWorkoutFetching {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func fetchRecentWorkouts(limit: Int = 20) async throws -> [HealthKitWorkout] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitAuthorizationError.healthDataUnavailable
        }

        let safeLimit = max(limit, 1)
        let workoutType = HKWorkoutType.workoutType()
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HealthKitWorkout], Error>) in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: nil,
                limit: safeLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout] ?? []).map(HealthKitWorkout.init)
                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }
}
