import Foundation
import Supabase

protocol SupabaseEmailMagicLinkRequesting {
    func requestMagicLink(_ request: EmailAuthRequest) async throws
}

protocol SupabaseAppleCredentialExchanging {
    func signInWithApple(idToken: String, nonce: String?) async throws -> SupabaseAuthSessionSnapshot
}

protocol SupabaseAuthCallbackSessionLoading {
    func loadSession(from url: URL) async throws -> SupabaseAuthSessionSnapshot
}

protocol SupabaseRemoteSignOutRequesting {
    func signOut() async throws
}

protocol SupabaseAccountDeleting {
    func deleteAccount() async throws
}

struct SupabaseClientEmailMagicLinkRequester: SupabaseEmailMagicLinkRequesting {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func requestMagicLink(_ request: EmailAuthRequest) async throws {
        try request.validate()
        try await client.auth.signInWithOTP(
            email: request.normalizedEmail,
            redirectTo: request.redirectTo,
            shouldCreateUser: false
        )
    }
}

struct SupabaseClientAppleCredentialExchanger: SupabaseAppleCredentialExchanging {
    private let client: SupabaseClient
    private let now: () -> Date

    init(client: SupabaseClient, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    func signInWithApple(idToken: String, nonce: String?) async throws -> SupabaseAuthSessionSnapshot {
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )

        return SupabaseAuthSessionSnapshot(
            isConfigured: true,
            hasSession: true,
            userId: session.user.id.uuidString,
            email: session.user.email,
            checkedAt: now(),
            status: .signedIn,
            appleUserIdentifier: SupabaseAppleAccountMetadata(user: session.user).userIdentifier,
            linkedAuthProviders: SupabaseAppleAccountMetadata(user: session.user).providers
        )
    }
}

struct SupabaseClientAuthCallbackSessionLoader: SupabaseAuthCallbackSessionLoading {
    private let client: SupabaseClient
    private let now: () -> Date

    init(client: SupabaseClient, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    func loadSession(from url: URL) async throws -> SupabaseAuthSessionSnapshot {
        let session = try await client.auth.session(from: url)

        return SupabaseAuthSessionSnapshot(
            isConfigured: true,
            hasSession: true,
            userId: session.user.id.uuidString,
            email: session.user.email,
            checkedAt: now(),
            status: .signedIn,
            appleUserIdentifier: SupabaseAppleAccountMetadata(user: session.user).userIdentifier,
            linkedAuthProviders: SupabaseAppleAccountMetadata(user: session.user).providers
        )
    }
}

struct SupabaseClientRemoteSignOutRequester: SupabaseRemoteSignOutRequesting {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}

struct SupabaseClientLocalSignOutRequester: SupabaseRemoteSignOutRequesting {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func signOut() async throws {
        // The SDK removes its cached/Keychain session before attempting the
        // logout request, including when the account no longer exists.
        try await client.auth.signOut(scope: .local)
    }
}

struct SupabaseClientAccountDeleter: SupabaseAccountDeleting {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func deleteAccount() async throws {
        try await client.rpc("delete_own_account").execute()
    }
}

final class SupabaseAuthProvider: RemoteAuthStartupSessionLoading, AuthCallbackSessionHandling {
    private let sessionMutationGate = SupabaseSessionMutationGate()
    private let clientProvider: SupabaseClientProvider
    /// The single `SupabaseClient` every requester below and `sessionProbe`
    /// are built from. `SupabaseClientProvider.makeClient()` returns a new
    /// SDK client (and therefore a new, independent in-memory Auth session
    /// cache) on every call — Keychain storage is shared across instances
    /// but the in-memory `currentSession` is not. Building two clients here
    /// (one for signing in, another inside sessionProbe for checking
    /// session status) was the root cause of a real bug: login appeared to
    /// work, but session restore on next launch always saw an empty
    /// in-memory cache and fell back to a guest session. Exposed via
    /// `underlyingClient` so callers needing Supabase access outside this
    /// type (e.g. device token registration) reuse the same session state
    /// instead of creating yet another disconnected client.
    let underlyingClient: SupabaseClient?
    private let sessionProbe: SupabaseAuthSessionProbe
    private let sessionBridge: AuthSessionBridge
    private let emailRequester: (any SupabaseEmailMagicLinkRequesting)?
    private let appleCredentialExchanger: (any SupabaseAppleCredentialExchanging)?
    private let appleGrantRegistrar: (any AppleGrantRegistering)?
    private let callbackSessionLoader: (any SupabaseAuthCallbackSessionLoading)?
    private let remoteSignOutRequester: (any SupabaseRemoteSignOutRequesting)?
    private let profileUpdater: (any SupabaseProfileUpdating)?
    private let accountDeleter: (any SupabaseAccountDeleting)?
    private let accountDeletionSessionCleaner: (any SupabaseRemoteSignOutRequesting)?
    private let appleSignInProvider: AppleSignInProvider
    private let now: () -> Date

