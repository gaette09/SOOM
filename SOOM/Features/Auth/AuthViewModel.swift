import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var session: AuthSession
    @Published var displayNameText: String
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAppleSignInInProgress: Bool

    private let repository: any AuthRepository
    private let remoteSessionLoader: (any RemoteAuthSessionLoading)?
    private let appleSignInHandler: ((AppleSignInCredential) async throws -> AuthSession)?

    init(
        repository: any AuthRepository = LocalAuthRepository(),
        remoteSessionLoader: (any RemoteAuthSessionLoading)? = nil,
        appleSignInHandler: ((AppleSignInCredential) async throws -> AuthSession)? = nil
    ) {
        let loadedSession = repository.loadSession()
        self.repository = repository
        self.remoteSessionLoader = remoteSessionLoader
        self.appleSignInHandler = appleSignInHandler
        self.session = loadedSession
        self.displayNameText = loadedSession.currentUser?.displayName ?? ""
        self.errorMessage = loadedSession.errorMessage
        self.isAppleSignInInProgress = false
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

    func signInWithAppleCredential(_ credential: AppleSignInCredential) async {
        guard let appleSignInHandler else {
            errorMessage = AuthError.futureRemoteAuthNotConfigured.userMessage
            return
        }

        isAppleSignInInProgress = true
        defer { isAppleSignInInProgress = false }

        do {
            let remoteSession = try await appleSignInHandler(credential)
            guard remoteSession.isSignedIn else {
                throw AuthError.sessionNotFound
            }

            session = remoteSession
            displayNameText = remoteSession.currentUser?.displayName ?? displayNameText
            errorMessage = nil
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func handleAppleSignInFailure(_ error: Error) {
        errorMessage = userMessage(for: error)
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

    private func userMessage(for error: Error) -> String {
        if let authError = error as? AuthError {
            return authError.userMessage
        }

        return "계정 연결 상태를 확인하지 못했어요. 현재 기록은 로컬에 유지됩니다."
    }
}
