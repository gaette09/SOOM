import Foundation

struct AuthEnvironmentLoader {
    private enum Key {
        static let environment = "SOOMAuthEnvironment"
        static let supabaseURL = "SOOMSupabaseURL"
        static let supabaseAnonKey = "SOOMSupabaseAnonKey"
        static let redirectScheme = "SOOMAuthRedirectScheme"

        static let legacySupabaseURL = "SOOM_SUPABASE_URL"
        static let legacySupabaseAnonKey = "SOOM_SUPABASE_ANON_KEY"
        static let legacyRedirectScheme = "SOOM_AUTH_REDIRECT_SCHEME"
    }

    private let infoDictionary: [String: Any]

    init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        self.infoDictionary = infoDictionary
    }

    func load() -> AuthEnvironment {
        AuthEnvironment(
            environment: runtimeEnvironment(),
            supabaseURL: supabaseURL(),
            supabaseAnonKey: stringValue(for: Key.supabaseAnonKey, fallback: Key.legacySupabaseAnonKey),
            redirectScheme: stringValue(for: Key.redirectScheme, fallback: Key.legacyRedirectScheme)
        )
    }

    private func runtimeEnvironment() -> AuthRuntimeEnvironment {
        guard let rawValue = AuthEnvironment.normalizedOptional(stringValue(for: Key.environment)) else {
            return .local
        }
        return AuthRuntimeEnvironment(rawValue: rawValue.lowercased()) ?? .local
    }

    private func supabaseURL() -> URL? {
        guard let rawURL = AuthEnvironment.normalizedOptional(stringValue(for: Key.supabaseURL, fallback: Key.legacySupabaseURL)) else {
            return nil
        }
        return URL(string: rawURL)
    }

    private func stringValue(for key: String, fallback: String? = nil) -> String? {
        if let value = infoDictionary[key] as? String { return value }
        if let fallback, let value = infoDictionary[fallback] as? String { return value }
        return nil
    }
}