    init(configuration: SupabaseAuthConfiguration = .empty, now: @escaping () -> Date = { Date() }) {
        let clientProvider = SupabaseClientProvider(configuration: configuration)
        let client = clientProvider.makeClient()
        self.clientProvider = clientProvider
        self.underlyingClient = client
        self.sessionProbe = SupabaseAuthSessionProbe(
            isConfigured: clientProvider.state == .ready,
            reader: client.map(SupabaseClientSessionReader.init(client:))
        )
        self.sessionBridge = AuthSessionBridge()
        self.emailRequester = client.map(SupabaseClientEmailMagicLinkRequester.init(client:))
        self.appleCredentialExchanger = client.map { SupabaseClientAppleCredentialExchanger(client: $0, now: now) }
        self.appleGrantRegistrar = client.map(SupabaseAppleGrantRegistrar.init(client:))
        self.callbackSessionLoader = client.map { SupabaseClientAuthCallbackSessionLoader(client: $0, now: now) }
        self.remoteSignOutRequester = client.map(SupabaseClientRemoteSignOutRequester.init(client:))
        self.profileUpdater = client.map(SupabaseProfileStore.init(client:))
        self.accountDeleter = client.map(SupabaseClientAccountDeleter.init(client:))
        self.accountDeletionSessionCleaner = client.map(SupabaseClientLocalSignOutRequester.init(client:))
        self.appleSignInProvider = AppleSignInProvider(now: now)
        self.now = now
    }

    init(clientProvider: SupabaseClientProvider, now: @escaping () -> Date = { Date() }) {
        let client = clientProvider.makeClient()
        self.clientProvider = clientProvider
        self.underlyingClient = client
        self.sessionProbe = SupabaseAuthSessionProbe(
            isConfigured: clientProvider.state == .ready,
            reader: client.map(SupabaseClientSessionReader.init(client:))
        )
        self.sessionBridge = AuthSessionBridge()
        self.emailRequester = client.map(SupabaseClientEmailMagicLinkRequester.init(client:))
        self.appleCredentialExchanger = client.map { SupabaseClientAppleCredentialExchanger(client: $0, now: now) }
        self.appleGrantRegistrar = client.map(SupabaseAppleGrantRegistrar.init(client:))
        self.callbackSessionLoader = client.map { SupabaseClientAuthCallbackSessionLoader(client: $0, now: now) }
        self.remoteSignOutRequester = client.map(SupabaseClientRemoteSignOutRequester.init(client:))
        self.profileUpdater = client.map(SupabaseProfileStore.init(client:))
        self.accountDeleter = client.map(SupabaseClientAccountDeleter.init(client:))
        self.accountDeletionSessionCleaner = client.map(SupabaseClientLocalSignOutRequester.init(client:))
        self.appleSignInProvider = AppleSignInProvider(now: now)
        self.now = now
    }

