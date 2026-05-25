import Foundation

struct SupabaseAuthSessionSnapshot: Equatable {
    enum Status: String, Equatable {
        case unconfigured
        case signedOut
        case signedIn
        case failed
    }

    let isConfigured: Bool
    let hasSession: Bool
    let userId: String?
    let email: String?
    let checkedAt: Date
    let status: Status
}
