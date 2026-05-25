import Foundation

struct EmailAuthRequest: Equatable {
    let email: String
    let redirectTo: URL?

    var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isValid: Bool {
        Self.isValidEmail(normalizedEmail)
    }

    init(email: String, redirectTo: URL? = nil) {
        self.email = email
        self.redirectTo = redirectTo
    }

    func validate() throws {
        guard isValid else { throw AuthError.invalidEmail }
    }

    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.contains("@"), trimmed.contains(".") else { return false }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        return parts[1].contains(".") && !trimmed.contains(" ")
    }

    static func redirectURL(from environment: AuthEnvironment) -> URL? {
        guard environment.isRedirectConfigured, let scheme = environment.redirectScheme else { return nil }
        return URL(string: "\(scheme)://auth/callback")
    }
}

struct EmailAuthRequestResult: Equatable {
    let email: String
    let redirectTo: URL?
    let requestedAt: Date
}
