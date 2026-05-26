import Foundation

enum AuthCallbackResult: Equatable {
    case ignored
    case handled
    case failed(String)
    case sessionBridged(AuthSession)
}

protocol AuthCallbackSessionHandling {
    func handleAuthCallback(url: URL) async throws -> AuthSession?
}

struct AuthCallbackHandler {
    private let environment: AuthEnvironment
    private let sessionHandler: any AuthCallbackSessionHandling

    init(
        environment: AuthEnvironment = AuthEnvironmentLoader().load(),
        sessionHandler: any AuthCallbackSessionHandling
    ) {
        self.environment = environment
        self.sessionHandler = sessionHandler
    }

    func handle(url: URL) async -> AuthCallbackResult {
        let callbackURL = AuthCallbackURL(url: url, environment: environment)
        guard callbackURL.isAuthCallback else {
            return .ignored
        }

        do {
            guard let session = try await sessionHandler.handleAuthCallback(url: url) else {
                return .handled
            }

            return .sessionBridged(session)
        } catch {
            return .failed(userMessage(for: error))
        }
    }

    private func userMessage(for error: Error) -> String {
        if let authError = error as? AuthError {
            return authError.userMessage
        }

        return "계정 연결 callback을 확인하지 못했어요. 현재 기록은 로컬에 유지됩니다."
    }
}
