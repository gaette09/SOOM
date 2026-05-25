import Foundation

final class SupabaseAuthProvider {
    private let clientProvider: SupabaseClientProvider

    init(configuration: SupabaseAuthConfiguration = .empty) {
        self.clientProvider = SupabaseClientProvider(configuration: configuration)
    }

    init(clientProvider: SupabaseClientProvider) {
        self.clientProvider = clientProvider
    }

    var clientState: SupabaseClientProvider.ClientState {
        clientProvider.state
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