    init(
        clientProvider: SupabaseClientProvider,
        sessionProbe: SupabaseAuthSessionProbe,
        sessionBridge: AuthSessionBridge = AuthSessionBridge(),
        emailRequester: (any SupabaseEmailMagicLinkRequesting)? = nil,
        appleCredentialExchanger: (any SupabaseAppleCredentialExchanging)? = nil,
        appleGrantRegistrar: (any AppleGrantRegistering)? = nil,
        callbackSessionLoader: (any SupabaseAuthCallbackSessionLoading)? = nil,
        remoteSignOutRequester: (any SupabaseRemoteSignOutRequesting)? = nil,
        accountDeleter: (any SupabaseAccountDeleting)? = nil,
        profileUpdater: (any SupabaseProfileUpdating)? = nil,
        accountDeletionSessionCleaner: (any SupabaseRemoteSignOutRequesting)? = nil,
        appleSignInProvider: AppleSignInProvider = AppleSignInProvider(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.clientProvider = clientProvider
        self.underlyingClient = nil
        self.sessionProbe = sessionProbe
        self.sessionBridge = sessionBridge
        self.emailRequester = emailRequester
        self.appleCredentialExchanger = appleCredentialExchanger
        self.appleGrantRegistrar = appleGrantRegistrar
        self.callbackSessionLoader = callbackSessionLoader
        self.remoteSignOutRequester = remoteSignOutRequester
        self.accountDeleter = accountDeleter
        self.profileUpdater = profileUpdater
        self.accountDeletionSessionCleaner = accountDeletionSessionCleaner
        self.appleSignInProvider = appleSignInProvider
        self.now = now
    }

    var clientState: SupabaseClientProvider.ClientState {
        clientProvider.state
    }

    func checkSessionStatus() async -> SupabaseAuthSessionSnapshot {
        await sessionProbe.checkSessionStatus()
    }

    func loadStartupSession() async -> AuthSession? {
        guard let client = underlyingClient else { return await loadRemoteSession() }
        let probe = SupabaseAuthSessionProbe(
            isConfigured: clientProvider.state == .ready,
            reader: SupabaseClientSessionReader(client: client, includesProfile: false)
        )
        return sessionBridge.bridge(snapshot: await probe.checkSessionStatus())
    }

    func loadRemoteSession() async -> AuthSession? {
        let snapshot = await checkSessionStatus()
        return sessionBridge.bridge(snapshot: snapshot)
    }

    func handleAuthCallback(url: URL) async throws -> AuthSession? {
        try sessionMutationGate.begin()
        defer { sessionMutationGate.end() }

        guard clientProvider.state == .ready, let callbackSessionLoader else {
            throw AuthError.futureRemoteAuthNotConfigured
        }

        let callbackSnapshot = try await callbackSessionLoader.loadSession(from: url)
        guard let session = sessionBridge.bridge(snapshot: callbackSnapshot) else {
            return await loadRemoteSession()
        }

        if underlyingClient != nil, let restored = await loadRemoteSession(), restored.currentUser?.id == session.currentUser?.id {
            return restored
        }
        return session
    }

    func prepareAppleSignInRequest(nonce: String? = nil) -> AppleSignInRequest {
        appleSignInProvider.prepareRequest(nonce: nonce)
    }

    func handleAppleSignInCredential(_ credential: AppleSignInCredential) async throws -> AuthSession {
        try await signInWithAppleCredential(credential)
    }

    func signInWithAppleCredential(_ credential: AppleSignInCredential) async throws -> AuthSession {
        try sessionMutationGate.begin()
        defer { sessionMutationGate.end() }

        let preparedCredential = try appleSignInProvider.handleCredential(credential)

        guard clientProvider.state == .ready, let appleCredentialExchanger else {
            throw AuthError.futureRemoteAuthNotConfigured
        }

        guard let idToken = preparedCredential.identityToken,
              let nonce = preparedCredential.nonce
        else {
            throw AuthError.appleCredentialMissing
        }

        let snapshot = try await appleCredentialExchanger.signInWithApple(
            idToken: idToken,
            nonce: nonce
        )

        guard let session = sessionBridge.bridge(snapshot: snapshot) else {
            throw AuthError.sessionNotFound
        }

        // Registration failure does not undo a successful Supabase login.
        // The one-use Apple code is never queued on disk; a new login retries it.
        if let owner = session.currentUser?.id, let appleGrantRegistrar {
            do {
                try await appleGrantRegistrar.register(credential: preparedCredential, expectedUserID: owner)
                await AppleGrantRegistrationState.shared.set(.registered, for: owner)
            } catch {
                await AppleGrantRegistrationState.shared.set(.needsRetry, for: owner)
            }
        }

        if underlyingClient != nil, let restored = await loadRemoteSession(), restored.currentUser?.id == session.currentUser?.id {
            return restored
        }
        return session
    }

    func requestMagicLink(email: String, redirectTo: URL? = nil) async throws -> EmailAuthRequestResult {
        let request = EmailAuthRequest(email: email, redirectTo: redirectTo)
        try request.validate()

        guard clientProvider.state == .ready, let emailRequester else {
            throw AuthError.futureRemoteAuthNotConfigured
        }

        try await emailRequester.requestMagicLink(request)
        return EmailAuthRequestResult(
            email: request.normalizedEmail,
            redirectTo: request.redirectTo,
            requestedAt: now()
        )
    }

    func signInWithEmail(_ email: String) async throws -> AuthSession {
        guard clientProvider.state == .ready else {
            throw AuthError.futureRemoteAuthNotConfigured
        }
        throw AuthError.futureRemoteAuthNotConfigured
    }

    func observeSessionTermination(onEnded: @escaping @MainActor (UUID) -> Void) async {
        guard let client = underlyingClient else { return }
        var previousUserID = client.auth.currentSession?.user.id
        for await (event, session) in client.auth.authStateChanges {
            if Task.isCancelled { return }
            if let session { previousUserID = session.user.id; continue }
            if event == .signedOut, let previousUserID, client.auth.currentSession == nil {
                await onEnded(previousUserID)
            }
        }
    }

    func updateDisplayName(expectedUserID: UUID, displayName: String) async throws -> String {
        try sessionMutationGate.begin()
        defer { sessionMutationGate.end() }
        guard let profileUpdater, clientProvider.state == .ready else {
            throw AuthError.futureRemoteAuthNotConfigured
        }
        let snapshot = await sessionProbe.checkSessionStatus()
        guard snapshot.userId.flatMap(UUID.init(uuidString:)) == expectedUserID else {
            throw AuthError.sessionNotFound
        }
        return try await profileUpdater.updateDisplayName(displayName, expectedUserID: expectedUserID)
    }

    func updateAvatar(expectedUserID: UUID, data: Data?) async throws -> String? {
        try sessionMutationGate.begin()
        defer { sessionMutationGate.end() }
        guard let client = underlyingClient, clientProvider.state == .ready else { throw ProfileAvatarError.unavailable }
        return try await SupabaseProfileStore(client: client).updateAvatar(data, expectedUserID: expectedUserID)
    }

    func signOut() async throws -> AuthSession {
        try sessionMutationGate.begin()
        defer { sessionMutationGate.end() }

        guard clientProvider.state == .ready, let remoteSignOutRequester else {
            throw AuthError.futureRemoteAuthNotConfigured
        }

        if FeedStaleSummaryCache.configuredMaximumAge != nil,
           let owner = underlyingClient?.auth.currentSession?.user.id {
            await MainActor.run { FeedStaleSummaryCache.shared.revokeAccountBoundary(viewerID: owner) }
        }
        do {
            try await remoteSignOutRequester.signOut()
        } catch {
            // Supabase removes its Keychain session before the logout HTTP call.
            // A post-removal offline error must not leave the UI signed in.
            guard await sessionProbe.checkSessionStatus().status == .signedOut else { throw error }
        }
        return .signedOut
    }

    /// Account verification, token cleanup, and SDK teardown share one mutation
    /// gate with callback/sign-in/deletion; no other login can replace this user.
    @discardableResult
    func endSessionAfterAppleCredentialRevocation(
        expectedUserID: UUID,
        beforeSignOut: () async -> Void = {}
    ) async -> Bool {
        do { try sessionMutationGate.begin() } catch { return false }
        defer { sessionMutationGate.end() }
        let snapshot = await sessionProbe.checkSessionStatus()
        guard snapshot.userId == expectedUserID.uuidString,
              let accountDeletionSessionCleaner else { return false }
        if FeedStaleSummaryCache.configuredMaximumAge != nil {
            await MainActor.run { FeedStaleSummaryCache.shared.revokeAccountBoundary(viewerID: expectedUserID) }
        }
        await beforeSignOut()
        // The live SDK removes its cached session before the network request.
        try? await accountDeletionSessionCleaner.signOut()
        return true
    }

    func deleteAccount() async throws {
        try await performAccountDeletion(expectedUserID: nil)
    }

    func deleteAccount(expectedUserID: UUID) async throws {
        try await performAccountDeletion(expectedUserID: expectedUserID)
    }

    private func performAccountDeletion(expectedUserID: UUID?) async throws {
        try sessionMutationGate.begin()
        defer { sessionMutationGate.end() }

        guard clientProvider.state == .ready, let accountDeleter else {
            throw AuthError.futureRemoteAuthNotConfigured
        }

        if let expectedUserID {
            let snapshot = await sessionProbe.checkSessionStatus()
            guard snapshot.status == .signedIn,
                  snapshot.userId.flatMap(UUID.init(uuidString:)) == expectedUserID else {
                throw AuthError.sessionNotFound
            }
            // The mutation gate prevents callback/sign-in from replacing the
            // token through the deletion await. Recheck the live cache after
            // the probe and immediately before invoking the deletion request.
            if let underlyingClient, underlyingClient.auth.currentSession?.user.id != expectedUserID {
                throw AuthError.sessionNotFound
            }
        }
        let deletingUserID = expectedUserID ?? underlyingClient?.auth.currentSession?.user.id
        if FeedStaleSummaryCache.configuredMaximumAge != nil, let deletingUserID {
            await MainActor.run { FeedStaleSummaryCache.shared.revokeAccountBoundary(viewerID: deletingUserID) }
        }
        try await accountDeleter.deleteAccount()
        if let deletingUserID { SupabaseProfileStore.clearCachedName(userID: deletingUserID) }
        // The account is already deleted. Clear the SDK session too so a
        // subsequent session check cannot restore the deleted identity.
        // A cleanup network error must not prevent local data erasure.
        try? await accountDeletionSessionCleaner?.signOut()
    }
}

/// Reject concurrent SDK mutations before either operation can install or clear
/// a session. The synchronous lock protects only the flag, never an await.
private final class SupabaseSessionMutationGate {
    private let lock = NSLock()
    private var isMutating = false

    func begin() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isMutating else { throw AuthError.sessionTransitionInProgress }
        isMutating = true
    }

    func end() {
        lock.lock()
        defer { lock.unlock() }
        isMutating = false
    }
}
