import Foundation

struct SupabaseAuthConfiguration: Equatable {
    var projectURL: URL?
    var anonKey: String?

    var isConfigured: Bool {
        projectURL != nil && AuthEnvironment.isConcreteValue(anonKey)
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
