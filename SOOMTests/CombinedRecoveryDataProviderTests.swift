import XCTest
@testable import SOOM

final class CombinedRecoveryDataProviderTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testProviderFetchesActivitiesAndCheckIns() async throws {
        let activityStore = FakeRecoveryActivityStore(activities: makeActivities())
        let checkInStore = FakeRecoveryCheckInStore(checkIns: makeCheckIns())
        let provider = CombinedRecoveryDataProvider(
            activityStore: activityStore,
            checkInStore: checkInStore,
            calculator: RecoveryCalculator(referenceDate: referenceDate),
            generatedAt: { self.referenceDate }
        )

        _ = try await provider.fetchRecoverySummary()

        XCTAssertEqual(activityStore.requestedDays, 7)
        XCTAssertEqual(checkInStore.requestedDays, 7)
    }

    func testProviderReturnsRecoverySummary() async throws {
        let provider = CombinedRecoveryDataProvider(
            activityStore: FakeRecoveryActivityStore(activities: makeActivities()),
            checkInStore: FakeRecoveryCheckInStore(checkIns: makeCheckIns()),
            calculator: RecoveryCalculator(referenceDate: referenceDate),
            generatedAt: { self.referenceDate }
        )

        let summary = try await provider.fetchRecoverySummary()

        XCTAssertTrue((45...95).contains(summary.score))
        XCTAssertFalse(summary.recommendation.isEmpty)
        XCTAssertFalse(summary.trends.isEmpty)
        XCTAssertFalse(summary.insights.isEmpty)
    }

    func testCheckInsDoNotChangeV1ActivityBasedScore() async throws {
        let activities = makeActivities()
        let provider = CombinedRecoveryDataProvider(
            activityStore: FakeRecoveryActivityStore(activities: activities),
            checkInStore: FakeRecoveryCheckInStore(checkIns: makeCheckIns()),
            calculator: RecoveryCalculator(referenceDate: referenceDate),
            generatedAt: { self.referenceDate }
        )

        let summary = try await provider.fetchRecoverySummary()
        let activityOnlySummary = RecoveryCalculator(referenceDate: referenceDate)
            .calculateSummary(from: activities)

        XCTAssertEqual(summary.score, activityOnlySummary.score)
        XCTAssertEqual(summary.status, activityOnlySummary.status)
    }

    private func makeActivities() -> [RecoveryActivity] {
        [
            makeActivity(daysAgo: 6, load: 38, effort: 24, avgHR: 132),
            makeActivity(daysAgo: 4, load: 46, effort: 30, avgHR: 136),
            makeActivity(daysAgo: 2, load: 52, effort: 34, avgHR: 138)
        ]
    }

    private func makeActivity(
        daysAgo: Int,
        load: Int,
        effort: Int,
        avgHR: Int
    ) -> RecoveryActivity {
        RecoveryActivity(
            workoutType: .run,
            durationMinutes: 45,
            distanceKm: 8.0,
            averageHeartRate: avgHR,
            relativeEffort: effort,
            trainingLoad: Double(load),
            completedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: referenceDate) ?? referenceDate
        )
    }

    private func makeCheckIns() -> [RecoveryCheckIn] {
        [
            RecoveryCheckIn(
                date: referenceDate,
                fatigueLevel: 5,
                sleepQuality: 1,
                muscleSoreness: 5,
                moodLevel: 2,
                note: "테스트용 높은 피로 입력"
            )
        ]
    }
}

private final class FakeRecoveryActivityStore: RecoveryActivityStore {
    private let activities: [RecoveryActivity]
    private(set) var requestedDays: Int?

    init(activities: [RecoveryActivity]) {
        self.activities = activities
    }

    func fetchRecentActivities(days: Int) async throws -> [RecoveryActivity] {
        requestedDays = days
        return activities
    }
}

private final class FakeRecoveryCheckInStore: RecoveryCheckInStore {
    private let checkIns: [RecoveryCheckIn]
    private(set) var requestedDays: Int?

    init(checkIns: [RecoveryCheckIn]) {
        self.checkIns = checkIns
    }

    func fetchRecentCheckIns(days: Int) async throws -> [RecoveryCheckIn] {
        requestedDays = days
        return checkIns
    }
}
