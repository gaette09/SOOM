import Foundation

enum AuthSessionState: String, Codable, Equatable {
    case localOnly
    case signedOut
    case signedIn
    case loading
    case error
}

struct AuthSession: Codable, Equatable {
    var currentUser: AppUser?
    var sessionState: AuthSessionState
    var errorMessage: String?

    var isSignedIn: Bool {
        sessionState == .signedIn
    }

    var isLocalOnly: Bool {
        sessionState == .localOnly || currentUser?.authProvider == .local
    }

    static let signedOut = AuthSession(currentUser: nil, sessionState: .signedOut)
    static let loading = AuthSession(currentUser: nil, sessionState: .loading)

    static func localOnly(user: AppUser) -> AuthSession {
        AuthSession(currentUser: user, sessionState: .localOnly)
    }

    static func signedIn(user: AppUser) -> AuthSession {
        AuthSession(currentUser: user, sessionState: .signedIn)
    }

    static func error(_ message: String, currentUser: AppUser? = nil) -> AuthSession {
        AuthSession(currentUser: currentUser, sessionState: .error, errorMessage: message)
    }
}
