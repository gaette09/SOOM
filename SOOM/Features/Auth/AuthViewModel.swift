import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var session: AuthSession
    @Published var displayNameText: String
    @Published private(set) var errorMessage: String?

    private let repository: any AuthRepository
    private let remoteSessionLoader: (any RemoteAuthSessionLoading)?

    init(
        repository: any AuthRepository = LocalAuthRepository(),
        remoteSessionLoader: (any RemoteAuthSessionLoading)? = nil
    ) {
        let loadedSession = repository.loadSession()
        self.repository = repository
        self.remoteSessionLoader = remoteSessionLoader
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

    func checkRemoteSession() async {
        guard let remoteSessionLoader,
              let remoteSession = await remoteSessionLoader.loadRemoteSession(),
              remoteSession.isSignedIn
        else {
            return
        }

        session = remoteSession
        displayNameText = remoteSession.currentUser?.displayName ?? displayNameText
        errorMessage = nil
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
