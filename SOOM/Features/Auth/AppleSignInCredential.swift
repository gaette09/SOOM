import Foundation

struct AppleSignInCredential: Equatable {
    let userIdentifier: String
    let identityToken: String?
    let authorizationCode: String?
    let email: String?
    let fullName: String?
    let nonce: String?
    let createdAt: Date

    init(
        userIdentifier: String,
        identityToken: String? = nil,
        authorizationCode: String? = nil,
        email: String? = nil,
        fullName: String? = nil,
        nonce: String? = nil,
        createdAt: Date = Date()
    ) {
        self.userIdentifier = userIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.identityToken = Self.normalized(identityToken)
        self.authorizationCode = Self.normalized(authorizationCode)
        self.email = Self.normalized(email)?.lowercased()
        self.fullName = Self.normalized(fullName)
        self.nonce = Self.normalized(nonce)
        self.createdAt = createdAt
    }

    var hasIdentityToken: Bool {
        identityToken != nil
    }

    var hasAuthorizationCode: Bool {
        authorizationCode != nil
    }

    var hasNonce: Bool {
        nonce != nil
    }

    var isReadyForSupabaseExchange: Bool {
        !userIdentifier.isEmpty && hasIdentityToken && hasNonce
    }

    var isReadyForFutureSupabaseExchange: Bool {
        !userIdentifier.isEmpty && hasIdentityToken && hasAuthorizationCode && hasNonce
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
