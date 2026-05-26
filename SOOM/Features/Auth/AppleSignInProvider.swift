import Foundation

final class AppleSignInProvider {
    private let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    func prepareRequest(nonce: String? = nil) -> AppleSignInRequest {
        AppleSignInRequest(
            requestedScopes: [.fullName, .email],
            requiresNonce: true,
            nonce: nonce,
            redirectStrategy: .supabaseOAuthFuture,
            createdAt: now()
        )
    }

    func handleCredential(_ credential: AppleSignInCredential) async throws -> AuthSession {
        guard credential.isReadyForFutureSupabaseExchange else {
            throw AuthError.futureRemoteAuthNotConfigured
        }

        throw AuthError.futureRemoteAuthNotConfigured
    }
}
