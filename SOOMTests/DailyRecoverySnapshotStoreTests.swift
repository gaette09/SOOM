import SwiftData
import XCTest
@testable import SOOM

@MainActor
final class DailyRecoverySnapshotStoreTests: XCTestCase {
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    func testSaveSnapshotThenFetchRecentSnapshots() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try makeStore(referenceDate: referenceDate)
        let snapshot = makeSnapshot(date: referenceDate, score: 82)

        try await store.saveSnapshot(snapshot)
        let fetched = try await store.fetchRecentSnapshots(days: 7)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, snapshot.id)
        XCTAssertEqual(fetched.first?.score, 82)
        XCTAssertEqual(fetched.first?.dataQuality, .estimated)
    }

    func testSavingSameCalendarDayUpsertsSnapshot() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try makeStore(referenceDate: referenceDate)
        let first = makeSnapshot(date: referenceDate, score: 78, status: "보통")
        let second = makeSnapshot(
            date: referenceDate.addingTimeInterval(60 * 60 * 4),
            score: 86,
            status: "좋음",
            recommendation: "가벼운 Z2 라이딩을 추천해요."
        )

        try await store.saveSnapshot(first)
        try await store.saveSnapshot(second)
        let fetched = try await store.fetchRecentSnapshots(days: 7)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, second.id)
        XCTAssertEqual(fetched.first?.score, 86)
        XCTAssertEqual(fetched.first?.status, "좋음")
        XCTAssertEqual(fetched.first?.recommendation, "가벼운 Z2 라이딩을 추천해요.")
    }

    func testFetchSnapshotForDateReturnsMatchingDay() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try makeStore(referenceDate: referenceDate)
        let snapshot = makeSnapshot(date: referenceDate.addingTimeInterval(60 * 60 * 6), score: 80)

        try await store.saveSnapshot(snapshot)
        let fetched = try await store.fetchSnapshot(for: referenceDate)

        XCTAssertEqual(fetched?.id, snapshot.id)
        XCTAssertEqual(fetched?.score, 80)
    }

    func testDeleteSnapshotRemovesStoredSnapshot() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try makeStore(referenceDate: referenceDate)
        let deleted = makeSnapshot(date: referenceDate, score: 82)
        let remaining = makeSnapshot(date: referenceDate.addingTimeInterval(-86_400), score: 79)

        try await store.saveSnapshot(deleted)
        try await store.saveSnapshot(remaining)
        try await store.deleteSnapshot(id: deleted.id)
        let fetched = try await store.fetchRecentSnapshots(days: 7)

        XCTAssertEqual(fetched.map(\.id), [remaining.id])
    }

    func testFetchRecentSnapshotsFiltersByDays() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try makeStore(referenceDate: referenceDate)
        let recent = makeSnapshot(date: referenceDate.addingTimeInterval(-2 * 86_400), score: 82)
        let old = makeSnapshot(date: referenceDate.addingTimeInterval(-8 * 86_400), score: 70)

        try await store.saveSnapshot(recent)
        try await store.saveSnapshot(old)
        let fetched = try await store.fetchRecentSnapshots(days: 7)

        XCTAssertEqual(fetched.map(\.id), [recent.id])
    }

    private func makeStore(referenceDate: Date) throws -> SwiftDataDailyRecoverySnapshotStore {
        let schema = Schema([DailyRecoverySnapshotRecord.self])
        let configuration = ModelConfiguration(
            "DailyRecoverySnapshotStoreTests-\(UUID().uuidString)",
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

    private func makeSnapshot(
        date: Date,
        score: Int,
        status: String = "좋음",
        recommendation: String = "오늘은 회복 리듬을 유지하세요."
    ) -> DailyRecoverySnapshot {
        DailyRecoverySnapshot(
            date: date,
            score: score,
            status: status,
            recommendation: recommendation,
            coachMessage: "훈련 흐름은 안정적입니다.",
            explanation: "휴식일이 포함되어 회복 흐름이 안정적이에요.",
            dataQuality: .estimated,
            activityCount: 4,
            checkInId: UUID()
        )
    }
}
