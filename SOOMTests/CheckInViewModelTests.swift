import XCTest
@testable import SOOM

@MainActor
final class CheckInViewModelTests: XCTestCase {
    func testSaveAppendsCheckInToMockStore() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MockRecoveryCheckInStore(referenceDate: referenceDate, checkIns: [])
        let viewModel = CheckInViewModel(
            store: store,
            now: { referenceDate }
        )

        viewModel.fatigueLevel = 4
        viewModel.sleepQuality = 2
        viewModel.muscleSoreness = 3
        viewModel.moodLevel = 5
        viewModel.note = "  다리가 조금 무거움  "

        await viewModel.save()

        let savedCheckIns = try await store.fetchRecentCheckIns(days: 1)
        XCTAssertEqual(savedCheckIns.count, 1)
        XCTAssertEqual(savedCheckIns.first?.fatigueLevel, 4)
        XCTAssertEqual(savedCheckIns.first?.sleepQuality, 2)
        XCTAssertEqual(savedCheckIns.first?.muscleSoreness, 3)
        XCTAssertEqual(savedCheckIns.first?.moodLevel, 5)
        XCTAssertEqual(savedCheckIns.first?.note, "다리가 조금 무거움")
        XCTAssertEqual(viewModel.confirmationMessage, "오늘의 회복 해석이 더 정확해졌어요.")
    }
}
