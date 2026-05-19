import SwiftData
import XCTest
@testable import SOOM

@MainActor
final class SwiftDataCheckInStoreTests: XCTestCase {
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    func testSaveCheckInThenFetchesItBack() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try makeStore(referenceDate: referenceDate)
        let checkIn = makeCheckIn(date: referenceDate, fatigue: 4, note: "다리 피로")

        try await store.saveCheckIn(checkIn)
        let fetched = try await store.fetchRecentCheckIns(days: 7)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, checkIn.id)
        XCTAssertEqual(fetched.first?.fatigueLevel, 4)
        XCTAssertEqual(fetched.first?.note, "다리 피로")
    }

    func testFetchRecentCheckInsFiltersByDays() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try makeStore(referenceDate: referenceDate)
        let recent = makeCheckIn(date: referenceDate.addingTimeInterval(-2 * 86_400))
        let old = makeCheckIn(date: referenceDate.addingTimeInterval(-10 * 86_400))

        try await store.saveCheckIn(recent)
        try await store.saveCheckIn(old)
        let fetched = try await store.fetchRecentCheckIns(days: 7)

        XCTAssertEqual(fetched.map(\.id), [recent.id])
    }

    func testStoredValuesStayWithinOneToFive() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try makeStore(referenceDate: referenceDate)
        let checkIn = RecoveryCheckIn(
            date: referenceDate,
            fatigueLevel: 9,
            sleepQuality: 0,
            muscleSoreness: 7,
            moodLevel: -2,
            note: nil
        )

        try await store.saveCheckIn(checkIn)
        let fetched = try await store.fetchRecentCheckIns(days: 7)

        XCTAssertEqual(fetched.first?.fatigueLevel, 5)
        XCTAssertEqual(fetched.first?.sleepQuality, 1)
        XCTAssertEqual(fetched.first?.muscleSoreness, 5)
        XCTAssertEqual(fetched.first?.moodLevel, 1)
    }

    func testUpdateCheckInChangesStoredValues() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try makeStore(referenceDate: referenceDate)
        let checkIn = makeCheckIn(date: referenceDate, fatigue: 2, note: "처음 기록")
        let updatedCheckIn = RecoveryCheckIn(
            id: checkIn.id,
            date: referenceDate,
            fatigueLevel: 5,
            sleepQuality: 2,
            muscleSoreness: 4,
            moodLevel: 3,
            note: "수정된 기록"
        )

        try await store.saveCheckIn(checkIn)
        try await store.updateCheckIn(updatedCheckIn)
        let fetched = try await store.fetchRecentCheckIns(days: 7)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, checkIn.id)
        XCTAssertEqual(fetched.first?.fatigueLevel, 5)
        XCTAssertEqual(fetched.first?.sleepQuality, 2)
        XCTAssertEqual(fetched.first?.muscleSoreness, 4)
        XCTAssertEqual(fetched.first?.note, "수정된 기록")
    }

    func testDeleteCheckInRemovesStoredRecord() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try makeStore(referenceDate: referenceDate)
        let deletedCheckIn = makeCheckIn(date: referenceDate, fatigue: 4)
        let remainingCheckIn = makeCheckIn(date: referenceDate.addingTimeInterval(-86_400), fatigue: 2)

        try await store.saveCheckIn(deletedCheckIn)
        try await store.saveCheckIn(remainingCheckIn)
        try await store.deleteCheckIn(id: deletedCheckIn.id)
        let fetched = try await store.fetchRecentCheckIns(days: 7)

        XCTAssertEqual(fetched.map(\.id), [remainingCheckIn.id])
    }

    func testDeleteMissingCheckInDoesNotChangeStoredRecords() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try makeStore(referenceDate: referenceDate)
        let existingCheckIn = makeCheckIn(date: referenceDate, fatigue: 4)

        try await store.saveCheckIn(existingCheckIn)
        try await store.deleteCheckIn(id: UUID())
        let fetched = try await store.fetchRecentCheckIns(days: 7)

        XCTAssertEqual(fetched.map(\.id), [existingCheckIn.id])
    }

    func testDeleteAllCheckInsClearsStore() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try makeStore(referenceDate: referenceDate)

        try await store.saveCheckIn(makeCheckIn(date: referenceDate, fatigue: 4))
        try await store.saveCheckIn(makeCheckIn(date: referenceDate.addingTimeInterval(-86_400), fatigue: 2))
        try await store.deleteAllCheckIns()
        let fetched = try await store.fetchRecentCheckIns(days: 7)

        XCTAssertTrue(fetched.isEmpty)
    }

    private func makeStore(referenceDate: Date) throws -> SwiftDataCheckInStore {
        let schema = Schema([CheckInRecord.self])
        let configuration = ModelConfiguration(
            "SwiftDataCheckInStoreTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        retainedContainers.append(container)

        return SwiftDataCheckInStore(
            modelContext: container.mainContext,
            referenceDate: { referenceDate }
        )
    }

    private func makeCheckIn(
        date: Date,
        fatigue: Int = 3,
        sleepQuality: Int = 4,
        muscleSoreness: Int = 2,
        mood: Int = 4,
        note: String? = nil
    ) -> RecoveryCheckIn {
        RecoveryCheckIn(
            date: date,
            fatigueLevel: fatigue,
            sleepQuality: sleepQuality,
            muscleSoreness: muscleSoreness,
            moodLevel: mood,
            note: note
        )
    }
}
