import Foundation

final class AuthViewModel: ObservableObject {
    @Published private(set) var session: AuthSession
    @Published var displayNameText: String
    @Published private(set) var errorMessage: String?

    private let repository: any AuthRepository

    init(repository: any AuthRepository = LocalAuthRepository()) {
        let loadedSession = repository.loadSession()
        self.repository = repository
        self.session = loadedSession
        self.displayNameText = loadedSession.currentUser?.displayName ?? ""
        self.errorMessage = loadedSession.errorMessage
    }

    convenience init(store: AuthSessionStore) {
        self.init(repository: LocalAuthRepository(store: store))
    }

    func load() {
        session = repository.loadSession()
        displayNameText = session.currentUser?.displayName ?? ""
        errorMessage = session.errorMessage
    }

    func continueAsLocalUser() {
        session = repository.continueAsLocalUser(displayName: displayNameText.isEmpty ? "SOOM 사용자" : displayNameText)
        displayNameText = session.currentUser?.displayName ?? ""
        errorMessage = nil
    }

    func updateDisplayName() {
        session = repository.updateDisplayName(displayNameText)
        displayNameText = session.currentUser?.displayName ?? displayNameText
        errorMessage = session.errorMessage
    }

    func signOut() {
        session = repository.signOut()
        displayNameText = ""
        errorMessage = nil
    }
}
