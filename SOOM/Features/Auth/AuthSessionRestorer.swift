import Foundation

struct AuthSessionRestorer {
    private let repository: any AuthRepository
    private let remoteSessionLoader: (any RemoteAuthSessionLoading)?
    private let policy: AuthSessionRestorePolicy

    init(
        repository: any AuthRepository,
        remoteSessionLoader: (any RemoteAuthSessionLoading)?,
        policy: AuthSessionRestorePolicy = .preferRemoteIfAvailable
    ) {
        self.repository = repository
        self.remoteSessionLoader = remoteSessionLoader
        self.policy = policy
    }

    func restore() async -> AuthSession {
        let localSession = repository.loadSession()

        switch policy {
        case .preferRemoteIfAvailable:
            guard let remoteSession = await remoteSessionLoader?.loadRemoteSession(),
                  remoteSession.isSignedIn
            else {
                return localSession
            }
            return remoteSession

        case .localFirst:
            return localSession

        case .remoteOnlyFuture:
            guard let remoteSession = await remoteSessionLoader?.loadRemoteSession(),
                  remoteSession.isSignedIn
            else {
                return .signedOut
            }
            return remoteSession
        }
    }
}
