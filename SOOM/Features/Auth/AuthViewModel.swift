import Foundation

/// Captured when the user opens deletion confirmation, including a session
/// revision so signing out and back into the same UUID requires new consent.
struct AccountDeletionTarget: Equatable {
    let userID: UUID?
    let provider: AuthProvider?
    fileprivate let sessionRevision: Int
    var remoteUserID: UUID? { provider == .supabase ? userID : nil }
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var session: AuthSession
    @Published var displayNameText: String
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAppleSignInInProgress: Bool
    @Published private(set) var isCheckingRemoteSession: Bool

    private let repository: any AuthRepository
    private let remoteSessionLoader: (any RemoteAuthSessionLoading)?
    private let sessionRestorer: AuthSessionRestorer
    private let appleSignInHandler: ((AppleSignInCredential) async throws -> AuthSession)?
    private let remoteDisplayNameHandler: ((UUID, String) async throws -> String)?
    private let remoteAvatarHandler: ((UUID, Data?) async throws -> String?)?
    @Published private(set) var isUpdatingDisplayName = false
    @Published private(set) var isUpdatingAvatar = false
    private let remoteSignOutHandler: (() async throws -> AuthSession)?
    private let remoteAccountDeleteHandler: (() async throws -> Void)?
    private let remoteAccountDeleteForUserHandler: ((UUID) async throws -> Void)?
    private var initializeSessionTask: Task<Void, Never>?
    private let appleCredentialStateReader: (String) async throws -> AppleCredentialState
    private let appleCredentialRevocationHandler: ((UUID) async -> Bool)?
    @Published private(set) var isAccountDeletionInProgress = false
    private var isDisconnectingRemoteAccount = false
    private var isHandlingAuthCallback = false

    var isRemoteSessionTransitionInProgress: Bool {
        isAppleSignInInProgress || isHandlingAppleCredentialRevocation
            || isAccountDeletionInProgress || isDisconnectingRemoteAccount || isHandlingAuthCallback || isUpdatingDisplayName || isUpdatingAvatar
    }

    private var sessionRevision = 0
    private var isHandlingAppleCredentialRevocation = false

    var accountDeletionTarget: AccountDeletionTarget {
        AccountDeletionTarget(userID: session.currentUser?.id,
            provider: session.currentUser?.authProvider, sessionRevision: sessionRevision)
    }

    var isCurrentAccountLinkedToApple: Bool {
        session.isSignedIn && session.currentUser?.isLinkedToApple == true
    }

    init(
        repository: any AuthRepository = LocalAuthRepository(),
        remoteSessionLoader: (any RemoteAuthSessionLoading)? = nil,
        restorePolicy: AuthSessionRestorePolicy = .preferRemoteIfAvailable,
        appleSignInHandler: ((AppleSignInCredential) async throws -> AuthSession)? = nil,
        remoteSignOutHandler: (() async throws -> AuthSession)? = nil,
        remoteDisplayNameHandler: ((UUID, String) async throws -> String)? = nil,
        remoteAvatarHandler: ((UUID, Data?) async throws -> String?)? = nil,
        remoteAccountDeleteHandler: (() async throws -> Void)? = nil,
        remoteAccountDeleteForUserHandler: ((UUID) async throws -> Void)? = nil,
        appleCredentialStateReader: @escaping (String) async throws -> AppleCredentialState = {
            try await AppleSignInProvider().credentialState(forUserID: $0)
        },
        appleCredentialRevocationHandler: ((UUID) async -> Bool)? = nil
    ) {
        let loadedSession = repository.loadSession()
        self.repository = repository
        self.remoteSessionLoader = remoteSessionLoader
        self.sessionRestorer = AuthSessionRestorer(
            repository: repository,
            remoteSessionLoader: remoteSessionLoader,
            policy: restorePolicy
        )
        self.appleSignInHandler = appleSignInHandler
        self.remoteSignOutHandler = remoteSignOutHandler
        self.remoteDisplayNameHandler = remoteDisplayNameHandler
        self.remoteAvatarHandler = remoteAvatarHandler
        self.remoteAccountDeleteHandler = remoteAccountDeleteHandler
        self.remoteAccountDeleteForUserHandler = remoteAccountDeleteForUserHandler
        self.appleCredentialStateReader = appleCredentialStateReader
        self.appleCredentialRevocationHandler = appleCredentialRevocationHandler
        self.session = loadedSession
        self.displayNameText = loadedSession.currentUser?.displayName ?? ""
        self.errorMessage = loadedSession.errorMessage
        self.isAppleSignInInProgress = false
        self.isCheckingRemoteSession = false
    }

