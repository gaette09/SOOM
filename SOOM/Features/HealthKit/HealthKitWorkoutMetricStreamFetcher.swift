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

        let mapper = self.mapper
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
                    mapper.map(sample, sampleType: sampleType)
                }
                continuation.resume(returning: metricSamples)
            }

            healthStore.execute(query)
        }
    }

    func fetchZoneMetricSamples(
        for workout: HKWorkout
    ) async throws -> [HealthKitWorkoutMetricSampleType: [HealthKitWorkoutMetricSample]] {
        try await Self.collectZoneMetrics { type in
            try await self.fetchMetricSamples(for: workout, sampleType: type)
        }
    }

    /// A missing optional cadence/power stream must not discard fetched HR.
    /// Failed channels remain absent; no permissions or replacement values added.
    static func collectZoneMetrics(
        fetch: (HealthKitWorkoutMetricSampleType) async throws -> [HealthKitWorkoutMetricSample]
    ) async throws -> [HealthKitWorkoutMetricSampleType: [HealthKitWorkoutMetricSample]] {
        var result: [HealthKitWorkoutMetricSampleType: [HealthKitWorkoutMetricSample]] = [:]
        var firstError: Error?
        for sampleType in [HealthKitWorkoutMetricSampleType.heartRate, .cyclingCadence, .cyclingPower] {
            try Task.checkCancellation()
            do { result[sampleType] = try await fetch(sampleType) }
            catch is CancellationError { throw CancellationError() }
            catch { if firstError == nil { firstError = error } }
        }
        if result.isEmpty, let firstError { throw firstError }
        return result
    }
}
