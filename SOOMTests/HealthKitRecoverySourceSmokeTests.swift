import XCTest
@testable import SOOM

final class HealthKitRecoverySourceSmokeTests: XCTestCase {
    func testFactoryCreatesHealthKitProviderWithoutImmediateWorkoutFetch() {
        let fetcher = SmokeFakeHealthKitWorkoutFetcher(workouts: [])

        _ = RecoveryDataProviderFactory.makeProvider(
            source: .healthKit,
            healthKitWorkoutFetcher: fetcher
        )

        XCTAssertNil(fetcher.requestedLimit)
    }

    func testHealthKitSourceBuildsRecoverySummaryFromFakeWorkouts() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fetcher = SmokeFakeHealthKitWorkoutFetcher(workouts: [
            makeWorkout(
                type: .running,
                endDate: now.addingTimeInterval(-86_400),
                duration: 3_600,
                distance: 10_000,
                averageHeartRate: 152,
                calories: 640
            ),
            makeWorkout(
                type: .cycling,
                endDate: now.addingTimeInterval(-2 * 86_400),
                duration: 4_800,
                distance: 32_000,
                averageHeartRate: 144,
                calories: 720
            )
        ])

        let provider = RecoveryDataProviderFactory.makeProvider(
            source: .healthKit,
            healthKitWorkoutFetcher: fetcher
        )

        let summary = try await provider.fetchRecoverySummary()

        XCTAssertEqual(fetcher.requestedLimit, 28)
        XCTAssertTrue((45...95).contains(summary.score))
        XCTAssertFalse(summary.status.isEmpty)
        XCTAssertFalse(summary.recommendation.isEmpty)
        XCTAssertFalse(summary.coachMessage.message.isEmpty)
        XCTAssertFalse(summary.trends.isEmpty)
        XCTAssertFalse(summary.insights.isEmpty)
    }

    func testHealthKitSourceHandlesEmptyFakeWorkoutsSafely() async throws {
        let fetcher = SmokeFakeHealthKitWorkoutFetcher(workouts: [])
        let provider = RecoveryDataProviderFactory.makeProvider(
            source: .healthKit,
            healthKitWorkoutFetcher: fetcher
        )

        let summary = try await provider.fetchRecoverySummary()

        XCTAssertEqual(summary.score, 72)
        XCTAssertEqual(summary.status, "데이터 부족")
        XCTAssertFalse(summary.recommendation.isEmpty)
    }

    private func makeWorkout(
        type: HealthKitWorkoutType,
        endDate: Date,
        duration: TimeInterval,
        distance: Double,
        averageHeartRate: Double,
        calories: Double
    ) -> HealthKitWorkout {
        HealthKitWorkout(
            id: UUID(),
            workoutType: type,
            startDate: endDate.addingTimeInterval(-duration),
            endDate: endDate,
            duration: duration,
            distance: distance,
            averageHeartRate: averageHeartRate,
            calories: calories
        )
    }
}

private final class SmokeFakeHealthKitWorkoutFetcher: HealthKitWorkoutFetching {
    private let workouts: [HealthKitWorkout]
    private(set) var requestedLimit: Int?

    init(workouts: [HealthKitWorkout]) {
        self.workouts = workouts
    }

    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkout] {
        requestedLimit = limit
        return workouts
    }
}