    convenience init(store: AuthSessionStore) {
        self.init(repository: LocalAuthRepository(store: store))
    }

    func load() {
        guard !isRemoteSessionTransitionInProgress else { return }
        let loaded = repository.loadSession()
        if session.currentUser?.id != loaded.currentUser?.id { revokeFeedCacheBoundary(session.currentUser?.id) }
        sessionRevision += 1
        session = loaded
        displayNameText = session.currentUser?.displayName ?? ""
        errorMessage = session.errorMessage
    }

    func initializeSession() async {
        if let initializeSessionTask {
            await initializeSessionTask.value
            return
        }

        let task = Task { @MainActor in
            await self.performInitializeSession()
        }
        initializeSessionTask = task
        await task.value
        initializeSessionTask = nil
    }

    private func performInitializeSession() async {
        guard !isRemoteSessionTransitionInProgress else { return }
        let localSession = repository.loadSession()
        publish(session: localSession, preservingDisplayName: false)

        guard remoteSessionLoader != nil else {
            return
        }

        isCheckingRemoteSession = true
        defer { isCheckingRemoteSession = false }

        let revision = sessionRevision
        let restoredSession = await sessionRestorer.restore()
        guard sessionRevision == revision, !isRemoteSessionTransitionInProgress else { return }
        publish(session: restoredSession, preservingDisplayName: restoredSession.currentUser == nil)
        if remoteSessionLoader is any RemoteAuthStartupSessionLoading,
           let user = restoredSession.currentUser, user.authProvider == .supabase {
            let restoredRevision = sessionRevision
            Task { @MainActor [weak self] in
                await self?.refreshStartupProfile(userID: user.id, revision: restoredRevision)
            }
        }
    }

    private func refreshStartupProfile(userID: UUID, revision: Int) async {
        guard sessionRevision == revision, !isRemoteSessionTransitionInProgress,
              let refreshed = await remoteSessionLoader?.loadRemoteSession(),
              sessionRevision == revision, !isRemoteSessionTransitionInProgress,
              session.currentUser?.id == userID, refreshed.currentUser?.id == userID,
              refreshed.currentUser?.authProvider == .supabase, refreshed.isSignedIn else { return }
        publish(session: refreshed, preservingDisplayName: true)
    }

    func checkRemoteSession() async {
        let revision = sessionRevision
        guard !isRemoteSessionTransitionInProgress,
              let remoteSessionLoader,
              let remoteSession = await remoteSessionLoader.loadRemoteSession(),
              sessionRevision == revision,
              !isRemoteSessionTransitionInProgress,
              remoteSession.isSignedIn
        else {
            return
        }

        publish(session: remoteSession, preservingDisplayName: true)
    }

    func applyRemoteSession(_ remoteSession: AuthSession) {
        guard remoteSession.isSignedIn, !isHandlingAppleCredentialRevocation else {
            return
        }

        publish(session: remoteSession, preservingDisplayName: true)
    }

    /// Keeps local UI actions from diverging while the callback installs its SDK session.
    func handleAuthCallback(_ operation: () async -> AuthCallbackResult) async {
        guard !isRemoteSessionTransitionInProgress else { return }
        isHandlingAuthCallback = true
        defer { isHandlingAuthCallback = false }
        handleAuthCallbackResult(await operation())
    }

