import XCTest
@testable import SOOM

@MainActor
final class CheckInDetailViewModelTests: XCTestCase {
    func testDeleteSuccessCallsStoreAndDeletedCallback() async {
        let checkIn = makeCheckIn()
        let store = FakeEditableCheckInStore(checkIns: [checkIn])
        var deletedID: UUID?
        let viewModel = CheckInDetailViewModel(store: store) { id in
            deletedID = id
        }

        let didDelete = await viewModel.deleteCheckIn(id: checkIn.id)

        XCTAssertTrue(didDelete)
        XCTAssertEqual(deletedID, checkIn.id)
        XCTAssertTrue(store.checkIns.isEmpty)
        XCTAssertFalse(viewModel.isDeleting)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testDeleteFailureSetsErrorMessageAndDoesNotCallCallback() async {
        let checkIn = makeCheckIn()
        let store = FakeEditableCheckInStore(checkIns: [checkIn], shouldFailDelete: true)
        var deletedID: UUID?
        let viewModel = CheckInDetailViewModel(store: store) { id in
            deletedID = id
        }

        let didDelete = await viewModel.deleteCheckIn(id: checkIn.id)

        XCTAssertFalse(didDelete)
        XCTAssertNil(deletedID)
        XCTAssertEqual(store.checkIns.map(\.id), [checkIn.id])
        XCTAssertFalse(viewModel.isDeleting)
        XCTAssertEqual(viewModel.errorMessage, "기록을 삭제하지 못했습니다. 잠시 후 다시 시도해 주세요.")
    }

    private func makeCheckIn() -> RecoveryCheckIn {
        RecoveryCheckIn(
            date: Date(timeIntervalSince1970: 1_800_000_000),
            fatigueLevel: 3,
            sleepQuality: 4,
            muscleSoreness: 2,
            moodLevel: 4,
            note: "테스트 기록"
        )
    }
}

private final class FakeEditableCheckInStore: RecoveryCheckInEditableStore {
    var checkIns: [RecoveryCheckIn]
    let shouldFailDelete: Bool

    init(checkIns: [RecoveryCheckIn], shouldFailDelete: Bool = false) {
        self.checkIns = checkIns
        self.shouldFailDelete = shouldFailDelete
    }

    func fetchRecentCheckIns(days: Int) async throws -> [RecoveryCheckIn] {
        checkIns
    }

    func saveCheckIn(_ checkIn: RecoveryCheckIn) async throws {
        checkIns.append(checkIn)
    }

    func updateCheckIn(_ checkIn: RecoveryCheckIn) async throws {
        guard let index = checkIns.firstIndex(where: { $0.id == checkIn.id }) else {
            return
        }

        checkIns[index] = checkIn
    }

    func deleteCheckIn(id: UUID) async throws {
        if shouldFailDelete {
            throw CheckInDetailViewModelTestError.expectedFailure
        }

        checkIns.removeAll { $0.id == id }
    }

    func deleteAllCheckIns() async throws {
        checkIns.removeAll()
    }
}

private enum CheckInDetailViewModelTestError: Error {
    case expectedFailure
}
