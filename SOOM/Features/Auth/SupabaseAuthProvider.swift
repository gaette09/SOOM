import Foundation

final class SupabaseAuthProvider {
    private let configuration: SupabaseAuthConfiguration

    init(configuration: SupabaseAuthConfiguration = .empty) {
        self.configuration = configuration
    }

    func signInWithEmail(_ email: String) async throws -> AuthSession {
        guard configuration.isConfigured else {
            throw AuthError.futureRemoteAuthNotConfigured
        }
        throw AuthError.futureRemoteAuthNotConfigured
    }

    func signOut() async throws -> AuthSession {
        guard configuration.isConfigured else {
            throw AuthError.futureRemoteAuthNotConfigured
        }
        throw AuthError.futureRemoteAuthNotConfigured
    }
}