    func handleAuthCallbackResult(_ result: AuthCallbackResult) {
        switch result {
        case .sessionBridged(let remoteSession):
            applyRemoteSession(remoteSession)
        case .failed(let message):
            errorMessage = message
        case .ignored, .handled:
            break
        }
    }

    func signInWithAppleCredential(_ credential: AppleSignInCredential) async {
        guard !isRemoteSessionTransitionInProgress else { return }
        guard let appleSignInHandler else {
            errorMessage = AuthError.futureRemoteAuthNotConfigured.userMessage
            return
        }

        isAppleSignInInProgress = true
        defer { isAppleSignInInProgress = false }

        let revision = sessionRevision
        do {
            var remoteSession = try await appleSignInHandler(credential)
            guard sessionRevision == revision, !isHandlingAppleCredentialRevocation else { return }
            guard remoteSession.isSignedIn else {
                throw AuthError.sessionNotFound
            }

            if remoteSession.currentUser?.appleUserIdentifier == nil {
                remoteSession.currentUser?.appleUserIdentifier = credential.userIdentifier
            }
            publish(session: remoteSession, preservingDisplayName: true)
        } catch {
            guard sessionRevision == revision else { return }
            errorMessage = userMessage(for: error)
        }
    }

    /// Notification, launch, and foreground hooks call this without presenting sign-in UI.
    /// A stale response can never disconnect a replacement account/session.
    func refreshAppleCredentialState() async {
        guard !isRemoteSessionTransitionInProgress,
              isCurrentAccountLinkedToApple,
              let user = session.currentUser,
              let subject = user.appleUserIdentifier,
              !subject.isEmpty,
              let appleCredentialRevocationHandler
        else { return }
        let revision = sessionRevision
        let state: AppleCredentialState
        do {
            state = try await appleCredentialStateReader(subject)
        } catch {
            // Transient errors and ASAuthorizationError.accountNotFound are not revocation.
            return
        }
        guard sessionRevision == revision,
              !isRemoteSessionTransitionInProgress,
              session.currentUser?.id == user.id,
              session.currentUser?.appleUserIdentifier == subject,
              session.isSignedIn,
              state == .revoked || state == .notFound
        else { return }

        isHandlingAppleCredentialRevocation = true
        sessionRevision += 1
        let cleanupRevision = sessionRevision
        defer { isHandlingAppleCredentialRevocation = false }
        let didEndRemoteSession = await appleCredentialRevocationHandler(user.id)
        guard didEndRemoteSession, sessionRevision == cleanupRevision else { return }
        restoreLocalFallbackAfterRemoteDisconnect()
    }

    func handleAppleSignInFailure(_ error: Error) {
        errorMessage = userMessage(for: error)
    }

    func continueAsLocalUser() {
        guard !isRemoteSessionTransitionInProgress else { return }
        revokeFeedCacheBoundary(session.currentUser?.id)
        sessionRevision += 1
        session = repository.continueAsLocalUser(displayName: displayNameText.isEmpty ? "SOOM 사용자" : displayNameText)
        displayNameText = session.currentUser?.displayName ?? ""
        errorMessage = nil
    }

