import XCTest
@testable import SOOM

final class WeeklyRecoverySummaryBuilderTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testBuildSummaryCreatesWeeklySummaryFromSevenSnapshots() async {
        let snapshots = makeWeekScores([82, 84, 83, 81, 80, 79, 78])
        let builder = WeeklyRecoverySummaryBuilder(
            snapshotStore: FakeWeeklySnapshotStore(snapshots: snapshots)
        )

        let summary = await builder.buildSummary()

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.bestDayScore, 84)
        XCTAssertEqual(summary?.lowestDayScore, 78)
        XCTAssertFalse(summary?.shortSummary.isEmpty ?? true)
    }

    func testAverageScoreIsRoundedFromSnapshots() {
        let builder = WeeklyRecoverySummaryBuilder(
            snapshotStore: FakeWeeklySnapshotStore(snapshots: [])
        )

        let summary = builder.makeSummary(from: makeWeekScores([80, 81, 82, 83, 84, 85, 86]))

        XCTAssertEqual(summary?.averageScore, 83)
    }

    func testTrendDirectionDetectsImprovingFlow() {
        let builder = WeeklyRecoverySummaryBuilder(
            snapshotStore: FakeWeeklySnapshotStore(snapshots: [])
        )

        let summary = builder.makeSummary(from: makeWeekScores([86, 85, 84, 78, 77, 76, 75]))

        XCTAssertEqual(summary?.trendDirection, .improving)
    }

    func testTrendDirectionDetectsDecliningFlow() {
        let builder = WeeklyRecoverySummaryBuilder(
            snapshotStore: FakeWeeklySnapshotStore(snapshots: [])
        )

        let summary = builder.makeSummary(from: makeWeekScores([72, 73, 74, 78, 82, 84, 85]))

        XCTAssertEqual(summary?.trendDirection, .declining)
        XCTAssertTrue(summary?.shortSummary.contains("피로") == true)
    }

    func testRecommendationIsGenerated() {
        let builder = WeeklyRecoverySummaryBuilder(
            snapshotStore: FakeWeeklySnapshotStore(snapshots: [])
        )

        let summary = builder.makeSummary(from: makeWeekScores([72, 73, 74, 78, 82, 84, 85]))

        XCTAssertFalse(summary?.recommendation.isEmpty ?? true)
    }

    func testEmptySnapshotsReturnNil() {
        let builder = WeeklyRecoverySummaryBuilder(
            snapshotStore: FakeWeeklySnapshotStore(snapshots: [])
        )

        XCTAssertNil(builder.makeSummary(from: []))
    }

    func testSnapshotScoreStatusAndRecommendationAreNotMutated() {
        let snapshots = makeWeekScores([82, 84, 83])
        let original = snapshots[0]
        let builder = WeeklyRecoverySummaryBuilder(
            snapshotStore: FakeWeeklySnapshotStore(snapshots: [])
        )

        _ = builder.makeSummary(from: snapshots)

        XCTAssertEqual(snapshots[0].score, original.score)
        XCTAssertEqual(snapshots[0].status, original.status)
        XCTAssertEqual(snapshots[0].recommendation, original.recommendation)
    }

    private func makeWeekScores(_ scores: [Int]) -> [DailyRecoverySnapshot] {
        scores.enumerated().map { offset, score in
            makeSnapshot(daysAgo: offset, score: score)
        }
    }

    private func makeSnapshot(
        daysAgo: Int,
        score: Int,
        status: String = "좋음",
        recommendation: String = "다음 훈련은 회복 리듬을 먼저 확인하세요.",
        activityCount: Int = 2
    ) -> DailyRecoverySnapshot {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate

        return DailyRecoverySnapshot(
            date: date,
            score: score,
            status: status,
            recommendation: recommendation,
            coachMessage: score < 75 ? "피로가 누적되는 흐름이 있어요." : "회복 리듬이 안정적입니다.",
            explanation: score < 75 ? "최근 피로 신호가 조금 보입니다." : "회복 흐름이 안정적입니다.",
            dataQuality: .estimated,
            activityCount: activityCount
        )
    }
}

private final class FakeWeeklySnapshotStore: DailyRecoverySnapshotStore {
    private let snapshots: [DailyRecoverySnapshot]

    init(snapshots: [DailyRecoverySnapshot]) {
        self.snapshots = snapshots
    }

    func saveSnapshot(_ snapshot: DailyRecoverySnapshot) async throws {}

    func fetchRecentSnapshots(days: Int) async throws -> [DailyRecoverySnapshot] {
        Array(snapshots.prefix(days))
    }

    func fetchSnapshot(for date: Date) async throws -> DailyRecoverySnapshot? {
        snapshots.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func deleteSnapshot(id: UUID) async throws {}
}
