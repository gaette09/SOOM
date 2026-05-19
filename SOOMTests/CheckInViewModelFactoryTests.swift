import SwiftData
import XCTest
@testable import SOOM

@MainActor
final class CheckInViewModelFactoryTests: XCTestCase {
    func testFactoryCreatesViewModelWithInjectedStore() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_100)
        let store = MockRecoveryCheckInStore(referenceDate: referenceDate, checkIns: [])
        let factory = CheckInViewModelFactory(
            store: store,
            now: { referenceDate }
        )
        let viewModel = factory.makeViewModel()

        viewModel.fatigueLevel = 5
        await viewModel.save()

        let savedCheckIns = try await store.fetchRecentCheckIns(days: 1)
        XCTAssertEqual(savedCheckIns.count, 1)
        XCTAssertEqual(savedCheckIns.first?.fatigueLevel, 5)
        XCTAssertEqual(savedCheckIns.first?.date, referenceDate)
    }

    func testSwiftDataFactoryCreatesViewModelBackedBySwiftDataStore() async throws {
        let container = try makeInMemoryContainer()
        let viewModel = CheckInViewModelFactory.makeSwiftDataViewModel(
            modelContext: container.mainContext
        )

        viewModel.fatigueLevel = 4
        viewModel.sleepQuality = 2
        viewModel.muscleSoreness = 3
        viewModel.moodLevel = 4
        await viewModel.save()

        let store = SwiftDataCheckInStore(modelContext: container.mainContext)
        let savedCheckIns = try await store.fetchRecentCheckIns(days: 30)

        XCTAssertEqual(savedCheckIns.count, 1)
        XCTAssertEqual(savedCheckIns.first?.fatigueLevel, 4)
        XCTAssertEqual(savedCheckIns.first?.sleepQuality, 2)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([CheckInRecord.self])
        let configuration = ModelConfiguration(
            "CheckInViewModelFactoryTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
