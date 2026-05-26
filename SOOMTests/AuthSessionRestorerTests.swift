import XCTest
@testable import SOOM

final class AuthSessionRestorerTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testPreferRemotePromotesSignedInRemoteSessionWithoutMutatingLocalStore() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: fixedDate
        )
        let restorer = AuthSessionRestorer(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRestoreRemoteSessionLoader(session: .signedIn(user: remoteUser)),
            policy: .preferRemoteIfAvailable
        )

        let restored = await restorer.restore()

        XCTAssertEqual(restored.sessionState, .signedIn)
        XCTAssertEqual(restored.currentUser?.authProvider, .supabase)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testRemoteSignedOutKeepsLocalSession() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let restorer = AuthSessionRestorer(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRestoreRemoteSessionLoader(session: .signedOut),
            policy: .preferRemoteIfAvailable
        )

        let restored = await restorer.restore()

        XCTAssertEqual(restored.currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(restored.isLocalOnly)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
    }

    func testRemoteFailureKeepsLocalSession() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let restorer = AuthSessionRestorer(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRestoreRemoteSessionLoader(session: nil),
            policy: .preferRemoteIfAvailable
        )

        let restored = await restorer.restore()

        XCTAssertEqual(restored.currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(restored.isLocalOnly)
    }

    func testNoLocalAndNoRemoteUsesSignedOutFallback() async {
        let store = makeStore()
        let restorer = AuthSessionRestorer(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRestoreRemoteSessionLoader(session: nil),
            policy: .preferRemoteIfAvailable
        )

        let restored = await restorer.restore()

        XCTAssertEqual(restored.sessionState, .signedOut)
        XCTAssertNil(restored.currentUser)
    }

    func testLocalFirstPolicyDoesNotCallRemoteLoader() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteLoader = FakeRestoreRemoteSessionLoader(session: .signedOut)
        let restorer = AuthSessionRestorer(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: remoteLoader,
            policy: .localFirst
        )

        let restored = await restorer.restore()

        XCTAssertEqual(restored.currentUser?.id, localSession.currentUser?.id)
        XCTAssertEqual(remoteLoader.loadCount, 0)
    }

    func testRemoteOnlyFutureReturnsSignedOutWhenRemoteIsMissing() async {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "Local User")
        let restorer = AuthSessionRestorer(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRestoreRemoteSessionLoader(session: nil),
            policy: .remoteOnlyFuture
        )

        let restored = await restorer.restore()

        XCTAssertEqual(restored.sessionState, .signedOut)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testRestorerDoesNotUseRecoveryCalculator() async {
        let restorer = AuthSessionRestorer(
            repository: LocalAuthRepository(store: makeStore()),
            remoteSessionLoader: nil
        )

        let restored = await restorer.restore()

        XCTAssertEqual(restored.sessionState, .signedOut)
    }

    private func makeStore() -> AuthSessionStore {
        let suiteName = "AuthSessionRestorerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AuthSessionStore(userDefaults: defaults, now: { self.fixedDate })
    }
}

private final class FakeRestoreRemoteSessionLoader: RemoteAuthSessionLoading {
    private let session: AuthSession?
    private(set) var loadCount = 0

    init(session: AuthSession?) {
        self.session = session
    }

    func loadRemoteSession() async -> AuthSession? {
        loadCount += 1
        return session
    }
}
