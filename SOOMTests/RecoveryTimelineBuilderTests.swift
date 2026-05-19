import SwiftData
import XCTest
@testable import SOOM

final class RecoveryTimelineBuilderTests: XCTestCase {
    private let builder = RecoveryTimelineBuilder()
    private var retainedContainers: [ModelContainer] = []

    func testBuildMockTimelineCreatesEntries() {
        let entries = builder.buildMockTimeline(endingAt: makeSummary())

        XCTAssertEqual(entries.count, 5)
    }

    func testBuildMockTimelineSortsNewestFirst() {
        let entries = builder.buildMockTimeline(endingAt: makeSummary())

        let sorted = entries.sorted { $0.date > $1.date }
        XCTAssertEqual(entries.map(\.date), sorted.map(\.date))
    }

    func testBuildMockTimelineKeepsScoreInFormulaRange() {
        let entries = builder.buildMockTimeline(endingAt: makeSummary(score: 94))

        XCTAssertTrue(entries.allSatisfy { (45...95).contains($0.recoveryScore) })
    }

    func testBuildMockTimelineHandlesOptionalTextSafely() {
        let entries = builder.buildMockTimeline(endingAt: makeSummary())

        XCTAssertTrue(entries.contains { $0.checkInSummary == nil || $0.recommendationSummary == nil })
        XCTAssertTrue(entries.allSatisfy { !$0.status.isEmpty })
    }

    func testBuildTimelineCreatesEntriesFromSnapshots() async {
        let snapshots = [
            makeSnapshot(daysAgo: 0, score: 82, status: "좋음"),
            makeSnapshot(daysAgo: 1, score: 76, status: "보통")
        ]
        let builder = RecoveryTimelineBuilder(snapshotStore: FakeDailyRecoverySnapshotStore(snapshots: snapshots))

        let entries = await builder.buildTimeline()

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.recoveryScore, 82)
        XCTAssertEqual(entries.first?.status, "좋음")
        XCTAssertEqual(entries.first?.shortExplanation, "최근 회복 흐름이 안정적입니다.")
        XCTAssertEqual(entries.first?.recommendationSummary, "오늘은 가벼운 Z2를 추천해요.")
    }

    func testBuildTimelineSortsSnapshotEntriesNewestFirst() async {
        let snapshots = [
            makeSnapshot(daysAgo: 2, score: 74),
            makeSnapshot(daysAgo: 0, score: 86),
            makeSnapshot(daysAgo: 1, score: 80)
        ]
        let builder = RecoveryTimelineBuilder(snapshotStore: FakeDailyRecoverySnapshotStore(snapshots: snapshots))

        let entries = await builder.buildTimeline()

        let sorted = entries.sorted { $0.date > $1.date }
        XCTAssertEqual(entries.map(\.date), sorted.map(\.date))
    }

    func testBuildTimelineHandlesEmptySnapshots() async {
        let builder = RecoveryTimelineBuilder(snapshotStore: FakeDailyRecoverySnapshotStore(snapshots: []))

        let entries = await builder.buildTimeline(fallbackSummary: makeSummary())

        XCTAssertTrue(entries.isEmpty)
    }

    func testBuildTimelineKeepsSnapshotScoreAndStatus() async {
        let snapshot = makeSnapshot(score: 95, status: "회복 양호")
        let builder = RecoveryTimelineBuilder(snapshotStore: FakeDailyRecoverySnapshotStore(snapshots: [snapshot]))

        let entries = await builder.buildTimeline()

        XCTAssertEqual(entries.first?.recoveryScore, snapshot.score)
        XCTAssertEqual(entries.first?.status, snapshot.status)
    }

    @MainActor
    func testBuildTimelineAfterSameDayUpsertHasNoDuplicateEntries() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try makeSwiftDataStore(referenceDate: referenceDate)

        try await store.saveSnapshot(makeSnapshot(date: referenceDate, score: 70, status: "보통"))
        try await store.saveSnapshot(makeSnapshot(date: referenceDate.addingTimeInterval(60 * 60), score: 84, status: "좋음"))

        let builder = RecoveryTimelineBuilder(snapshotStore: store)
        let entries = await builder.buildTimeline()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.recoveryScore, 84)
        XCTAssertEqual(entries.first?.status, "좋음")
    }

    private func makeSummary(score: Int = 82) -> RecoverySummary {
        RecoverySummary(
            score: score,
            status: "좋음",
            description: "휴식일이 포함되어 회복 흐름이 안정적입니다.",
            recommendation: "오늘은 Z2 라이딩 40분을 추천해요.",
            trendText: "지난 7일 대비 +6점",
            coachMessage: RecoveryCoachMessage(
                coachName: "SOOM AI 코치",
                subtitle: "회복 우선 주간",
                message: "오늘은 강도를 올리기보다 회복 리듬을 유지하세요."
            ),
            recommendationCard: RecoveryRecommendation(
                title: "오늘의 추천",
                description: "짧고 편한 유산소가 적합합니다.",
                actionLabel: "40분 Z2 라이딩 보기",
                icon: SOOMIcon.bike
            ),
            trends: [],
            insights: [],
            lastUpdated: Date(timeIntervalSince1970: 1_800_000_000),
            dataQuality: .estimated
        )
    }

    private func makeSnapshot(
        date: Date? = nil,
        daysAgo: Int = 0,
        score: Int = 82,
        status: String = "좋음"
    ) -> DailyRecoverySnapshot {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshotDate = date ?? Calendar.current.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate

        return DailyRecoverySnapshot(
            date: snapshotDate,
            score: score,
            status: status,
            recommendation: "오늘은 가벼운 Z2를 추천해요.",
            coachMessage: "회복 리듬을 유지하세요.",
            explanation: "최근 회복 흐름이 안정적입니다.",
            dataQuality: .estimated,
            activityCount: 2
        )
    }

    @MainActor
    private func makeSwiftDataStore(referenceDate: Date) throws -> SwiftDataDailyRecoverySnapshotStore {
        let schema = Schema([DailyRecoverySnapshotRecord.self])
        let configuration = ModelConfiguration(
            "RecoveryTimelineBuilderTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        retainedContainers.append(container)

        return SwiftDataDailyRecoverySnapshotStore(
            modelContext: container.mainContext,
            referenceDate: { referenceDate }
        )
    }
}

private final class FakeDailyRecoverySnapshotStore: DailyRecoverySnapshotStore {
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
