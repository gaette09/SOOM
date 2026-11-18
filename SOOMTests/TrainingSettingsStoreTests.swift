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

    func testNewSettingsUsePrivateSharingByDefault() {
        XCTAssertEqual(TrainingSettings().privacyDefault, .privateOnly)
        XCTAssertEqual(store.loadSettings().privacyDefault, .privateOnly)
        XCTAssertFalse(store.hasAnySavedTrainingSetting(), "Reading the default must not rewrite preferences")
    }

    func testExistingPublicPreferenceIsPreservedWhenLoading() {
        store.savePrivacyDefault(.publicFeed)

        XCTAssertEqual(store.loadSettings().privacyDefault, .publicFeed)
        XCTAssertEqual(userDefaults.string(forKey: "training.privacyDefault"), ShareableWorkoutVisibility.publicFeed.rawValue)
    }

    func testUnknownPrivacyPreferenceFallsBackToPrivateWithoutRewritingIt() {
        userDefaults.set("unknown-visibility", forKey: "training.privacyDefault")

        XCTAssertEqual(store.loadSettings().privacyDefault, .privateOnly)
        XCTAssertEqual(userDefaults.string(forKey: "training.privacyDefault"), "unknown-visibility")
    }

    func testSaveAndLoadMaxHeartRate() {
        store.saveMaxHeartRate(188)

        XCTAssertEqual(store.loadSettings().maxHeartRate, 188)
    }

    func testHasAnySavedTrainingSettingStartsFalse() {
        XCTAssertFalse(store.hasAnySavedTrainingSetting())
    }

    func testHasAnySavedTrainingSettingDetectsSavedValue() {
        store.saveMaxHeartRate(188)

        XCTAssertTrue(store.hasAnySavedTrainingSetting())
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

    func testResetAllClearsEverySavedValue() {
        store.saveSettings(
            TrainingSettings(
                maxHeartRate: 192,
                cyclingFTP: 280,
                preferredUnit: .imperial,
                privacyDefault: .publicFeed
            )
        )

        store.resetAll()

        XCTAssertFalse(store.hasAnySavedTrainingSetting())
        XCTAssertEqual(store.loadSettings(), TrainingSettings())
    }
}

extension TrainingSettingsStoreTests {
    func testAccountsAndGuestKeepIndependentHealthBaselines() {
        let a = UUID(), b = UUID()
        let accountA = TrainingSettingsStore(userDefaults: userDefaults, userID: a)
        let accountB = TrainingSettingsStore(userDefaults: userDefaults, userID: b)
        store.saveMaxHeartRate(170)
        accountA.saveMaxHeartRate(190)
        accountA.saveCyclingFTP(240)
        accountB.saveMaxHeartRate(180)
        XCTAssertEqual(store.loadSettings().maxHeartRate, 170)
        XCTAssertEqual(accountA.loadSettings().maxHeartRate, 190)
        XCTAssertEqual(accountB.loadSettings().maxHeartRate, 180)
        XCTAssertNil(accountB.loadSettings().cyclingFTP)
        accountA.resetAll()
        XCTAssertNil(accountA.loadSettings().maxHeartRate)
        XCTAssertEqual(accountB.loadSettings().maxHeartRate, 180)
        XCTAssertEqual(store.loadSettings().maxHeartRate, 170)
    }

    func testAccountSharingDefaultDoesNotInheritGuestOrAnotherAccount() {
        store.savePrivacyDefault(.publicFeed)
        let a = TrainingSettingsStore(userDefaults: userDefaults, userID: UUID())
        let b = TrainingSettingsStore(userDefaults: userDefaults, userID: UUID())
        XCTAssertEqual(a.loadSettings().privacyDefault, .privateOnly)
        a.savePrivacyDefault(.publicFeed)
        XCTAssertEqual(b.loadSettings().privacyDefault, .privateOnly)
        a.saveMaxHeartRate(195)
        XCTAssertNil(b.loadSettings().maxHeartRate)
    }
}
