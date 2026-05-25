import Foundation

final class AuthViewModel: ObservableObject {
    @Published private(set) var session: AuthSession
    @Published var displayNameText: String
    @Published private(set) var errorMessage: String?

    private let store: AuthSessionStore

    init(store: AuthSessionStore = .shared) {
        let loadedSession = store.loadSession()
        self.store = store
        self.session = loadedSession
        self.displayNameText = loadedSession.currentUser?.displayName ?? ""
        self.errorMessage = loadedSession.errorMessage
    }

    func load() {
        session = store.loadSession()
        displayNameText = session.currentUser?.displayName ?? ""
        errorMessage = session.errorMessage
    }

    func continueAsLocalUser() {
        session = store.continueAsLocalUser(displayName: displayNameText.isEmpty ? "SOOM 사용자" : displayNameText)
        displayNameText = session.currentUser?.displayName ?? ""
        errorMessage = nil
    }

    func updateDisplayName() {
        session = store.updateDisplayName(displayNameText)
        displayNameText = session.currentUser?.displayName ?? displayNameText
        errorMessage = session.errorMessage
    }

    func signOut() {
        session = store.signOut()
        displayNameText = ""
        errorMessage = nil
    }
}
