import XCTest
@testable import SOOM

@MainActor
final class CheckInHistoryViewModelTests: XCTestCase {
    func testLoadPopulatesCheckInsSortedByRecentDate() async {
        let latestDate = Date(timeIntervalSince1970: 1_800_000_200)
        let olderDate = latestDate.addingTimeInterval(-86_400)
        let latestCheckIn = makeCheckIn(date: latestDate, fatigue: 2)
        let olderCheckIn = makeCheckIn(date: olderDate, fatigue: 4)
        let viewModel = CheckInHistoryViewModel(
            store: FakeHistoryCheckInStore(checkIns: [olderCheckIn, latestCheckIn])
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.checkIns.map(\.id), [latestCheckIn.id, olderCheckIn.id])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadKeepsEmptyArrayWhenStoreIsEmpty() async {
        let viewModel = CheckInHistoryViewModel(
            store: FakeHistoryCheckInStore(checkIns: [])
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.checkIns.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadSetsErrorMessageWhenStoreFails() async {
        let viewModel = CheckInHistoryViewModel(
            store: FailingHistoryCheckInStore()
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.checkIns.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.errorMessage, "컨디션 기록을 불러오지 못했습니다.")
    }

    func testRemoveCheckInRemovesOnlyMatchingRecord() async {
        let latestDate = Date(timeIntervalSince1970: 1_800_000_200)
        let deletedCheckIn = makeCheckIn(date: latestDate, fatigue: 2)
        let remainingCheckIn = makeCheckIn(date: latestDate.addingTimeInterval(-86_400), fatigue: 4)
        let viewModel = CheckInHistoryViewModel(
            store: FakeHistoryCheckInStore(checkIns: [deletedCheckIn, remainingCheckIn])
        )

        await viewModel.load()
        viewModel.removeCheckIn(id: deletedCheckIn.id)

        XCTAssertEqual(viewModel.checkIns.map(\.id), [remainingCheckIn.id])
    }

    func testUpdateCheckInReplacesMatchingRecordAndKeepsSorting() async {
        let latestDate = Date(timeIntervalSince1970: 1_800_000_200)
        let editedCheckIn = makeCheckIn(date: latestDate, fatigue: 2)
        let olderCheckIn = makeCheckIn(date: latestDate.addingTimeInterval(-86_400), fatigue: 4)
        let viewModel = CheckInHistoryViewModel(
            store: FakeHistoryCheckInStore(checkIns: [olderCheckIn, editedCheckIn])
        )
        let updatedCheckIn = RecoveryCheckIn(
            id: editedCheckIn.id,
            date: editedCheckIn.date,
            fatigueLevel: 5,
            sleepQuality: 1,
            muscleSoreness: 4,
            moodLevel: 2,
            note: "수정된 기록"
        )

        await viewModel.load()
        viewModel.updateCheckIn(updatedCheckIn)

        XCTAssertEqual(viewModel.checkIns.map(\.id), [updatedCheckIn.id, olderCheckIn.id])
        XCTAssertEqual(viewModel.checkIns.first?.fatigueLevel, 5)
        XCTAssertEqual(viewModel.checkIns.first?.sleepQuality, 1)
        XCTAssertEqual(viewModel.checkIns.first?.note, "수정된 기록")
    }

    private func makeCheckIn(date: Date, fatigue: Int) -> RecoveryCheckIn {
        RecoveryCheckIn(
            date: date,
            fatigueLevel: fatigue,
            sleepQuality: 3,
            muscleSoreness: 2,
            moodLevel: 4,
            note: nil
        )
    }
}

private struct FakeHistoryCheckInStore: RecoveryCheckInStore {
    let checkIns: [RecoveryCheckIn]

    func fetchRecentCheckIns(days: Int) async throws -> [RecoveryCheckIn] {
        checkIns
    }
}

private struct FailingHistoryCheckInStore: RecoveryCheckInStore {
    func fetchRecentCheckIns(days: Int) async throws -> [RecoveryCheckIn] {
        throw HistoryViewModelTestError.expectedFailure
    }
}

private enum HistoryViewModelTestError: Error {
    case expectedFailure
}
