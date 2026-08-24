import Foundation

/// Gates device_tokens upsert on real login (`AuthProvider.supabase`) — a
/// guest's `AppUser.id` is a locally-generated UUID with no matching
/// auth.users row, so device_tokens' foreign key would reject it anyway,
/// but this avoids the doomed network call entirely. See
/// `soom-guest-vs-login-policy` in ROADMAP.yaml: registering for
/// notifications is a login-gated interaction, not a read.
///
/// Two entry points exist because token receipt and login completion race
/// (RootAuthBootstrap resolves the session asynchronously and can finish
/// after the APNs callback fires): `received` handles the token-first
/// case, `loginStateChanged` handles the login-first case by picking up
/// whatever `DeviceTokenStore` already cached.
struct DeviceTokenReceiptHandler {
    private let store: DeviceTokenStore
    private let registrar: any DeviceTokenRegistering

    init(store: DeviceTokenStore, registrar: any DeviceTokenRegistering) {
        self.store = store
        self.registrar = registrar
    }

    func received(tokenHex: String, currentUser: AppUser?) {
        store.cache(tokenHex: tokenHex)
        upsertIfSignedIn(tokenHex: tokenHex, currentUser: currentUser)
    }

    func loginStateChanged(currentUser: AppUser?) {
        guard let tokenHex = store.cachedTokenHex else { return }
        upsertIfSignedIn(tokenHex: tokenHex, currentUser: currentUser)
    }

    private func upsertIfSignedIn(tokenHex: String, currentUser: AppUser?) {
        guard currentUser?.authProvider == .supabase, let userId = currentUser?.id else { return }
        Task { try? await registrar.upsert(tokenHex: tokenHex, userId: userId) }
    }
}
