import XCTest
@testable import SOOM

final class TrainingSettingsStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var store: TrainingSettingsStore!

    override func setUp() {
        super.setUp()
        let suiteName = "TrainingSettingsStoreTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        store = TrainingSettingsStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults = nil
        store = nil
        super.tearDown()
    }

    func testSaveAndLoadMaxHeartRate() {
        store.saveMaxHeartRate(188)

        XCTAssertEqual(store.loadSettings().maxHeartRate, 188)
    }

    func testSaveAndLoadCyclingFTP() {
        store.saveCyclingFTP(246)

        XCTAssertEqual(store.loadSettings().cyclingFTP, 246)
    }

    func testSaveAndLoadPrivacyDefault() {
        store.savePrivacyDefault(.followers)

        XCTAssertEqual(store.loadSettings().privacyDefault, .followers)
    }

    func testSaveAndLoadPreferredUnit() {
        store.savePreferredUnit(.imperial)

        XCTAssertEqual(store.loadSettings().preferredUnit, .imperial)
    }

    func testLoadZoneBaselineUsesSavedMaxHeartRateAndFTP() {
        store.saveMaxHeartRate(188)
        store.saveCyclingFTP(260)

        let baseline = store.loadZoneBaseline()

        XCTAssertEqual(baseline.maxHeartRate, 188)
        XCTAssertEqual(baseline.cyclingFTP, 260)
        XCTAssertTrue(baseline.hasPersonalizedHeartRate)
        XCTAssertTrue(baseline.hasPersonalizedPower)
    }

    func testSaveSettingsRoundTripsAllValues() {
        let settings = TrainingSettings(
            maxHeartRate: 192,
            cyclingFTP: 280,
            preferredUnit: .imperial,
            privacyDefault: .publicFeed
        )

        store.saveSettings(settings)

        XCTAssertEqual(store.loadSettings(), settings)
    }
}
