import Foundation

protocol RemoteAuthSessionLoading {
    func loadRemoteSession() async -> AuthSession?
}

struct AuthSessionBridge {
    private let mapper: SupabaseAppUserMapper

    init(mapper: SupabaseAppUserMapper = SupabaseAppUserMapper()) {
        self.mapper = mapper
    }

    func bridge(snapshot: SupabaseAuthSessionSnapshot, preserving localSession: AuthSession? = nil) -> AuthSession? {
        guard let user = mapper.map(snapshot: snapshot) else {
            return nil
        }

        return .signedIn(user: user)
    }
}