    func updateDisplayName() async {
        guard !isRemoteSessionTransitionInProgress else { return }
        guard var user = session.currentUser, user.authProvider == .supabase else {
            let demoAvatarPath = session.currentUser?.avatarPath
            sessionRevision += 1
            session = repository.updateDisplayName(displayNameText)
            if ReviewDemoMode.isActive, session.currentUser?.id == ReviewDemoMode.userID {
                session.currentUser?.avatarPath = demoAvatarPath
            }
            displayNameText = session.currentUser?.displayName ?? displayNameText
            errorMessage = session.errorMessage
            return
        }
        let name = displayNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else {
            errorMessage = "표시 이름은 1~80자로 입력해 주세요."
            return
        }
        guard let remoteDisplayNameHandler else {
            errorMessage = AuthError.futureRemoteAuthNotConfigured.userMessage
            return
        }
        let revision = sessionRevision
        isUpdatingDisplayName = true
        defer { isUpdatingDisplayName = false }
        do {
            let savedName = try await remoteDisplayNameHandler(user.id, name)
            guard sessionRevision == revision, session.currentUser?.id == user.id else { return }
            user.displayName = savedName
            session = .signedIn(user: user)
            displayNameText = savedName
            errorMessage = nil
        } catch {
            guard sessionRevision == revision, session.currentUser?.id == user.id else { return }
            errorMessage = userMessage(for: error)
        }
    }

    func updateAvatar(_ data: Data?) async -> Bool {
        guard !isRemoteSessionTransitionInProgress else { return false }
        if ReviewDemoMode.isActive, var user = session.currentUser,
           user.id == ReviewDemoMode.userID, user.authProvider == .local {
            do {
                user.avatarPath = try ReviewDemoAvatarStore.shared.save(imageData: data, userID: user.id)
                session = .localOnly(user: user)
                errorMessage = nil
                return true
            } catch {
                errorMessage = (error as? ProfileAvatarError)?.errorDescription ?? userMessage(for: error)
                return false
            }
        }
        guard var user = session.currentUser,
              user.authProvider == .supabase, let remoteAvatarHandler else {
            errorMessage = "프로필 사진은 로그인한 계정에 저장할 수 있어요."
            return false
        }
        let revision = sessionRevision
        isUpdatingAvatar = true
        defer { isUpdatingAvatar = false }
        do {
            let savedPath = try await remoteAvatarHandler(user.id, data)
            guard sessionRevision == revision, session.currentUser?.id == user.id else { return false }
            user.avatarPath = savedPath
            session = .signedIn(user: user)
            errorMessage = nil
            return true
        } catch {
            guard sessionRevision == revision, session.currentUser?.id == user.id else { return false }
            errorMessage = (error as? ProfileAvatarError)?.errorDescription ?? userMessage(for: error)
            return false
        }
    }

    func signOut() {
        guard !isRemoteSessionTransitionInProgress else { return }
        revokeFeedCacheBoundary(session.currentUser?.id)
        sessionRevision += 1
        session = repository.signOut()
        displayNameText = ""
        errorMessage = nil
    }

    /// Handles SDK expiry/revocation while idle. Explicit auth transitions own
    /// their completion, and a delayed event for A must not disconnect B.
    func remoteSessionDidEnd(expectedUserID: UUID) {
        guard !isRemoteSessionTransitionInProgress,
              session.currentUser?.authProvider == .supabase,
              session.currentUser?.id == expectedUserID else { return }
        restoreLocalFallbackAfterRemoteDisconnect()
    }

    func disconnectRemoteAccount() async {
        guard !isRemoteSessionTransitionInProgress else { return }
        isDisconnectingRemoteAccount = true
        defer { isDisconnectingRemoteAccount = false }
        let revision = sessionRevision
        guard session.currentUser?.authProvider == .supabase else {
            restoreLocalFallbackAfterRemoteDisconnect()
            return
        }

        guard let remoteSignOutHandler else {
            errorMessage = AuthError.futureRemoteAuthNotConfigured.userMessage
            return
        }

        revokeFeedCacheBoundary(session.currentUser?.id)
        do {
            _ = try await remoteSignOutHandler()
            guard sessionRevision == revision else { return }
            restoreLocalFallbackAfterRemoteDisconnect()
        } catch {
            guard sessionRevision == revision else { return }
            errorMessage = userMessage(for: error)
        }
    }

