import XCTest
@testable import SOOM

final class UserOwnershipMigrationPlannerTests: XCTestCase {
    private let planner = UserOwnershipMigrationPlanner()
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testLocalOnlyBuildsNotLinkedPlan() {
        let localSession = AuthSession.localOnly(user: localUser())

        let plan = planner.buildPlan(localSession: localSession)

        XCTAssertEqual(plan.localUserId, localSession.currentUser?.id)
        XCTAssertNil(plan.remoteUserId)
        XCTAssertEqual(plan.ownershipScope, .localOnly)
        XCTAssertEqual(plan.migrationStatus, .notLinked)
        XCTAssertFalse(plan.requiresUserConsent)
        XCTAssertTrue(plan.eligibleDataTypes.isEmpty)
    }

    func testRemoteSignedInWithLocalDataAwaitsConsent() {
        let localSession = AuthSession.localOnly(user: localUser())
        let remoteSession = AuthSession.signedIn(user: remoteUser())

        let plan = planner.buildPlan(
            localSession: localSession,
            remoteSession: remoteSession,
            localDataPresence: LocalDataPresence(
                hasTrainingSettings: true,
                hasWorkouts: true,
                hasWorkoutRoutes: true,
                hasProgressionData: false
            )
        )

        XCTAssertEqual(plan.localUserId, localSession.currentUser?.id)
        XCTAssertEqual(plan.remoteUserId, remoteSession.currentUser?.id)
        XCTAssertEqual(plan.ownershipScope, .migrationEligible)
        XCTAssertEqual(plan.migrationStatus, .awaitingConsent)
        XCTAssertTrue(plan.requiresUserConsent)
        XCTAssertEqual(plan.eligibleDataTypes, [.trainingSettings, .workouts, .workoutRoutes, .courseIdentities])
    }

    func testRemoteSignedInWithoutLocalDataDefersMigration() {
        let localSession = AuthSession.signedIn(user: remoteUser())

        let plan = planner.buildPlan(
            localSession: localSession,
            localDataPresence: .empty
        )

        XCTAssertNil(plan.localUserId)
        XCTAssertEqual(plan.remoteUserId, localSession.currentUser?.id)
        XCTAssertEqual(plan.ownershipScope, .remoteAccountLinked)
        XCTAssertEqual(plan.migrationStatus, .deferred)
        XCTAssertFalse(plan.requiresUserConsent)
        XCTAssertTrue(plan.eligibleDataTypes.isEmpty)
    }

    func testRemoteSignedInWithLocalDataNeverAutoMigrates() {
        let plan = planner.buildPlan(
            localSession: .localOnly(user: localUser()),
            remoteSession: .signedIn(user: remoteUser()),
            eligibleDataTypes: UserOwnershipEligibleDataType.localFirstDefaults
        )

        XCTAssertNotEqual(plan.migrationStatus, .migratedFuture)
        XCTAssertEqual(plan.migrationStatus, .awaitingConsent)
        XCTAssertTrue(plan.requiresUserConsent)
    }

    func testRemoteSignedInWithWorkoutOnlyAwaitsConsentForWorkoutsOnly() {
        let plan = planner.buildPlan(
            localSession: .signedIn(user: remoteUser()),
            localDataPresence: LocalDataPresence(
                hasTrainingSettings: false,
                hasWorkouts: true,
                hasWorkoutRoutes: false,
                hasProgressionData: false
            )
        )

        XCTAssertEqual(plan.migrationStatus, .awaitingConsent)
        XCTAssertTrue(plan.requiresUserConsent)
        XCTAssertEqual(plan.eligibleDataTypes, [.workouts])
    }

    func testRemoteSessionPreferenceDoesNotMutateInputSessions() {
        let localSession = AuthSession.localOnly(user: localUser())
        let remoteSession = AuthSession.signedIn(user: remoteUser())

        _ = planner.buildPlan(localSession: localSession, remoteSession: remoteSession)

        XCTAssertTrue(localSession.isLocalOnly)
        XCTAssertEqual(remoteSession.currentUser?.authProvider, .supabase)
    }

    func testPlannerDoesNotUseRecoveryCalculator() {
        let plan = planner.buildPlan(localSession: .signedOut)

        XCTAssertEqual(plan.migrationStatus, .notLinked)
    }

    private func localUser() -> AppUser {
        AppUser(
            id: UUID(uuidString: "23232323-2323-2323-2323-232323232323")!,
            displayName: "Local User",
            authProvider: .local,
            createdAt: fixedDate
        )
    }

    private func remoteUser() -> AppUser {
        AppUser(
            id: UUID(uuidString: "24242424-2424-2424-2424-242424242424")!,
            displayName: "Remote User",
            email: "remote@example.com",
            authProvider: .supabase,
            createdAt: fixedDate
        )
    }
}
