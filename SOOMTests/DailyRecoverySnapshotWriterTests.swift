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

    func testEmptySummaryDoesNotPersistWithOrWithoutCheckIn() async throws {
        let store = CapturingDailyRecoverySnapshotStore()
        let writer = DailyRecoverySnapshotWriter(snapshotStore: store)
        let empty = RecoveryCalculator().calculateSummary(from: [])
        let checkIn = RecoveryCheckIn(date: Date(), fatigueLevel: 4, sleepQuality: 3,
                                      muscleSoreness: 2, moodLevel: 4, note: nil)
        try await writer.saveTodaySnapshot(from: empty, latestCheckIn: nil, explanation: nil)
        let personalized = RecoverySummaryComposer().compose(baseSummary: empty, latestCheckIn: checkIn)
        try await writer.saveTodaySnapshot(from: personalized, latestCheckIn: checkIn, explanation: nil)
        XCTAssertTrue(store.savedSnapshots.isEmpty)
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

extension DailyRecoverySnapshotWriterTests {
    func testActualDayCountSurvivesCheckInCompositionAndSnapshotWriting() async throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let summary = RecoveryCalculator(referenceDate: date).calculateSummary(from: [
            RecoveryActivity(workoutType: .ride, durationMinutes: 30, distanceKm: 10, averageHeartRate: 0, relativeEffort: 30, trainingLoad: 35, completedAt: date),
            RecoveryActivity(workoutType: .run, durationMinutes: 20, distanceKm: 3, averageHeartRate: 0, relativeEffort: 20, trainingLoad: 25, completedAt: date.addingTimeInterval(-86_400))
        ])
        let checkIn = RecoveryCheckIn(date: date, fatigueLevel: 3, sleepQuality: 3, muscleSoreness: 3, moodLevel: 3, note: nil)
        let personalized = RecoverySummaryComposer().compose(baseSummary: summary, latestCheckIn: checkIn)
        let store = CapturingDailyRecoverySnapshotStore()
        let writer = DailyRecoverySnapshotWriter(snapshotStore: store, referenceDate: { date })
        try await writer.saveTodaySnapshot(from: personalized, latestCheckIn: checkIn, explanation: nil)
        XCTAssertEqual(store.savedSnapshots.first?.activityCount, 1)
        XCTAssertEqual(store.savedSnapshots.first?.activityCountKnown, true)
        let nextDayWriter = DailyRecoverySnapshotWriter(snapshotStore: store, referenceDate: { date.addingTimeInterval(86_400) })
        let stale = nextDayWriter.makeTodaySnapshot(from: personalized, latestCheckIn: nil, explanation: nil)
        XCTAssertFalse(stale.activityCountKnown, "Yesterday's count must not be assigned to today")
        let legacy = writer.makeTodaySnapshot(from: .mockToday, latestCheckIn: nil, explanation: nil)
        XCTAssertFalse(legacy.activityCountKnown)
    }
}
