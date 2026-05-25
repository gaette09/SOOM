import Foundation

final class SupabaseAuthProvider {
    private let clientProvider: SupabaseClientProvider
    private let sessionProbe: SupabaseAuthSessionProbe

    init(configuration: SupabaseAuthConfiguration = .empty) {
        let clientProvider = SupabaseClientProvider(configuration: configuration)
        self.clientProvider = clientProvider
        self.sessionProbe = SupabaseAuthSessionProbe(clientProvider: clientProvider)
    }

    init(clientProvider: SupabaseClientProvider) {
        self.clientProvider = clientProvider
        self.sessionProbe = SupabaseAuthSessionProbe(clientProvider: clientProvider)
    }

    init(clientProvider: SupabaseClientProvider, sessionProbe: SupabaseAuthSessionProbe) {
        self.clientProvider = clientProvider
        self.sessionProbe = sessionProbe
    }

    var clientState: SupabaseClientProvider.ClientState {
        clientProvider.state
    }

    func checkSessionStatus() async -> SupabaseAuthSessionSnapshot {
        await sessionProbe.checkSessionStatus()
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
