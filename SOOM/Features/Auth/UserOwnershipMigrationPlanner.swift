import Foundation

struct UserOwnershipMigrationPlanner {
    func buildPlan(
        localSession: AuthSession,
        remoteSession: AuthSession? = nil,
        eligibleDataTypes: [UserOwnershipEligibleDataType] = UserOwnershipEligibleDataType.localFirstDefaults
    ) -> UserOwnershipMigrationPlan {
        let localUser = localSession.currentUser?.authProvider == .local ? localSession.currentUser : nil
        let remoteUser = preferredRemoteUser(localSession: localSession, remoteSession: remoteSession)

        guard let remoteUser else {
            return UserOwnershipMigrationPlan(
                localUserId: localUser?.id,
                remoteUserId: nil,
                ownershipScope: .localOnly,
                eligibleDataTypes: [],
                requiresUserConsent: false,
                migrationStatus: .notLinked
            )
        }

        guard !eligibleDataTypes.isEmpty else {
            return UserOwnershipMigrationPlan(
                localUserId: localUser?.id,
                remoteUserId: remoteUser.id,
                ownershipScope: .remoteAccountLinked,
                eligibleDataTypes: [],
                requiresUserConsent: false,
                migrationStatus: .deferred
            )
        }

        return UserOwnershipMigrationPlan(
            localUserId: localUser?.id,
            remoteUserId: remoteUser.id,
            ownershipScope: .migrationEligible,
            eligibleDataTypes: eligibleDataTypes,
            requiresUserConsent: true,
            migrationStatus: .awaitingConsent
        )
    }

    func buildPlan(
        localSession: AuthSession,
        remoteSession: AuthSession? = nil,
        localDataPresence: LocalDataPresence
    ) -> UserOwnershipMigrationPlan {
        buildPlan(
            localSession: localSession,
            remoteSession: remoteSession,
            eligibleDataTypes: localDataPresence.eligibleDataTypes
        )
    }

    private func preferredRemoteUser(localSession: AuthSession, remoteSession: AuthSession?) -> AppUser? {
        if let remoteUser = remoteSession?.currentUser, remoteUser.authProvider == .supabase {
            return remoteUser
        }

        if let currentUser = localSession.currentUser, currentUser.authProvider == .supabase {
            return currentUser
        }

        return nil
    }
}
