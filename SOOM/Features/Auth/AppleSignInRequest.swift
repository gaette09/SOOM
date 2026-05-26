import Foundation

enum AppleSignInScope: String, Codable, Equatable, CaseIterable {
    case fullName
    case email

    var title: String {
        switch self {
        case .fullName:
            return "이름"
        case .email:
            return "이메일"
        }
    }
}

enum AppleSignInRedirectStrategy: String, Codable, Equatable {
    case none
    case supabaseOAuthFuture
}

struct AppleSignInRequest: Equatable {
    let requestedScopes: [AppleSignInScope]
    let requiresNonce: Bool
    let nonce: String?
    let redirectStrategy: AppleSignInRedirectStrategy
    let createdAt: Date

    init(
        requestedScopes: [AppleSignInScope] = [.fullName, .email],
        requiresNonce: Bool = true,
        nonce: String? = nil,
        redirectStrategy: AppleSignInRedirectStrategy = .supabaseOAuthFuture,
        createdAt: Date = Date()
    ) {
        self.requestedScopes = requestedScopes
        self.requiresNonce = requiresNonce
        self.nonce = nonce?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.redirectStrategy = redirectStrategy
        self.createdAt = createdAt
    }

    var isNoncePrepared: Bool { !requiresNonce || nonce != nil }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
