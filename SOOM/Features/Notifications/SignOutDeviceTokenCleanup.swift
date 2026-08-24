import Foundation

/// Wraps a remote sign-out handler to best-effort delete this device's
/// token first. Sign-out is a pre-existing, load-bearing flow — a failed
/// token delete (network error, RLS edge case) must never block it, so
/// failures are swallowed with `try?` and sign-out always proceeds.
struct SignOutDeviceTokenCleanup {
    private let registrar: any DeviceTokenRegistering
    private let store: DeviceTokenStore

    init(registrar: any DeviceTokenRegistering, store: DeviceTokenStore) {
        self.registrar = registrar
        self.store = store
    }

    func wrapping(_ remoteSignOut: @escaping () async throws -> AuthSession) -> () async throws -> AuthSession {
        {
            if let tokenHex = store.cachedTokenHex {
                try? await registrar.deleteToken(tokenHex: tokenHex)
            }
            return try await remoteSignOut()
        }
    }
}
