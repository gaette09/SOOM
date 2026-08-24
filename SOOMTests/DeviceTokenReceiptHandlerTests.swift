import XCTest
@testable import SOOM

final class DeviceTokenReceiptHandlerTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var store: DeviceTokenStore!

    override func setUp() {
        super.setUp()
        let suiteName = "DeviceTokenReceiptHandlerTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        store = DeviceTokenStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults = nil
        store = nil
        super.tearDown()
    }

    func testReceivedUpsertsWhenSignedInWithSupabase() {
        let registrar = MockDeviceTokenRegistrar()
        let handler = DeviceTokenReceiptHandler(store: store, registrar: registrar)
        let user = AppUser(displayName: "테스터", authProvider: .supabase)
        let didUpsert = expectation(description: "upsert called")
        registrar.onUpsert = { didUpsert.fulfill() }

        handler.received(tokenHex: "abc123", currentUser: user)

        wait(for: [didUpsert], timeout: 1)
        XCTAssertEqual(registrar.upsertCalls.first?.tokenHex, "abc123")
        XCTAssertEqual(registrar.upsertCalls.first?.userId, user.id)
    }

    func testReceivedCachesTokenEvenForGuest() {
        let registrar = MockDeviceTokenRegistrar()
        let handler = DeviceTokenReceiptHandler(store: store, registrar: registrar)

        handler.received(tokenHex: "abc123", currentUser: AppUser(displayName: "게스트", authProvider: .local))

        XCTAssertEqual(store.cachedTokenHex, "abc123")
        XCTAssertTrue(registrar.upsertCalls.isEmpty)
    }

    func testReceivedSkipsUpsertWhenNoCurrentUser() {
        let registrar = MockDeviceTokenRegistrar()
        let handler = DeviceTokenReceiptHandler(store: store, registrar: registrar)

        handler.received(tokenHex: "abc123", currentUser: nil)

        XCTAssertTrue(registrar.upsertCalls.isEmpty)
    }

    func testLoginStateChangedUpsertsCachedTokenAfterLoginConfirmed() {
        let registrar = MockDeviceTokenRegistrar()
        let handler = DeviceTokenReceiptHandler(store: store, registrar: registrar)
        handler.received(tokenHex: "abc123", currentUser: nil)
        let didUpsert = expectation(description: "upsert called")
        registrar.onUpsert = { didUpsert.fulfill() }

        handler.loginStateChanged(currentUser: AppUser(displayName: "테스터", authProvider: .supabase))

        wait(for: [didUpsert], timeout: 1)
        XCTAssertEqual(registrar.upsertCalls.first?.tokenHex, "abc123")
    }

    func testLoginStateChangedSkipsWhenNoCachedToken() {
        let registrar = MockDeviceTokenRegistrar()
        let handler = DeviceTokenReceiptHandler(store: store, registrar: registrar)

        handler.loginStateChanged(currentUser: AppUser(displayName: "테스터", authProvider: .supabase))

        XCTAssertTrue(registrar.upsertCalls.isEmpty)
    }
}
