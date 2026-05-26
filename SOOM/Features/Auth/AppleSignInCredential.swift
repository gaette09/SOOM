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
        self.identityToken = identityToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.authorizationCode = authorizationCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.email = email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.fullName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.nonce = nonce?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.createdAt = createdAt
    }

    var hasIdentityToken: Bool { identityToken != nil }
    var hasAuthorizationCode: Bool { authorizationCode != nil }
    var isReadyForFutureSupabaseExchange: Bool {
        !userIdentifier.isEmpty && hasIdentityToken && hasAuthorizationCode
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
