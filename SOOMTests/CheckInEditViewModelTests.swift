import XCTest
@testable import SOOM

@MainActor
final class CheckInEditViewModelTests: XCTestCase {
    func testInitializesWithExistingCheckInValues() {
        let checkIn = makeCheckIn(
            fatigue: 4,
            sleepQuality: 2,
            muscleSoreness: 3,
            mood: 5,
            note: "기존 메모"
        )

        let viewModel = CheckInEditViewModel(checkIn: checkIn)

        XCTAssertEqual(viewModel.fatigueLevel, 4)
        XCTAssertEqual(viewModel.sleepQuality, 2)
        XCTAssertEqual(viewModel.muscleSoreness, 3)
        XCTAssertEqual(viewModel.moodLevel, 5)
        XCTAssertEqual(viewModel.note, "기존 메모")
    }

    func testSaveUpdatesExistingCheckInInStore() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let original = makeCheckIn(date: referenceDate, fatigue: 2, note: "처음 기록")
        let store = MockRecoveryCheckInStore(referenceDate: referenceDate, checkIns: [original])
        let viewModel = CheckInEditViewModel(checkIn: original, store: store)

        viewModel.fatigueLevel = 5
        viewModel.sleepQuality = 2
        viewModel.muscleSoreness = 4
        viewModel.moodLevel = 3
        viewModel.note = "  수정된 기록  "

        let updated = await viewModel.save()
        let fetched = try await store.fetchRecentCheckIns(days: 7)

        XCTAssertEqual(updated?.id, original.id)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, original.id)
        XCTAssertEqual(fetched.first?.fatigueLevel, 5)
        XCTAssertEqual(fetched.first?.sleepQuality, 2)
        XCTAssertEqual(fetched.first?.muscleSoreness, 4)
        XCTAssertEqual(fetched.first?.moodLevel, 3)
        XCTAssertEqual(fetched.first?.note, "수정된 기록")
        XCTAssertEqual(viewModel.confirmationMessage, "컨디션 기록을 수정했어요.")
    }

    func testSavePreservesOriginalDateAndClearsBlankNote() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let original = makeCheckIn(date: referenceDate, note: "기존 메모")
        let store = MockRecoveryCheckInStore(referenceDate: referenceDate, checkIns: [original])
        let viewModel = CheckInEditViewModel(checkIn: original, store: store)

        viewModel.note = "   "

        _ = await viewModel.save()
        let fetched = try await store.fetchRecentCheckIns(days: 7)

        XCTAssertEqual(fetched.first?.date, referenceDate)
        XCTAssertNil(fetched.first?.note)
    }

    private func makeCheckIn(
        date: Date = Date(timeIntervalSince1970: 1_800_000_000),
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

