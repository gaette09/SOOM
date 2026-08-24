import Foundation

/// Caches the most recently received APNs device token locally, independent
/// of login state. A token can arrive before login is confirmed (or while
/// the user is a guest) — caching it here lets a later login pick it up
/// (see `DeviceTokenReceiptHandler.loginStateChanged`) and lets sign-out
/// find the value to delete server-side without re-deriving it.
final class DeviceTokenStore {
    static let shared = DeviceTokenStore()

    private enum Key {
        static let cachedTokenHex = "deviceToken.cachedHex"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var cachedTokenHex: String? {
        userDefaults.string(forKey: Key.cachedTokenHex)
    }

    func cache(tokenHex: String) {
        userDefaults.set(tokenHex, forKey: Key.cachedTokenHex)
    }
}
