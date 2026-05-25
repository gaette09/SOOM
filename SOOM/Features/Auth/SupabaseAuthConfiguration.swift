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
}
