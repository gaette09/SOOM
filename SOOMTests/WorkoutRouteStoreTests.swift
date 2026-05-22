import HealthKit
import XCTest
@testable import SOOM

final class WorkoutRouteStoreTests: XCTestCase {
    func testSaveAndFetchRouteByWorkoutId() async throws {
        let store = InMemoryWorkoutRouteStore()
        let workoutId = UUID()
        let route = WorkoutRoute(
            workoutId: workoutId,
            source: .appleHealthKit,
            coordinates: [WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0)],
            totalDistanceMeters: 1_000
        )

        try await store.saveRoute(route)

        let fetched = try await store.fetchRoute(workoutId: workoutId)
        XCTAssertEqual(fetched, route)
    }

    func testFetchMissingRouteReturnsNil() async throws {
        let store = InMemoryWorkoutRouteStore()

        let route = try await store.fetchRoute(workoutId: UUID())

        XCTAssertNil(route)
    }

    func testSavingRouteForSameWorkoutReplacesExistingRoute() async throws {
        let store = InMemoryWorkoutRouteStore()
        let workoutId = UUID()
        let first = WorkoutRoute(
            workoutId: workoutId,
            source: .appleHealthKit,
            coordinates: [WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0)],
            totalDistanceMeters: 1_000
        )
        let updated = WorkoutRoute(
            workoutId: workoutId,
            source: .appleHealthKit,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0),
                WorkoutRouteCoordinate(latitude: 37.6, longitude: 127.1)
            ],
            totalDistanceMeters: 2_000
        )

        try await store.saveRoute(first)
        try await store.saveRoute(updated)

        let fetched = try await store.fetchRoute(workoutId: workoutId)
        XCTAssertEqual(fetched, updated)
    }
}

final class HealthKitWorkoutRouteFetcherFailureTests: XCTestCase {
    func testRouteFetchFailureCanBeHandledSafelyByCaller() async {
        let fetcher = FakeFailingRouteFetcher()

        do {
            _ = try await fetcher.fetchRoute(for: makeWorkout())
            XCTFail("Expected route fetch to fail")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    private func makeWorkout() -> HKWorkout {
        HKWorkout(
            activityType: .running,
            start: Date(timeIntervalSince1970: 1_800_000_000),
            end: Date(timeIntervalSince1970: 1_800_003_600),
            duration: 3_600,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: nil
        )
    }
}

private final class FakeFailingRouteFetcher: HealthKitWorkoutRouteFetching {
    func fetchRoute(for workout: HKWorkout) async throws -> WorkoutRoute? {
        throw SampleRouteError.fetchFailed
    }
}

private enum SampleRouteError: Error {
    case fetchFailed
}
