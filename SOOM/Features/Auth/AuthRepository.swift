import Foundation

protocol AuthRepository {
    func loadSession() -> AuthSession
    @discardableResult func continueAsLocalUser(displayName: String) -> AuthSession
    @discardableResult func signOut() -> AuthSession
    @discardableResult func updateDisplayName(_ displayName: String) -> AuthSession
    func signInWithApple() async throws -> AuthSession
    func signInWithGoogle() async throws -> AuthSession
    func signInWithSupabaseEmail(email: String) async throws -> AuthSession
    func requestEmailMagicLink(email: String, redirectTo: URL?) async throws -> EmailAuthRequestResult
}

extension AuthRepository {
    func signInWithApple() async throws -> AuthSession {
        throw AuthError.unsupportedProvider(.apple)
    }

    func signInWithGoogle() async throws -> AuthSession {
        throw AuthError.unsupportedProvider(.google)
    }

    func signInWithSupabaseEmail(email: String) async throws -> AuthSession {
        throw AuthError.futureRemoteAuthNotConfigured
    }

    func requestEmailMagicLink(email: String, redirectTo: URL? = nil) async throws -> EmailAuthRequestResult {
        throw AuthError.futureRemoteAuthNotConfigured
    }
}
