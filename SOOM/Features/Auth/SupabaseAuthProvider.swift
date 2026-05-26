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
            status: .signedIn
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
            status: .signedIn
        )
    }
}

final class SupabaseAuthProvider: RemoteAuthSessionLoading, AuthCallbackSessionHandling {
    private let clientProvider: SupabaseClientProvider
    private let sessionProbe: SupabaseAuthSessionProbe
    private let sessionBridge: AuthSessionBridge
    private let emailRequester: (any SupabaseEmailMagicLinkRequesting)?
    private let appleCredentialExchanger: (any SupabaseAppleCredentialExchanging)?
    private let callbackSessionLoader: (any SupabaseAuthCallbackSessionLoading)?
    private let appleSignInProvider: AppleSignInProvider
    private let now: () -> Date

    init(configuration: SupabaseAuthConfiguration = .empty, now: @escaping () -> Date = { Date() }) {
        let clientProvider = SupabaseClientProvider(configuration: configuration)
        let client = clientProvider.makeClient()
        self.clientProvider = clientProvider
        self.sessionProbe = SupabaseAuthSessionProbe(clientProvider: clientProvider)
        self.sessionBridge = AuthSessionBridge()
        self.emailRequester = client.map(SupabaseClientEmailMagicLinkRequester.init(client:))
        self.appleCredentialExchanger = client.map { SupabaseClientAppleCredentialExchanger(client: $0, now: now) }
        self.callbackSessionLoader = client.map { SupabaseClientAuthCallbackSessionLoader(client: $0, now: now) }
        self.appleSignInProvider = AppleSignInProvider(now: now)
        self.now = now
    }

    init(clientProvider: SupabaseClientProvider, now: @escaping () -> Date = { Date() }) {
        let client = clientProvider.makeClient()
        self.clientProvider = clientProvider
        self.sessionProbe = SupabaseAuthSessionProbe(clientProvider: clientProvider)
        self.sessionBridge = AuthSessionBridge()
        self.emailRequester = client.map(SupabaseClientEmailMagicLinkRequester.init(client:))
        self.appleCredentialExchanger = client.map { SupabaseClientAppleCredentialExchanger(client: $0, now: now) }
        self.callbackSessionLoader = client.map { SupabaseClientAuthCallbackSessionLoader(client: $0, now: now) }
        self.appleSignInProvider = AppleSignInProvider(now: now)
        self.now = now
    }

    init(
        clientProvider: SupabaseClientProvider,
        sessionProbe: SupabaseAuthSessionProbe,
        sessionBridge: AuthSessionBridge = AuthSessionBridge(),
        emailRequester: (any SupabaseEmailMagicLinkRequesting)? = nil,
        appleCredentialExchanger: (any SupabaseAppleCredentialExchanging)? = nil,
        callbackSessionLoader: (any SupabaseAuthCallbackSessionLoading)? = nil,
        appleSignInProvider: AppleSignInProvider = AppleSignInProvider(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.clientProvider = clientProvider
        self.sessionProbe = sessionProbe
        self.sessionBridge = sessionBridge
        self.emailRequester = emailRequester
        self.appleCredentialExchanger = appleCredentialExchanger
        self.callbackSessionLoader = callbackSessionLoader
        self.appleSignInProvider = appleSignInProvider
        self.now = now
    }

    var clientState: SupabaseClientProvider.ClientState {
        clientProvider.state
    }

    func checkSessionStatus() async -> SupabaseAuthSessionSnapshot {
        await sessionProbe.checkSessionStatus()
    }

    func loadRemoteSession() async -> AuthSession? {
        let snapshot = await checkSessionStatus()
        return sessionBridge.bridge(snapshot: snapshot)
    }

    func handleAuthCallback(url: URL) async throws -> AuthSession? {
        guard clientProvider.state == .ready, let callbackSessionLoader else {
            throw AuthError.futureRemoteAuthNotConfigured
        }

        let callbackSnapshot = try await callbackSessionLoader.loadSession(from: url)
        guard let session = sessionBridge.bridge(snapshot: callbackSnapshot) else {
            return await loadRemoteSession()
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

    func signOut() async throws -> AuthSession {
        guard clientProvider.state == .ready else {
            throw AuthError.futureRemoteAuthNotConfigured
        }
        throw AuthError.futureRemoteAuthNotConfigured
    }
}
