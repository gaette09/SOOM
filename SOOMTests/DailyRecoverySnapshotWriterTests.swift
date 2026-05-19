import XCTest
@testable import SOOM

final class DailyRecoverySnapshotWriterTests: XCTestCase {
    func testMakeTodaySnapshotKeepsSummaryScoreStatusAndRecommendation() {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let checkIn = RecoveryCheckIn(
            date: referenceDate,
            fatigueLevel: 4,
            sleepQuality: 3,
            muscleSoreness: 2,
            moodLevel: 4,
            note: nil
        )
        let writer = DailyRecoverySnapshotWriter(
            snapshotStore: CapturingDailyRecoverySnapshotStore(),
            referenceDate: { referenceDate }
        )

        let snapshot = writer.makeTodaySnapshot(
            from: .mockToday,
            latestCheckIn: checkIn,
            explanation: "최근 회복 흐름이 안정적입니다.",
            activityCount: 0
        )

        XCTAssertEqual(snapshot.date, referenceDate)
        XCTAssertEqual(snapshot.score, RecoverySummary.mockToday.score)
        XCTAssertEqual(snapshot.status, RecoverySummary.mockToday.status)
        XCTAssertEqual(snapshot.recommendation, RecoverySummary.mockToday.recommendation)
        XCTAssertEqual(snapshot.coachMessage, RecoverySummary.mockToday.coachMessage.message)
        XCTAssertEqual(snapshot.explanation, "최근 회복 흐름이 안정적입니다.")
        XCTAssertEqual(snapshot.checkInId, checkIn.id)
        XCTAssertEqual(snapshot.activityCount, 0)
    }

    func testSaveTodaySnapshotPersistsSnapshotThroughStore() async throws {
        let store = CapturingDailyRecoverySnapshotStore()
        let writer = DailyRecoverySnapshotWriter(
            snapshotStore: store,
            referenceDate: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        try await writer.saveTodaySnapshot(
            from: .mockToday,
            latestCheckIn: nil,
            explanation: "오늘 회복 상태 설명",
            activityCount: 0
        )

        XCTAssertEqual(store.savedSnapshots.count, 1)
        XCTAssertEqual(store.savedSnapshots.first?.score, RecoverySummary.mockToday.score)
        XCTAssertEqual(store.savedSnapshots.first?.status, RecoverySummary.mockToday.status)
        XCTAssertEqual(store.savedSnapshots.first?.recommendation, RecoverySummary.mockToday.recommendation)
    }
}

private final class CapturingDailyRecoverySnapshotStore: DailyRecoverySnapshotStore {
    private(set) var savedSnapshots: [DailyRecoverySnapshot] = []

    func saveSnapshot(_ snapshot: DailyRecoverySnapshot) async throws {
        savedSnapshots.append(snapshot)
    }

    func fetchRecentSnapshots(days: Int) async throws -> [DailyRecoverySnapshot] {
        savedSnapshots
    }

    func fetchSnapshot(for date: Date) async throws -> DailyRecoverySnapshot? {
        savedSnapshots.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func deleteSnapshot(id: UUID) async throws {
        savedSnapshots.removeAll { $0.id == id }
    }
}
