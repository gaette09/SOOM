import XCTest
@testable import SOOM

@MainActor
final class AuthViewModelTests: XCTestCase {
    func testLoadPublishesStoredLocalSession() {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "로컬 사용자")
        let viewModel = AuthViewModel(store: store)

        viewModel.load()

        XCTAssertEqual(viewModel.session.currentUser?.displayName, "로컬 사용자")
        XCTAssertTrue(viewModel.session.isLocalOnly)
    }

    func testRepositoryBasedInitLoadsStoredLocalSession() {
        let store = makeStore()
        let repository = LocalAuthRepository(store: store)
        _ = repository.continueAsLocalUser(displayName: "Repository User")

        let viewModel = AuthViewModel(repository: repository)

        XCTAssertEqual(viewModel.session.currentUser?.displayName, "Repository User")
        XCTAssertTrue(viewModel.session.isLocalOnly)
    }

    func testContinueAsLocalUserCreatesSession() {
        let viewModel = AuthViewModel(store: makeStore())
        viewModel.displayNameText = "지완"

        viewModel.continueAsLocalUser()

        XCTAssertEqual(viewModel.session.currentUser?.displayName, "지완")
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUpdateDisplayNamePublishesUpdatedUser() {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "이전 이름")
        let viewModel = AuthViewModel(store: store)
        viewModel.displayNameText = "새 이름"

        viewModel.updateDisplayName()

        XCTAssertEqual(viewModel.session.currentUser?.displayName, "새 이름")
        XCTAssertEqual(viewModel.displayNameText, "새 이름")
    }

    func testInvalidDisplayNamePublishesError() {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "SOOM 사용자")
        let viewModel = AuthViewModel(store: store)
        viewModel.displayNameText = "  "

        viewModel.updateDisplayName()

        XCTAssertEqual(viewModel.session.sessionState, .error)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testSignOutClearsSessionAndDisplayName() {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "SOOM 사용자")
        let viewModel = AuthViewModel(store: store)

        viewModel.signOut()

        XCTAssertEqual(viewModel.session.sessionState, .signedOut)
        XCTAssertTrue(viewModel.displayNameText.isEmpty)
    }


    func testCheckRemoteSessionPromotesSignedInRemoteSessionWithoutDeletingLocalStore() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRemoteSessionLoader(session: .signedIn(user: remoteUser))
        )

        await viewModel.checkRemoteSession()

        XCTAssertEqual(viewModel.session.sessionState, .signedIn)
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
        XCTAssertEqual(viewModel.session.currentUser?.email, "remote@example.com")
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testCheckRemoteSessionRunsOnMainActorAndPromotesRemoteSessionSafely() async {
        XCTAssertTrue(Thread.isMainThread)
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRemoteSessionLoader(session: .signedIn(user: remoteUser))
        )

        await viewModel.checkRemoteSession()

        XCTAssertTrue(Thread.isMainThread)
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
    }

    func testCheckRemoteSessionFailureKeepsLocalSession() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRemoteSessionLoader(session: nil)
        )

        await viewModel.checkRemoteSession()

        XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
    }


    func testInitializeSessionRestoresRemoteSessionWhenAvailableWithoutMutatingLocalStore() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRemoteSessionLoader(session: .signedIn(user: remoteUser))
        )

        await viewModel.initializeSession()

        XCTAssertEqual(viewModel.session.sessionState, .signedIn)
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
        XCTAssertEqual(viewModel.displayNameText, "remote")
        XCTAssertFalse(viewModel.isCheckingRemoteSession)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testInitializeSessionKeepsLocalWhenRemoteIsMissing() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRemoteSessionLoader(session: nil)
        )

        await viewModel.initializeSession()

        XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertFalse(viewModel.isCheckingRemoteSession)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
    }

    func testInitializeSessionWithLocalFirstPolicyDoesNotPromoteRemote() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeRemoteSessionLoader(session: .signedIn(user: remoteUser)),
            restorePolicy: .localFirst
        )

        await viewModel.initializeSession()

        XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertFalse(viewModel.isCheckingRemoteSession)
    }

    func testDuplicateInitializeSessionCallsShareActiveRestoreTask() async {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "10101010-1010-1010-1010-101010101010")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let loader = CountingRemoteSessionLoader(session: .signedIn(user: remoteUser))
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: loader
        )

        async let first: Void = viewModel.initializeSession()
        async let second: Void = viewModel.initializeSession()
        _ = await (first, second)

        XCTAssertEqual(loader.loadCount, 1)
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
        XCTAssertFalse(viewModel.isCheckingRemoteSession)
    }

    func testAppleSignInSuccessPromotesRemoteSessionWithoutDeletingLocalStore() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            displayName: "apple",
            email: "apple@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            appleSignInHandler: { credential in
                XCTAssertEqual(credential.identityToken, "token")
                return .signedIn(user: remoteUser)
            }
        )

        await viewModel.signInWithAppleCredential(
            AppleSignInCredential(
                userIdentifier: "apple-user",
                identityToken: "token",
                authorizationCode: "code",
                nonce: "raw-nonce"
            )
        )

        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
        XCTAssertEqual(viewModel.session.currentUser?.email, "apple@example.com")
        XCTAssertFalse(viewModel.isAppleSignInInProgress)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testAppleSignInFailureKeepsLocalSession() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            appleSignInHandler: { _ in throw AuthError.appleCredentialMissing }
        )

        await viewModel.signInWithAppleCredential(
            AppleSignInCredential(userIdentifier: "apple-user")
        )

        XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertEqual(viewModel.errorMessage, AuthError.appleCredentialMissing.userMessage)
        XCTAssertFalse(viewModel.isAppleSignInInProgress)
    }

    func testSessionBridgedCallbackResultAppliesSignedInSessionWithoutMutatingLocalStore() {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "12121212-1212-1212-1212-121212121212")!,
            displayName: "magic",
            email: "magic@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(repository: LocalAuthRepository(store: store))

        viewModel.handleAuthCallbackResult(.sessionBridged(.signedIn(user: remoteUser)))

        XCTAssertEqual(viewModel.session.sessionState, .signedIn)
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
        XCTAssertEqual(viewModel.session.currentUser?.email, "magic@example.com")
        XCTAssertEqual(viewModel.displayNameText, "magic")
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testIgnoredCallbackResultKeepsLocalSession() {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let viewModel = AuthViewModel(repository: LocalAuthRepository(store: store))

        viewModel.handleAuthCallbackResult(.ignored)

        XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
    }

    func testFailedCallbackResultKeepsLocalSessionAndPublishesSoftError() {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let viewModel = AuthViewModel(repository: LocalAuthRepository(store: store))

        viewModel.handleAuthCallbackResult(.failed("계정 연결 callback을 확인하지 못했어요."))

        XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertEqual(viewModel.errorMessage, "계정 연결 callback을 확인하지 못했어요.")
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
    }

    func testDisconnectRemoteAccountRestoresLocalFallbackWithoutDeletingStore() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "13131313-1313-1313-1313-131313131313")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        var signOutCallCount = 0
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSignOutHandler: {
                signOutCallCount += 1
                return .signedOut
            }
        )
        viewModel.applyRemoteSession(.signedIn(user: remoteUser))

        await viewModel.disconnectRemoteAccount()

        XCTAssertEqual(signOutCallCount, 1)
        XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertEqual(viewModel.displayNameText, "Local User")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testDisconnectRemoteAccountCreatesLocalFallbackWhenNoLocalUserExists() async {
        let store = makeStore()
        let remoteUser = AppUser(
            id: UUID(uuidString: "14141414-1414-1414-1414-141414141414")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSignOutHandler: { .signedOut }
        )
        viewModel.applyRemoteSession(.signedIn(user: remoteUser))

        await viewModel.disconnectRemoteAccount()

        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertEqual(viewModel.session.currentUser?.displayName, "SOOM 사용자")
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .local)
        XCTAssertEqual(store.loadSession().currentUser?.id, viewModel.session.currentUser?.id)
    }

    func testDisconnectRemoteAccountFailureKeepsRemoteSessionAndPublishesSoftError() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "15151515-1515-1515-1515-151515151515")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSignOutHandler: {
                throw AuthError.unknown("계정 연결 해제를 완료하지 못했어요.")
            }
        )
        viewModel.applyRemoteSession(.signedIn(user: remoteUser))

        await viewModel.disconnectRemoteAccount()

        XCTAssertEqual(viewModel.session.currentUser?.id, remoteUser.id)
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
        XCTAssertEqual(viewModel.errorMessage, "계정 연결 해제를 완료하지 못했어요.")
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testViewModelDoesNotUseRecoveryCalculator() {
        let viewModel = AuthViewModel(store: makeStore())
        viewModel.continueAsLocalUser()

        XCTAssertTrue(viewModel.session.isLocalOnly)
    }

    private func makeStore() -> AuthSessionStore {
        let suiteName = "AuthViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AuthSessionStore(userDefaults: defaults, now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }
}


private struct FakeRemoteSessionLoader: RemoteAuthSessionLoading {
    let session: AuthSession?

    func loadRemoteSession() async -> AuthSession? {
        session
    }
}

private final class CountingRemoteSessionLoader: RemoteAuthSessionLoading {
    private(set) var loadCount = 0
    let session: AuthSession?

    init(session: AuthSession?) {
        self.session = session
    }

    func loadRemoteSession() async -> AuthSession? {
        loadCount += 1
        try? await Task.sleep(nanoseconds: 10_000_000)
        return session
    }
}
