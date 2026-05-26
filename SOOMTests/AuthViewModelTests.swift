import XCTest
@testable import SOOM

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
