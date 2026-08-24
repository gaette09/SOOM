import XCTest
@testable import SOOM

final class SignOutDeviceTokenCleanupTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var store: DeviceTokenStore!

    override func setUp() {
        super.setUp()
        let suiteName = "SignOutDeviceTokenCleanupTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        store = DeviceTokenStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults = nil
        store = nil
        super.tearDown()
    }

    /// The load-bearing case: sign-out is a pre-existing flow this batch
    /// must not regress. A broken token delete (network error, RLS edge
    /// case) must never strand the user signed in.
    func testSignOutProceedsWhenTokenDeleteFails() async throws {
        let registrar = MockDeviceTokenRegistrar()
        registrar.deleteError = NSError(domain: "test", code: 1)
        store.cache(tokenHex: "abc123")
        let cleanup = SignOutDeviceTokenCleanup(registrar: registrar, store: store)
        var remoteSignOutCalled = false

        let result = try await cleanup.wrapping {
            remoteSignOutCalled = true
            return .signedOut
        }()

        XCTAssertTrue(remoteSignOutCalled)
        XCTAssertEqual(result, .signedOut)
        XCTAssertEqual(registrar.deleteCalls, ["abc123"])
    }

    func testSignOutDeletesCachedTokenBeforeSigningOut() async throws {
        let registrar = MockDeviceTokenRegistrar()
        store.cache(tokenHex: "abc123")
        let cleanup = SignOutDeviceTokenCleanup(registrar: registrar, store: store)

        _ = try await cleanup.wrapping { .signedOut }()

        XCTAssertEqual(registrar.deleteCalls, ["abc123"])
    }

    func testSignOutSkipsDeleteWhenNoCachedToken() async throws {
        let registrar = MockDeviceTokenRegistrar()
        let cleanup = SignOutDeviceTokenCleanup(registrar: registrar, store: store)

        _ = try await cleanup.wrapping { .signedOut }()

        XCTAssertTrue(registrar.deleteCalls.isEmpty)
    }

    func testSignOutPropagatesRemoteSignOutFailure() async {
        let registrar = MockDeviceTokenRegistrar()
        let cleanup = SignOutDeviceTokenCleanup(registrar: registrar, store: store)

        do {
            _ = try await cleanup.wrapping { throw NSError(domain: "test", code: 2) }()
            XCTFail("expected the remote sign-out error to propagate")
        } catch {
            // expected
        }
    }
}
