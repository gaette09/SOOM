import Foundation
import HealthKit

protocol HealthKitWorkoutMetricStreamFetching {
    func fetchMetricSamples(
        for workout: HKWorkout,
        sampleType: HealthKitWorkoutMetricSampleType
    ) async throws -> [HealthKitWorkoutMetricSample]

    func fetchZoneMetricSamples(
        for workout: HKWorkout
    ) async throws -> [HealthKitWorkoutMetricSampleType: [HealthKitWorkoutMetricSample]]
}

final class HealthKitWorkoutMetricStreamFetcher: HealthKitWorkoutMetricStreamFetching {
    private let healthStore: HKHealthStore
    private let mapper: HealthKitWorkoutMetricMapper

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        mapper: HealthKitWorkoutMetricMapper = HealthKitWorkoutMetricMapper()
    ) {
        self.healthStore = healthStore
        self.mapper = mapper
    }

    func fetchMetricSamples(
        for workout: HKWorkout,
        sampleType: HealthKitWorkoutMetricSampleType
    ) async throws -> [HealthKitWorkoutMetricSample] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitAuthorizationError.healthDataUnavailable
        }

        guard let quantityType = mapper.quantityType(for: sampleType) else {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let metricSamples = (samples as? [HKQuantitySample] ?? []).map { sample in
                    self.mapper.map(sample, sampleType: sampleType)
                }
                continuation.resume(returning: metricSamples)
            }

            healthStore.execute(query)
        }
    }

    func fetchZoneMetricSamples(
        for workout: HKWorkout
    ) async throws -> [HealthKitWorkoutMetricSampleType: [HealthKitWorkoutMetricSample]] {
        var result: [HealthKitWorkoutMetricSampleType: [HealthKitWorkoutMetricSample]] = [:]

        for sampleType in [HealthKitWorkoutMetricSampleType.heartRate, .cyclingCadence, .cyclingPower] {
            result[sampleType] = try await fetchMetricSamples(for: workout, sampleType: sampleType)
        }

        return result
    }
}
