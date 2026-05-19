import XCTest
@testable import SOOM

@MainActor
final class HealthKitSettingsViewModelTests: XCTestCase {
    func testInitialStatusShowsAvailableNotRequested() {
        let viewModel = HealthKitSettingsViewModel(
            manager: FakeHealthKitManager(isAvailable: true)
        )

        XCTAssertEqual(viewModel.status.title, HealthKitConnectionStatus.notRequested.title)
        XCTAssertTrue(viewModel.canRequestAuthorization)
    }

    func testInitialStatusShowsUnavailable() {
        let viewModel = HealthKitSettingsViewModel(
            manager: FakeHealthKitManager(isAvailable: false)
        )

        XCTAssertEqual(viewModel.status.title, HealthKitConnectionStatus.notAvailable.title)
        XCTAssertFalse(viewModel.canRequestAuthorization)
    }

    func testAuthorizationSuccessMovesToCheckNeededState() async {
        let manager = FakeHealthKitManager(isAvailable: true)
        let viewModel = HealthKitSettingsViewModel(manager: manager)

        await viewModel.requestAuthorization()

        XCTAssertTrue(manager.didRequestAuthorization)
        XCTAssertEqual(viewModel.status.title, HealthKitConnectionStatus.accessLimited.title)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testAuthorizationFailureSetsErrorMessage() async {
        let viewModel = HealthKitSettingsViewModel(
            manager: FakeHealthKitManager(isAvailable: true, error: TestError.authorizationFailed)
        )

        await viewModel.requestAuthorization()

        XCTAssertEqual(viewModel.status.title, HealthKitConnectionStatus.accessLimited.title)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testUnavailableRequestDoesNotCallAuthorization() async {
        let manager = FakeHealthKitManager(isAvailable: false)
        let viewModel = HealthKitSettingsViewModel(manager: manager)

        await viewModel.requestAuthorization()

        XCTAssertFalse(manager.didRequestAuthorization)
        XCTAssertEqual(viewModel.status.title, HealthKitConnectionStatus.notAvailable.title)
        XCTAssertNotNil(viewModel.errorMessage)
    }
}

private final class FakeHealthKitManager: HealthKitManaging {
    private let isAvailable: Bool
    private let error: Error?
    private(set) var didRequestAuthorization = false

    init(isAvailable: Bool, error: Error? = nil) {
        self.isAvailable = isAvailable
        self.error = error
    }

    func isHealthDataAvailable() -> Bool {
        isAvailable
    }

    func requestAuthorization() async throws {
        didRequestAuthorization = true

        if let error {
            throw error
        }
    }
}

private enum TestError: Error {
    case authorizationFailed
}
