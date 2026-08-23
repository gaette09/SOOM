import XCTest
@testable import SOOM

final class OnboardingStateStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var store: OnboardingStateStore!

    override func setUp() {
        super.setUp()
        let suiteName = "OnboardingStateStoreTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        store = OnboardingStateStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults = nil
        store = nil
        super.tearDown()
    }

    func testHasCompletedOnboardingStartsFalse() {
        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    func testMarkOnboardingCompletedPersists() {
        store.markOnboardingCompleted()

        XCTAssertTrue(store.hasCompletedOnboarding)
    }

    func testMarkOnboardingCompletedSurvivesReconstructionWithSameUserDefaults() {
        store.markOnboardingCompleted()
        let reloaded = OnboardingStateStore(userDefaults: userDefaults)

        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }
}
