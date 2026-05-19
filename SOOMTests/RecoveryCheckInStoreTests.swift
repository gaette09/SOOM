import XCTest
@testable import SOOM

final class RecoveryCheckInStoreTests: XCTestCase {
    func testMockCheckInsAreNotEmpty() async throws {
        let checkIns = try await MockRecoveryCheckInStore().fetchRecentCheckIns(days: 7)

        XCTAssertFalse(checkIns.isEmpty)
    }

    func testMockCheckInScaleValuesStayWithinOneToFive() async throws {
        let checkIns = try await MockRecoveryCheckInStore().fetchRecentCheckIns(days: 7)

        for checkIn in checkIns {
            XCTAssertTrue((1...5).contains(checkIn.fatigueLevel))
            XCTAssertTrue((1...5).contains(checkIn.sleepQuality))
            XCTAssertTrue((1...5).contains(checkIn.muscleSoreness))
            XCTAssertTrue((1...5).contains(checkIn.moodLevel))
        }
    }

    func testWeeklySummaryAveragesCheckIns() {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let checkIns = [
            makeCheckIn(date: referenceDate, fatigue: 2, sleep: 4, soreness: 1),
            makeCheckIn(date: referenceDate.addingTimeInterval(-86_400), fatigue: 4, sleep: 2, soreness: 3)
        ]

        let summary = RecoveryCheckInSummary.make(from: checkIns)

        XCTAssertEqual(summary.latestCheckIn?.date, referenceDate)
        XCTAssertEqual(summary.weeklyAverageFatigue, 3.0, accuracy: 0.001)
        XCTAssertEqual(summary.weeklyAverageSleepQuality, 3.0, accuracy: 0.001)
        XCTAssertEqual(summary.weeklyAverageSoreness, 2.0, accuracy: 0.001)
    }

    func testMockStoreSupportsUpdateDeleteAndDeleteAll() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let firstCheckIn = makeCheckIn(date: referenceDate, fatigue: 2, sleep: 4, soreness: 1)
        let secondCheckIn = makeCheckIn(date: referenceDate.addingTimeInterval(-86_400), fatigue: 4, sleep: 2, soreness: 3)
        let store = MockRecoveryCheckInStore(referenceDate: referenceDate, checkIns: [
            firstCheckIn,
            secondCheckIn
        ])
        let updatedFirstCheckIn = RecoveryCheckIn(
            id: firstCheckIn.id,
            date: firstCheckIn.date,
            fatigueLevel: 5,
            sleepQuality: 3,
            muscleSoreness: 2,
            moodLevel: 3,
            note: "수정"
        )

        try await store.updateCheckIn(updatedFirstCheckIn)
        var fetched = try await store.fetchRecentCheckIns(days: 7)
        XCTAssertEqual(fetched.first { $0.id == firstCheckIn.id }?.fatigueLevel, 5)
        XCTAssertEqual(fetched.first { $0.id == firstCheckIn.id }?.note, "수정")

        try await store.deleteCheckIn(id: secondCheckIn.id)
        fetched = try await store.fetchRecentCheckIns(days: 7)
        XCTAssertEqual(fetched.map(\.id), [firstCheckIn.id])

        try await store.deleteAllCheckIns()
        fetched = try await store.fetchRecentCheckIns(days: 7)
        XCTAssertTrue(fetched.isEmpty)
    }

    private func makeCheckIn(
        date: Date,
        fatigue: Int,
        sleep: Int,
        soreness: Int
    ) -> RecoveryCheckIn {
        RecoveryCheckIn(
            date: date,
            fatigueLevel: fatigue,
            sleepQuality: sleep,
            muscleSoreness: soreness,
            moodLevel: 3,
            note: nil
        )
    }
}
