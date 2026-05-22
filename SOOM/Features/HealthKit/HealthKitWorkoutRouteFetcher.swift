import CoreLocation
import Foundation
import HealthKit

protocol HealthKitWorkoutRouteFetching {
    func fetchRoute(for workout: HKWorkout) async throws -> WorkoutRoute?
}

final class HealthKitWorkoutRouteFetcher: HealthKitWorkoutRouteFetching {
    private let healthStore: HKHealthStore
    private let mapper: HealthKitWorkoutRouteMapper

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        mapper: HealthKitWorkoutRouteMapper = HealthKitWorkoutRouteMapper()
    ) {
        self.healthStore = healthStore
        self.mapper = mapper
    }

    func fetchRoute(for workout: HKWorkout) async throws -> WorkoutRoute? {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitAuthorizationError.healthDataUnavailable
        }

        let routeSamples = try await fetchRouteSamples(for: workout)
        guard !routeSamples.isEmpty else { return nil }

        var locations: [CLLocation] = []
        for routeSample in routeSamples {
            locations.append(contentsOf: try await fetchLocations(for: routeSample))
        }

        return mapper.map(workout: workout, locations: locations)
    }

    private func fetchRouteSamples(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        try await withCheckedThrowingContinuation { continuation in
            let routeType = HKSeriesType.workoutRoute()
            let predicate = HKQuery.predicateForObjects(from: workout)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples as? [HKWorkoutRoute] ?? [])
            }

            healthStore.execute(query)
        }
    }

    private func fetchLocations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { continuation in
            var locations: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, routeLocations, done, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let routeLocations {
                    locations.append(contentsOf: routeLocations)
                }

                if done {
                    continuation.resume(returning: locations)
                }
            }

            healthStore.execute(query)
        }
    }
}
