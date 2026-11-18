import Foundation
import HealthKit

protocol HealthKitWorkoutFetching {
    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkout]
}

final class HealthKitWorkoutFetcher: HealthKitWorkoutFetching {
    private let healthStore: HKHealthStore
    private let since: Date?

    init(healthStore: HKHealthStore = HKHealthStore(), since: Date? = nil) {
        self.healthStore = healthStore
        self.since = since
    }

    func fetchRecentWorkouts(limit: Int = 20) async throws -> [HealthKitWorkout] {
        guard await MainActor.run(body: { !ReviewDemoMode.isActive }) else { return [] }
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
                predicate: since.map { HKQuery.predicateForSamples(withStart: $0, end: nil, options: .strictStartDate) },
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

/// HealthKit delivers a local observer callback, not an HTTP webhook. An anchor
/// lets that callback read only changes since the last successful import.
struct HealthKitWorkoutChanges {
    let workouts: [HealthKitWorkout]
    let anchor: HKQueryAnchor
    let changeCount: Int
}

final class HealthKitWorkoutChangeFetcher {
    private let healthStore: HKHealthStore
    private let since: Date

    init(healthStore: HKHealthStore = HKHealthStore(), since: Date) {
        self.healthStore = healthStore
        self.since = since
    }

    func fetch(after anchor: HKQueryAnchor?, limit: Int = 100) async throws -> HealthKitWorkoutChanges {
        guard await MainActor.run(body: { !ReviewDemoMode.isActive }) else { throw CancellationError() }
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitAuthorizationError.healthDataUnavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
            let query = HKAnchoredObjectQuery(type: HKWorkoutType.workoutType(), predicate: predicate,
                                              anchor: anchor, limit: max(1, limit)) {
                _, samples, deleted, nextAnchor, error in
                if let error { continuation.resume(throwing: error); return }
                guard let nextAnchor else {
                    continuation.resume(throwing: HealthKitAuthorizationError.healthDataUnavailable)
                    return
                }
                continuation.resume(returning: HealthKitWorkoutChanges(
                    workouts: (samples as? [HKWorkout] ?? []).map(HealthKitWorkout.init),
                    anchor: nextAnchor,
                    changeCount: (samples?.count ?? 0) + (deleted?.count ?? 0)))
            }
            healthStore.execute(query)
        }
    }
}

struct HealthKitChangedWorkoutBatch: HealthKitWorkoutFetching {
    let workouts: [HealthKitWorkout]
    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkout] { workouts }
}
