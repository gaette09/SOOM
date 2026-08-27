import Foundation

enum AuthRuntimeEnvironment: String, CaseIterable, Identifiable {
    case local
    case development
    case production

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local:
            return "Local"
        case .development:
            return "Development"
        case .production:
            return "Production"
        }
    }
}

struct AuthEnvironment: Equatable {
    var environment: AuthRuntimeEnvironment
    var supabaseURL: URL?
    var supabaseAnonKey: String?
    var redirectScheme: String?

    var isSupabaseConfigured: Bool {
        Self.hasValidHost(supabaseURL) && Self.isConcreteValue(supabaseAnonKey)
    }

    var isRedirectConfigured: Bool {
        Self.isConcreteValue(redirectScheme)
    }

    static let local = AuthEnvironment(environment: .local)

    init(
        environment: AuthRuntimeEnvironment = .local,
        supabaseURL: URL? = nil,
        supabaseAnonKey: String? = nil,
        redirectScheme: String? = nil
    ) {
        self.environment = environment
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = Self.normalizedOptional(supabaseAnonKey)
        self.redirectScheme = Self.normalizedOptional(redirectScheme)
    }

    static func isConcreteValue(_ value: String?) -> Bool {
        normalizedOptional(value) != nil
    }

    /// `URL(string:)` happily parses a hostless string like `"https:"` —
    /// the exact shape xcconfig produces when it treats an un-escaped
    /// `//` as a comment start and truncates the value (see
    /// SOOM_LOCAL_SECRETS_SETUP.md). `SupabaseClient(supabaseURL:...)`
    /// fatal-errors on that instead of throwing, so this must be caught
    /// here, before a URL like that is ever treated as "configured".
    static func hasValidHost(_ url: URL?) -> Bool {
        url?.host?.isEmpty == false
    }

    static func normalizedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        let lowercased = trimmed.lowercased()
        if trimmed.hasPrefix("$(") && trimmed.hasSuffix(")") { return nil }
        if lowercased.contains("placeholder") { return nil }
        if lowercased.contains("replace_me") { return nil }
        if lowercased.contains("your_") { return nil }
        if lowercased == "soom_supabase_url" { return nil }
        if lowercased == "soom_supabase_anon_key" { return nil }
        if lowercased == "soom_auth_redirect_scheme" { return nil }
        return trimmed
    }
}
