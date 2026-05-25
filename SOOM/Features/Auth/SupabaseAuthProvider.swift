import Foundation
import Supabase

protocol SupabaseEmailMagicLinkRequesting {
    func requestMagicLink(_ request: EmailAuthRequest) async throws
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

final class SupabaseAuthProvider {
    private let clientProvider: SupabaseClientProvider
    private let sessionProbe: SupabaseAuthSessionProbe
    private let emailRequester: (any SupabaseEmailMagicLinkRequesting)?
    private let now: () -> Date

    init(configuration: SupabaseAuthConfiguration = .empty, now: @escaping () -> Date = { Date() }) {
        let clientProvider = SupabaseClientProvider(configuration: configuration)
        self.clientProvider = clientProvider
        self.sessionProbe = SupabaseAuthSessionProbe(clientProvider: clientProvider)
        self.emailRequester = clientProvider.makeClient().map(SupabaseClientEmailMagicLinkRequester.init(client:))
        self.now = now
    }

    init(clientProvider: SupabaseClientProvider, now: @escaping () -> Date = { Date() }) {
        self.clientProvider = clientProvider
        self.sessionProbe = SupabaseAuthSessionProbe(clientProvider: clientProvider)
        self.emailRequester = clientProvider.makeClient().map(SupabaseClientEmailMagicLinkRequester.init(client:))
        self.now = now
    }

    init(
        clientProvider: SupabaseClientProvider,
        sessionProbe: SupabaseAuthSessionProbe,
        emailRequester: (any SupabaseEmailMagicLinkRequesting)? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.clientProvider = clientProvider
        self.sessionProbe = sessionProbe
        self.emailRequester = emailRequester
        self.now = now
    }

    var clientState: SupabaseClientProvider.ClientState {
        clientProvider.state
    }

    func checkSessionStatus() async -> SupabaseAuthSessionSnapshot {
        await sessionProbe.checkSessionStatus()
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
