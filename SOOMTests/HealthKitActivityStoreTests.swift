import XCTest
@testable import SOOM

final class HealthKitActivityStoreTests: XCTestCase {
    func testFetchRecentActivitiesMapsFetchedWorkouts() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fetcher = FakeHealthKitWorkoutFetcher(workouts: [
            makeWorkout(type: .running, endDate: now.addingTimeInterval(-86_400))
        ])
        let store = HealthKitActivityStore(workoutFetcher: fetcher, now: { now })

        let activities = try await store.fetchRecentActivities(days: 7)

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities.first?.workoutType.title, RecoveryWorkoutType.run.title)
        XCTAssertEqual(fetcher.requestedLimit, 28)
    }

    func testFetchRecentActivitiesFiltersOldWorkouts() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fetcher = FakeHealthKitWorkoutFetcher(workouts: [
            makeWorkout(type: .cycling, endDate: now.addingTimeInterval(-10 * 86_400)),
            makeWorkout(type: .cycling, endDate: now.addingTimeInterval(-2 * 86_400))
        ])
        let store = HealthKitActivityStore(workoutFetcher: fetcher, now: { now })

        let activities = try await store.fetchRecentActivities(days: 7)

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities.first?.completedAt, now.addingTimeInterval(-2 * 86_400))
    }

    func testFetchFailureReturnsEmptyActivities() async throws {
        let fetcher = FakeHealthKitWorkoutFetcher(error: TestError.fetchFailed)
        let store = HealthKitActivityStore(workoutFetcher: fetcher)

        let activities = try await store.fetchRecentActivities(days: 7)

        XCTAssertTrue(activities.isEmpty)
    }

    private func makeWorkout(
        type: HealthKitWorkoutType,
        endDate: Date,
        duration: TimeInterval = 3_600
    ) -> HealthKitWorkout {
        HealthKitWorkout(
            id: UUID(),
            workoutType: type,
            startDate: endDate.addingTimeInterval(-duration),
            endDate: endDate,
            duration: duration,
            distance: 12_000,
            averageHeartRate: 144,
            calories: 520
        )
    }
}

private final class FakeHealthKitWorkoutFetcher: HealthKitWorkoutFetching {
    private let workouts: [HealthKitWorkout]
    private let error: Error?
    private(set) var requestedLimit: Int?

    init(workouts: [HealthKitWorkout] = [], error: Error? = nil) {
        self.workouts = workouts
        self.error = error
    }

    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkout] {
        requestedLimit = limit

        if let error {
            throw error
        }

        return workouts
    }
}

private enum TestError: Error {
    case fetchFailed
}
