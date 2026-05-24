import XCTest
@testable import SOOM

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var store: TrainingSettingsStore!

    override func setUp() {
        super.setUp()
        let suiteName = "SettingsViewModelTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        store = TrainingSettingsStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults = nil
        store = nil
        super.tearDown()
    }

    func testValidMaxHeartRateIsSaved() {
        let viewModel = SettingsViewModel(store: store)
        viewModel.maxHeartRateText = "187"

        XCTAssertTrue(viewModel.saveMaxHeartRate())
        XCTAssertEqual(viewModel.settings.maxHeartRate, 187)
        XCTAssertEqual(store.loadSettings().maxHeartRate, 187)
    }

    func testInvalidMaxHeartRateIsRejected() {
        let viewModel = SettingsViewModel(store: store)
        viewModel.maxHeartRateText = "260"

        XCTAssertFalse(viewModel.saveMaxHeartRate())
        XCTAssertNil(store.loadSettings().maxHeartRate)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testValidCyclingFTPIsSaved() {
        let viewModel = SettingsViewModel(store: store)
        viewModel.cyclingFTPText = "255"

        XCTAssertTrue(viewModel.saveCyclingFTP())
        XCTAssertEqual(viewModel.settings.cyclingFTP, 255)
        XCTAssertEqual(store.loadSettings().cyclingFTP, 255)
    }

    func testInvalidCyclingFTPIsRejected() {
        let viewModel = SettingsViewModel(store: store)
        viewModel.cyclingFTPText = "20"

        XCTAssertFalse(viewModel.saveCyclingFTP())
        XCTAssertNil(store.loadSettings().cyclingFTP)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testPrivacyDefaultIsSaved() {
        let viewModel = SettingsViewModel(store: store)

        viewModel.updatePrivacyDefault(.followers)

        XCTAssertEqual(viewModel.settings.privacyDefault, .followers)
        XCTAssertEqual(store.loadSettings().privacyDefault, .followers)
    }

    func testViewModelDoesNotUseRecoveryCalculator() {
        let viewModel = SettingsViewModel(store: store)

        viewModel.updatePreferredUnit(.imperial)
        viewModel.updatePrivacyDefault(.privateOnly)

        XCTAssertEqual(viewModel.settings.preferredUnit, .imperial)
        XCTAssertEqual(viewModel.settings.privacyDefault, .privateOnly)
    }
}
