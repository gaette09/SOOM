import XCTest
@testable import SOOM

final class AuthSessionStoreTests: XCTestCase {
    func testLoadSessionStartsSignedOutWhenNoUserIsStored() {
        let store = makeStore()

        let session = store.loadSession()

        XCTAssertNil(session.currentUser)
        XCTAssertEqual(session.sessionState, .signedOut)
        XCTAssertFalse(session.isSignedIn)
    }

    func testContinueAsLocalUserCreatesAndPersistsLocalUser() {
        let store = makeStore()

        let created = store.continueAsLocalUser(displayName: "지완")
        let loaded = store.loadSession()

        XCTAssertEqual(created.currentUser?.displayName, "지완")
        XCTAssertEqual(loaded.currentUser, created.currentUser)
        XCTAssertTrue(loaded.isLocalOnly)
        XCTAssertFalse(loaded.isSignedIn)
    }

    func testUpdateDisplayNameUpdatesPersistedUser() {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "SOOM 사용자")

        let updated = store.updateDisplayName("새 이름")

        XCTAssertEqual(updated.currentUser?.displayName, "새 이름")
        XCTAssertEqual(store.loadSession().currentUser?.displayName, "새 이름")
    }

    func testInvalidDisplayNameKeepsCurrentUserAndReturnsError() {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "SOOM 사용자")

        let session = store.updateDisplayName("   ")

        XCTAssertEqual(session.sessionState, .error)
        XCTAssertNotNil(session.currentUser)
        XCTAssertEqual(store.loadSession().currentUser?.displayName, "SOOM 사용자")
    }

    func testSignOutClearsStoredLocalSession() {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "SOOM 사용자")

        let signedOut = store.signOut()

        XCTAssertEqual(signedOut.sessionState, .signedOut)
        XCTAssertNil(store.loadSession().currentUser)
    }

    func testFutureProviderEnumCasesExist() {
        XCTAssertTrue(AuthProvider.allCases.contains(.apple))
        XCTAssertTrue(AuthProvider.allCases.contains(.google))
        XCTAssertTrue(AuthProvider.allCases.contains(.supabase))
        XCTAssertTrue(AuthProvider.allCases.contains(.supabaseFuture))
    }

    func testUserScopedTrainingKeyCanIncludeFutureUserId() {
        let userId = UUID()
        let key = UserScopedStorageKey.training("maxHeartRate", userId: userId).value

        XCTAssertTrue(key.contains(userId.uuidString))
        XCTAssertTrue(key.contains("training.user"))
    }

    func testStoreDoesNotUseRecoveryCalculator() {
        let store = makeStore()
        let session = store.continueAsLocalUser(displayName: "SOOM 사용자")

        XCTAssertTrue(session.isLocalOnly)
    }

    private func makeStore() -> AuthSessionStore {
        let suiteName = "AuthSessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AuthSessionStore(userDefaults: defaults, now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }
}
