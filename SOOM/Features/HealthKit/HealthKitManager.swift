import Foundation
import HealthKit

protocol HealthKitManaging {
    func isHealthDataAvailable() -> Bool
    func requestAuthorization() async throws
}

enum HealthKitAuthorizationError: LocalizedError {
    case healthDataUnavailable

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "이 기기에서는 HealthKit 데이터를 사용할 수 없습니다."
        }
    }
}

final class HealthKitManager: HealthKitManaging {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func isHealthDataAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable() else {
            throw HealthKitAuthorizationError.healthDataUnavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(
                toShare: [],
                read: Self.readTypes
            ) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitAuthorizationError.healthDataUnavailable)
                }
            }
        }
    }

    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKWorkoutType.workoutType()
        ]

        [
            HKQuantityType.quantityType(forIdentifier: .heartRate),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
            HKQuantityType.quantityType(forIdentifier: .distanceCycling)
        ]
            .compactMap { $0 }
            .forEach { types.insert($0) }

        return types
    }
}
