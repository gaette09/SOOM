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

    func testTimeoutUnblocksAllWaitersWithoutOpeningAccountOrRepeatingInitialization() async {
        let pending = PendingBootstrapOperation()
        let bootstrap = RootAuthBootstrap(timeoutNanoseconds: 20_000_000) { await pending.run() }
        async let first: Void = bootstrap.bootstrap()
        async let second: Void = bootstrap.bootstrap()
        _ = await (first, second)
        XCTAssertEqual(bootstrap.state, .timedOut)
        XCTAssertEqual(pending.calls, 1)
        await bootstrap.bootstrap()
        XCTAssertEqual(bootstrap.state, .timedOut)
        await bootstrap.retry()
        XCTAssertEqual(bootstrap.state, .timedOut)
        XCTAssertEqual(pending.calls, 1)
        pending.release()
        await Task.yield()
    }

    func testLateCompletionNeedsExplicitRetryAndDoesNotRepeatInitialization() async {
        let pending = PendingBootstrapOperation()
        let bootstrap = RootAuthBootstrap(timeoutNanoseconds: 20_000_000) { await pending.run() }
        await bootstrap.bootstrap()
        XCTAssertEqual(bootstrap.state, .timedOut)
        pending.release()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(bootstrap.state, .timedOut)
        await bootstrap.retry()
        XCTAssertEqual(bootstrap.state, .completed)
        XCTAssertEqual(pending.calls, 1)
    }

    func testCancelledCallerStillReachesBoundedFailureAndNeverOpensAccount() async {
        let pending = PendingBootstrapOperation()
        let bootstrap = RootAuthBootstrap(timeoutNanoseconds: 20_000_000) { await pending.run() }
        let caller = Task { await bootstrap.bootstrap() }
        await Task.yield()
        caller.cancel()
        await caller.value
        XCTAssertEqual(bootstrap.state, .timedOut)
        pending.release()
        await Task.yield()
    }

    func testSuccessfulInitializationCancelsDeadline() async {
        let bootstrap = RootAuthBootstrap(timeoutNanoseconds: 20_000_000) {}
        await bootstrap.bootstrap()
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(bootstrap.state, .completed)
    }

    func testPendingProfileDoesNotBlockIdentityOrMutateLocalAccount() async {
        let store = makeStore()
        let local = store.continueAsLocalUser(displayName: "Local")
        let loader = PendingStartupProfileLoader()
        let model = AuthViewModel(repository: LocalAuthRepository(store: store), remoteSessionLoader: loader)
        let bootstrap = RootAuthBootstrap(authViewModel: model)
        await bootstrap.bootstrap()
        await loader.waitForProfileRead()
        XCTAssertEqual(bootstrap.state, .completed)
        XCTAssertEqual(model.session.currentUser?.id, loader.user.id)
        XCTAssertEqual(model.session.currentUser?.displayName, "Cached")
        XCTAssertEqual(store.loadSession().currentUser?.id, local.currentUser?.id)
        var enriched = loader.user
        enriched.displayName = "Fresh"
        loader.release(.signedIn(user: enriched))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.session.currentUser?.displayName, "Fresh")
        XCTAssertEqual(store.loadSession().currentUser?.id, local.currentUser?.id)
    }

    func testLateProfileCannotOverwriteNewAccount() async {
        let loader = PendingStartupProfileLoader()
        let model = AuthViewModel(repository: LocalAuthRepository(store: makeStore()), remoteSessionLoader: loader)
        await model.initializeSession()
        await loader.waitForProfileRead()
        let other = AppUser(id: UUID(), displayName: "Other", email: nil, authProvider: .supabase, createdAt: Date())
        model.applyRemoteSession(.signedIn(user: other))
        loader.release(.signedIn(user: loader.user))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.session.currentUser?.id, other.id)
        XCTAssertEqual(model.session.currentUser?.displayName, "Other")
    }

    func testLateProfileFromPriorVisitCannotOverwriteSameAccountAfterSwitchBack() async {
        let loader = PendingStartupProfileLoader()
        let model = AuthViewModel(repository: LocalAuthRepository(store: makeStore()), remoteSessionLoader: loader)
        await model.initializeSession()
        await loader.waitForProfileRead()
        let other = AppUser(id: UUID(), displayName: "Other", email: nil, authProvider: .supabase, createdAt: Date())
        model.applyRemoteSession(.signedIn(user: other))
        var current = loader.user
        current.displayName = "Current visit"
        model.applyRemoteSession(.signedIn(user: current))
        loader.release(.signedIn(user: loader.user))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.session.currentUser?.id, current.id)
        XCTAssertEqual(model.session.currentUser?.displayName, "Current visit")
    }

    func testProfileReturningDifferentOwnerIsDiscarded() async {
        let loader = PendingStartupProfileLoader()
        let model = AuthViewModel(repository: LocalAuthRepository(store: makeStore()), remoteSessionLoader: loader)
        await model.initializeSession()
        await loader.waitForProfileRead()
        let other = AppUser(id: UUID(), displayName: "Other", email: nil, authProvider: .supabase, createdAt: Date())
        loader.release(.signedIn(user: other))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.session.currentUser?.id, loader.user.id)
        XCTAssertEqual(model.session.currentUser?.displayName, "Cached")
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

@MainActor
private final class PendingBootstrapOperation {
    private var continuation: CheckedContinuation<Void, Never>?
    var calls = 0
    func run() async {
        calls += 1
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class PendingStartupProfileLoader: RemoteAuthStartupSessionLoading {
    let user = AppUser(id: UUID(), displayName: "Cached", email: nil, authProvider: .supabase, createdAt: Date())
    private var profileContinuation: CheckedContinuation<AuthSession?, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    func loadStartupSession() async -> AuthSession? { .signedIn(user: user) }
    func loadRemoteSession() async -> AuthSession? {
        await withCheckedContinuation {
            profileContinuation = $0
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }
    func waitForProfileRead() async {
        if profileContinuation != nil { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }
    func release(_ session: AuthSession?) {
        profileContinuation?.resume(returning: session)
        profileContinuation = nil
    }
}
