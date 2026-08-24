import XCTest
@testable import SOOM

final class DeviceTokenStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var store: DeviceTokenStore!

    override func setUp() {
        super.setUp()
        let suiteName = "DeviceTokenStoreTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        store = DeviceTokenStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults = nil
        store = nil
        super.tearDown()
    }

    func testCachedTokenHexStartsNil() {
        XCTAssertNil(store.cachedTokenHex)
    }

    func testCacheTokenHexPersists() {
        store.cache(tokenHex: "abc123")

        XCTAssertEqual(store.cachedTokenHex, "abc123")
    }

    func testCacheTokenHexSurvivesReconstructionWithSameUserDefaults() {
        store.cache(tokenHex: "abc123")
        let reloaded = DeviceTokenStore(userDefaults: userDefaults)

        XCTAssertEqual(reloaded.cachedTokenHex, "abc123")
    }
}
