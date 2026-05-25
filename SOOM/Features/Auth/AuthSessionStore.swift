import Foundation

final class AuthSessionStore {
    static let shared = AuthSessionStore()

    private enum Key {
        static let user = UserScopedStorageKey.auth("currentUser").value
    }

    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let now: () -> Date

    init(
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        now: @escaping () -> Date = Date.init
    ) {
        self.userDefaults = userDefaults
        self.encoder = encoder
        self.decoder = decoder
        self.now = now
    }

    func loadSession() -> AuthSession {
        guard let data = userDefaults.data(forKey: Key.user) else {
            return .signedOut
        }

        do {
            let user = try decoder.decode(AppUser.self, from: data)
            if user.authProvider == .local {
                return .localOnly(user: user)
            }
            return AuthSession(currentUser: user, sessionState: .signedIn)
        } catch {
            return .error("저장된 사용자 정보를 불러오지 못했어요.")
        }
    }

    @discardableResult
    func continueAsLocalUser(displayName: String = "SOOM 사용자") -> AuthSession {
        let existing = loadSession().currentUser
        let user = existing ?? AppUser(
            displayName: displayName,
            handle: "@soom.local",
            authProvider: .local,
            createdAt: now()
        )
        saveUser(user)
        return .localOnly(user: user)
    }

    @discardableResult
    func updateDisplayName(_ displayName: String) -> AuthSession {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .error("표시 이름을 입력해주세요.", currentUser: loadSession().currentUser)
        }

        var user = loadSession().currentUser ?? AppUser(
            displayName: trimmed,
            handle: "@soom.local",
            authProvider: .local,
            createdAt: now()
        )
        user.displayName = trimmed
        saveUser(user)
        return user.authProvider == .local ? .localOnly(user: user) : AuthSession(currentUser: user, sessionState: .signedIn)
    }

    @discardableResult
    func signOut() -> AuthSession {
        userDefaults.removeObject(forKey: Key.user)
        return .signedOut
    }

    private func saveUser(_ user: AppUser) {
        guard let data = try? encoder.encode(user) else { return }
        userDefaults.set(data, forKey: Key.user)
    }
}
