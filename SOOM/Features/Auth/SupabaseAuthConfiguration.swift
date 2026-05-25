import Foundation

struct SupabaseAuthConfiguration: Equatable {
    var projectURL: URL?
    var anonKey: String?

    var isConfigured: Bool {
        guard projectURL != nil else { return false }
        guard let anonKey, !anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    static let empty = SupabaseAuthConfiguration()

    init(projectURL: URL? = nil, anonKey: String? = nil) {
        self.projectURL = projectURL
        self.anonKey = anonKey
    }

    static func from(environment: AuthEnvironment) -> SupabaseAuthConfiguration {
        guard environment.isSupabaseConfigured else { return .empty }
        return SupabaseAuthConfiguration(
            projectURL: environment.supabaseURL,
            anonKey: environment.supabaseAnonKey
        )
    }
}