    /// Deletes the account: for a Supabase-linked user this calls the remote
    /// `delete_own_account` RPC first (local session is only cleared if that
    /// succeeds, so a failed remote call never strands the user with a
    /// remote account but no local record of it); for a local-only (guest)
    /// user there is no remote step, so this only clears the local session.
    /// Returns whether the caller should proceed with wiping local stores.
    @discardableResult
    func deleteAccount() async -> Bool {
        await deleteAccount(expectedTarget: accountDeletionTarget)
    }

    @discardableResult
    func deleteAccount(expectedTarget: AccountDeletionTarget) async -> Bool {
        guard expectedTarget == accountDeletionTarget else {
            errorMessage = "계정이 변경됐어요. 현재 계정에서 삭제를 다시 확인해 주세요."
            return false
        }
        guard !isRemoteSessionTransitionInProgress else { return false }
        isAccountDeletionInProgress = true
        var shouldEraseLocalStores = false
        defer { if !shouldEraseLocalStores { isAccountDeletionInProgress = false } }
        let revision = sessionRevision
        let deletingUserID = session.currentUser?.id
        revokeFeedCacheBoundary(deletingUserID)
        if session.currentUser?.authProvider == .supabase {
            guard remoteAccountDeleteForUserHandler != nil || remoteAccountDeleteHandler != nil else {
                errorMessage = AuthError.futureRemoteAuthNotConfigured.userMessage
                return false
            }

            do {
                if let remoteAccountDeleteForUserHandler, let owner = expectedTarget.remoteUserID {
                    try await remoteAccountDeleteForUserHandler(owner)
                } else if let remoteAccountDeleteHandler {
                    // Compatibility for isolated callers; the app injects the
                    // owner-bound handler so the SDK also validates the target.
                    try await remoteAccountDeleteHandler()
                }
            } catch {
                guard sessionRevision == revision else { return false }
                errorMessage = userMessage(for: error)
                return false
            }
        }

        // The old account may have been deleted remotely, but a late response
        // must never sign out a replacement session or authorize its local wipe.
        guard sessionRevision == revision, session.currentUser?.id == deletingUserID else { return false }
        sessionRevision += 1
        session = repository.signOut()
        displayNameText = ""
        errorMessage = nil
        shouldEraseLocalStores = true
        return true
    }

    /// The caller releases this after the local erasure attempt, including failure.
    func finishAccountDeletion() {
        isAccountDeletionInProgress = false
    }

    private func userMessage(for error: Error) -> String {
        if let authError = error as? AuthError {
            return authError.userMessage
        }

        return "계정 연결 상태를 확인하지 못했어요. 현재 기록은 로컬에 유지됩니다."
    }

    private func publish(session newSession: AuthSession, preservingDisplayName: Bool) {
        if session.currentUser?.id != newSession.currentUser?.id { revokeFeedCacheBoundary(session.currentUser?.id) }
        sessionRevision += 1
        session = newSession
        if let displayName = newSession.currentUser?.displayName {
            displayNameText = displayName
        } else if !preservingDisplayName {
            displayNameText = ""
        }
        errorMessage = newSession.errorMessage
    }

    private func revokeFeedCacheBoundary(_ viewerID: UUID?) {
        // Gate-off auth behavior is unchanged; do not even instantiate the cache.
        guard FeedStaleSummaryCache.configuredMaximumAge != nil, let viewerID else { return }
        FeedStaleSummaryCache.shared.revokeAccountBoundary(viewerID: viewerID)
    }

    private func restoreLocalFallbackAfterRemoteDisconnect() {
        let localSession = repository.loadSession()
        if localSession.isLocalOnly, localSession.currentUser != nil {
            publish(session: localSession, preservingDisplayName: false)
        } else {
            let fallbackSession = repository.continueAsLocalUser(displayName: "SOOM 사용자")
            publish(session: fallbackSession, preservingDisplayName: false)
        }
        errorMessage = nil
    }
}
