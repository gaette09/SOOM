import XCTest
@testable import SOOM

@MainActor
final class RootAuthBootstrapTests: XCTestCase {
    func testBootstrapRunsInitializeOnce() async {
        var initializeCount = 0
        let bootstrap = RootAuthBootstrap {
            initializeCount += 1
        }

        await bootstrap.bootstrap()
        await bootstrap.bootstrap()

        XCTAssertEqual(initializeCount, 1)
        XCTAssertEqual(bootstrap.state, .completed)
    }

    func testDuplicateBootstrapCallsShareActiveTask() async {
        var initializeCount = 0
        let bootstrap = RootAuthBootstrap {
            initializeCount += 1
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        async let first: Void = bootstrap.bootstrap()
        async let second: Void = bootstrap.bootstrap()
        _ = await (first, second)

        XCTAssertEqual(initializeCount, 1)
        XCTAssertEqual(bootstrap.state, .completed)
    }

    func testBootstrapPromotesRemoteSessionThroughAuthViewModelWithoutMutatingLocalStore() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let remoteUser = AppUser(
            id: UUID(uuidString: "12121212-1212-1212-1212-121212121212")!,
            displayName: "remote",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeBootstrapRemoteSessionLoader(session: .signedIn(user: remoteUser))
        )
        let bootstrap = RootAuthBootstrap(authViewModel: viewModel)

        await bootstrap.bootstrap()

        XCTAssertEqual(viewModel.session.sessionState, .signedIn)
        XCTAssertEqual(viewModel.session.currentUser?.authProvider, .supabase)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(store.loadSession().isLocalOnly)
    }

    func testBootstrapKeepsLocalFallbackWhenRemoteIsMissing() async {
        let store = makeStore()
        let localSession = store.continueAsLocalUser(displayName: "Local User")
        let viewModel = AuthViewModel(
            repository: LocalAuthRepository(store: store),
            remoteSessionLoader: FakeBootstrapRemoteSessionLoader(session: nil)
        )
        let bootstrap = RootAuthBootstrap(authViewModel: viewModel)

        await bootstrap.bootstrap()

        XCTAssertEqual(viewModel.session.currentUser?.id, localSession.currentUser?.id)
        XCTAssertTrue(viewModel.session.isLocalOnly)
        XCTAssertEqual(store.loadSession().currentUser?.id, localSession.currentUser?.id)
    }

    func testBootstrapDoesNotUseRecoveryCalculator() async {
        var initialized = false
        let bootstrap = RootAuthBootstrap {
            initialized = true
        }

        await bootstrap.bootstrap()

        XCTAssertTrue(initialized)
    }

    private func makeStore() -> AuthSessionStore {
        let suiteName = "RootAuthBootstrapTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AuthSessionStore(userDefaults: defaults, now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }
}

private struct FakeBootstrapRemoteSessionLoader: RemoteAuthSessionLoading {
    let session: AuthSession?

    func loadRemoteSession() async -> AuthSession? {
        session
    }
}
