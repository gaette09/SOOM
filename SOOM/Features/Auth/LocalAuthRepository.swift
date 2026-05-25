import Foundation

final class LocalAuthRepository: AuthRepository {
    private let store: AuthSessionStore

    init(store: AuthSessionStore = .shared) {
        self.store = store
    }

    func loadSession() -> AuthSession {
        store.loadSession()
    }

    @discardableResult
    func continueAsLocalUser(displayName: String) -> AuthSession {
        store.continueAsLocalUser(displayName: displayName)
    }

    @discardableResult
    func signOut() -> AuthSession {
        store.signOut()
    }

    @discardableResult
    func updateDisplayName(_ displayName: String) -> AuthSession {
        store.updateDisplayName(displayName)
    }
}
