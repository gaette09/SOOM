import SwiftData
import XCTest
@testable import SOOM

@MainActor final class Feed61OwnLocalRecordTests: XCTestCase {
    func testPendingLocalDisplayRequiresExactOwnerAndCurrentSecurityScope() {
        let owner = UUID(), other = UUID()
        let context = FeedReturnBatchContext(viewerID: owner, accountGeneration: 7, safetyRevision: 8, returnEpoch: 9)
        func allowed(_ mismatch: Int?) -> Bool {
            FeedPendingOwnRecordPolicy.allows(ownerID: owner,
                authOwnerID: mismatch == 0 ? other : owner, viewerID: mismatch == 1 ? other : owner,
                storageOwnerID: mismatch == 2 ? other : owner, context: context,
                generation: mismatch == 3 ? 10 : 7, safetyRevision: mismatch == 4 ? 10 : 8,
                returnEpoch: mismatch == 5 ? 10 : 9, pending: mismatch != 6,
                active: mismatch != 7, socialAllowed: mismatch != 8,
                sameContainer: mismatch != 9, retired: mismatch == 10)
        }
        XCTAssertTrue(allowed(nil))
        for mismatch in 0...10 { XCTAssertFalse(allowed(mismatch), "Mismatch \(mismatch) must close local display") }
        XCTAssertFalse(FeedPendingOwnRecordPolicy.allows(ownerID: other, authOwnerID: owner,
            viewerID: owner, storageOwnerID: owner, context: context, generation: 7,
            safetyRevision: 8, returnEpoch: 9, pending: true, active: true,
            socialAllowed: true, sameContainer: true, retired: false), "A foreign card is never a local owner fallback")
        let header = Feed61OwnedAuthorPresentation.resolve(.localOwner, authName: "private name", authID: owner, authAvatarPath: "private path")
        XCTAssertEqual(header.name, "내 기록"); XCTAssertNil(header.id); XCTAssertNil(header.avatarPath)
    }

    func testObservedOwnSourceTracksSameTimestampEditsAndDeletion() throws {
        let (container, owner, record) = try fixture()
        let originalDate = record.updatedAt, id = record.id
        func observed(authOwner: UUID? = nil, active: Bool = true) -> Feed61OwnLocalRecordReader.Result {
            Feed61OwnLocalRecordReader.readObserved(record: record, canonicalID: id,
                context: container.mainContext, storageContainer: container, ownerID: owner,
                authOwnerID: authOwner ?? owner, viewerID: owner, storageOwnerID: owner,
                isCurrent: { active })
        }
        XCTAssertEqual(observed().workout?.durationSeconds, 600)
        record.durationSeconds = 1234; record.userTitle = "Changed without timestamp"
        XCTAssertEqual(record.updatedAt, originalDate)
        XCTAssertEqual(observed().workout?.durationSeconds, 1234)
        XCTAssertEqual(observed().workout?.userTitle, "Changed without timestamp")
        XCTAssertNil(observed(authOwner: UUID()).workout)
        XCTAssertNil(observed(active: false).workout)
        container.mainContext.delete(record)
        XCTAssertNil(observed().workout)
    }

    private func fixture() throws -> (ModelContainer, UUID, UnifiedWorkoutRecord) {
        let schema = HealthAccountStorageController.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let owner = UUID(); HealthCloudJournal.register(container, userID: owner)
        let record = UnifiedWorkoutRecord(sourceRaw: UnifiedDataSource.soomLocal.rawValue,
            workoutTypeRaw: UnifiedWorkoutType.running.rawValue, startDate: Date(), endDate: Date(),
            durationSeconds: 600, dataQualityRaw: UnifiedDataQuality.complete.rawValue)
        container.mainContext.insert(record); try container.mainContext.save()
        return (container, owner, record)
    }
    private func read(_ container: ModelContainer, _ owner: UUID, _ id: UUID,
                      current: Bool = true, auth: UUID? = nil, viewer: UUID? = nil,
                      storageOwner: UUID? = nil, storageContainer: ModelContainer? = nil) -> Feed61OwnLocalRecordReader.Result {
        Feed61OwnLocalRecordReader.read(canonicalID: id, context: container.mainContext,
            storageContainer: storageContainer ?? container, ownerID: owner,
            authOwnerID: auth ?? owner, viewerID: viewer ?? owner, storageOwnerID: storageOwner ?? owner,
            isCurrent: { current })
    }
    func testUnverifiedForeignAndCancelledContextsNeverReachReadClosure() {
        var queries = 0
        for _ in 0..<8 {
            let result = Feed61OwnLocalRecordReader.resolve(canonicalID: UUID(), isCurrent: { false }) {
                queries += 1; return nil
            }
            XCTAssertFalse(result.isResolved)
        }
        XCTAssertEqual(queries, 0)
    }
    func testContextChangesDuringReadDiscardResultRatherThanClaimAbsence() {
        var current = true, queries = 0
        let result = Feed61OwnLocalRecordReader.resolve(canonicalID: UUID(), isCurrent: { current }) {
            queries += 1; current = false; return nil
        }
        XCTAssertEqual(queries, 1); XCTAssertFalse(result.isResolved)
    }
    func testMissingIsResolvedRemoteFallbackButReadErrorIsNot() {
        let missing = Feed61OwnLocalRecordReader.resolve(canonicalID: UUID(), isCurrent: { true }, read: { nil })
        XCTAssertTrue(missing.isResolved); XCTAssertNil(missing.workout)
        let failed = Feed61OwnLocalRecordReader.resolve(canonicalID: UUID(), isCurrent: { true }) {
            throw CancellationError()
        }
        XCTAssertFalse(failed.isResolved)
    }
    func testInitialAuthorizedOwnerGetsCurrentRecordWithoutAsyncState() throws {
        let (container, owner, record) = try fixture()
        let value = read(container, owner, record.id)
        XCTAssertTrue(value.isResolved); XCTAssertEqual(value.workout?.id, record.id)
        XCTAssertEqual(value.workout?.durationSeconds, 600)
    }
    func testChangedContentWithUnchangedTimestampIsReadFresh() throws {
        let (container, owner, record) = try fixture()
        let timestamp = record.updatedAt
        XCTAssertEqual(read(container, owner, record.id).workout?.durationSeconds, 600)
        record.durationSeconds = 1200; record.userTitle = "updated"
        try container.mainContext.save()
        XCTAssertEqual(record.updatedAt, timestamp)
        let next = read(container, owner, record.id).workout
        XCTAssertEqual(next?.durationSeconds, 1200); XCTAssertEqual(next?.userTitle, "updated")
    }
    func testUnsavedAndSavedDeletionCannotRestorePreviousWorkout() throws {
        let (container, owner, record) = try fixture(); let id = record.id
        XCTAssertNotNil(read(container, owner, id).workout)
        container.mainContext.delete(record)
        XCTAssertNil(read(container, owner, id).workout)
        try container.mainContext.save()
        XCTAssertNil(read(container, owner, id).workout)
    }
    func testReplacementUnderSameCanonicalIDUsesNewSource() throws {
        let (container, owner, record) = try fixture(); let id = record.id
        container.mainContext.delete(record); try container.mainContext.save()
        let replacement = UnifiedWorkoutRecord(id: id, sourceRaw: UnifiedDataSource.soomLocal.rawValue,
            workoutTypeRaw: UnifiedWorkoutType.cycling.rawValue, startDate: Date(), endDate: Date(),
            durationSeconds: 900, dataQualityRaw: UnifiedDataQuality.complete.rawValue)
        container.mainContext.insert(replacement); try container.mainContext.save()
        XCTAssertEqual(read(container, owner, id).workout?.workoutType, .cycling)
        XCTAssertEqual(read(container, owner, id).workout?.durationSeconds, 900)
    }
    func testDifferentContainerAndEveryOwnerIdentityMismatchAreRejected() throws {
        let (container, owner, record) = try fixture()
        let (otherContainer, otherOwner, _) = try fixture()
        XCTAssertFalse(read(container, owner, record.id, storageContainer: otherContainer).isResolved)
        XCTAssertFalse(read(container, owner, record.id, auth: otherOwner).isResolved)
        XCTAssertFalse(read(container, owner, record.id, viewer: otherOwner).isResolved)
        XCTAssertFalse(read(container, owner, record.id, storageOwner: otherOwner).isResolved)
        XCTAssertFalse(read(container, otherOwner, record.id).isResolved, "Journal belongs to the original owner")
        XCTAssertFalse(read(container, owner, record.id, current: false).isResolved)
    }
    func testRetiredContainerRejectsReadAndNewRowRecreation() throws {
        let (container, owner, record) = try fixture(); let id = record.id
        HealthCloudJournal.retire(container)
        XCTAssertFalse(read(container, owner, id).isResolved)
        XCTAssertFalse(read(container, owner, id).isResolved)
    }
    func testWrongCanonicalRecordNeverPassesPureResolver() throws {
        let (container, owner, record) = try fixture()
        let value = try XCTUnwrap(read(container, owner, record.id).workout)
        let result = Feed61OwnLocalRecordReader.resolve(canonicalID: UUID(), isCurrent: { true }, read: { value })
        XCTAssertFalse(result.isResolved)
    }
    func testImmediateTapOpensOnlyAfterVerificationWithSameLiveReceiptAndScope() throws {
        let (container, owner, record) = try fixture()
        let result = read(container, owner, record.id)
        func allowed(key: String = "key", scope: String = "scope", verified: Bool = true,
                     grant: Bool = true, cancelled: Bool = false) -> Bool {
            Feed61OwnLocalRecordReader.canOpen(result, requiresLocalRecord: true,
                expectedKey: "key", currentKey: key, expectedScope: "scope", currentScope: scope,
                verified: verified, liveGrantCurrent: grant, cancelled: cancelled)
        }
        XCTAssertFalse(allowed(verified: false), "Initial display alone must not authorize opening")
        XCTAssertTrue(allowed(), "The same current receipt may open after the normal verifier completes")
        XCTAssertFalse(allowed(key: "new-epoch")); XCTAssertFalse(allowed(scope: "new-container-scope"))
        XCTAssertFalse(allowed(grant: false)); XCTAssertFalse(allowed(cancelled: true))
    }
    func testDeletedLocalTapNeverTurnsIntoRemoteOnlyFallback() {
        func open(_ result: Feed61OwnLocalRecordReader.Result, requiresLocal: Bool) -> Bool {
            Feed61OwnLocalRecordReader.canOpen(result, requiresLocalRecord: requiresLocal,
                expectedKey: "key", currentKey: "key", expectedScope: "scope", currentScope: "scope",
                verified: true, liveGrantCurrent: true, cancelled: false)
        }
        XCTAssertFalse(open(.missing, requiresLocal: true))
        XCTAssertTrue(open(.missing, requiresLocal: false), "An originally remote-only owned summary retains its permitted route")
        XCTAssertFalse(open(.unavailable, requiresLocal: false))
    }
    func testBusyAdoptionRetriesOnceAndEqualRawSourceDoesNotPublishAgain() throws {
        let (container, owner, record) = try fixture()
        let old = try XCTUnwrap(read(container, owner, record.id).workout)
        record.durationSeconds += 30
        let fresh = try XCTUnwrap(read(container, owner, record.id).workout)
        XCTAssertFalse(Feed61OwnLocalRecordReader.shouldAdopt(current: old, source: fresh, isWorking: true))
        XCTAssertTrue(Feed61OwnLocalRecordReader.shouldAdopt(current: old, source: fresh, isWorking: false))
        XCTAssertFalse(Feed61OwnLocalRecordReader.shouldAdopt(current: fresh, source: fresh, isWorking: false))
        XCTAssertFalse(Feed61OwnLocalRecordReader.shouldAdopt(current: fresh, source: fresh, isWorking: true))
    }

    private func identity(_ workout: UnifiedWorkout, account: AccountDeletionTarget,
                          feed: Bool = true, route: WorkoutRouteReadSnapshot? = nil) -> WorkoutCardLoadIdentity {
        WorkoutCardLoadIdentity(account: account, scopeID: "test-scope", workoutID: workout.id,
            workoutUpdatedAt: workout.updatedAt, routeUpdatedAt: route?.updatedAt,
            routeContent: route, sourceWorkout: feed ? workout : nil)
    }
    private func identityAccount() throws -> AccountDeletionTarget {
        let suite = "Feed61OwnIdentity.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        return AuthViewModel(store: AuthSessionStore(userDefaults: defaults)).accountDeletionTarget
    }
    func testFeedIdentityChangesForSameTimestampTitleEdit() throws {
        let (container, owner, record) = try fixture(); let account = try identityAccount()
        let old = try XCTUnwrap(read(container, owner, record.id).workout)
        record.userTitle = "new title"
        let fresh = try XCTUnwrap(read(container, owner, record.id).workout)
        XCTAssertEqual(old.id, fresh.id); XCTAssertEqual(old.updatedAt, fresh.updatedAt)
        XCTAssertNotEqual(identity(old, account: account), identity(fresh, account: account))
    }
    func testFeedIdentityChangesForSameTimestampDurationAndSourceEdits() throws {
        let (container, owner, record) = try fixture(); let account = try identityAccount()
        let old = try XCTUnwrap(read(container, owner, record.id).workout)
        record.durationSeconds += 60
        let duration = try XCTUnwrap(read(container, owner, record.id).workout)
        XCTAssertEqual(old.updatedAt, duration.updatedAt)
        XCTAssertNotEqual(identity(old, account: account), identity(duration, account: account))
        record.durationSeconds = old.durationSeconds; record.sourceRaw = UnifiedDataSource.garmin.rawValue
        let source = try XCTUnwrap(read(container, owner, record.id).workout)
        XCTAssertEqual(old.id, source.id); XCTAssertEqual(old.updatedAt, source.updatedAt)
        XCTAssertNotEqual(identity(old, account: account), identity(source, account: account))
    }
    func testFeedIdentityIsStableForEqualSourceInput() throws {
        let (container, owner, record) = try fixture(); let account = try identityAccount()
        let first = try XCTUnwrap(read(container, owner, record.id).workout)
        let second = try XCTUnwrap(read(container, owner, record.id).workout)
        XCTAssertEqual(identity(first, account: account), identity(second, account: account))
    }
    func testIndependentIdentityPreservesExistingTimestampPolicy() throws {
        let (container, owner, record) = try fixture(); let account = try identityAccount()
        let old = try XCTUnwrap(read(container, owner, record.id).workout)
        record.durationSeconds += 60; record.userTitle = "changed"
        let fresh = try XCTUnwrap(read(container, owner, record.id).workout)
        let legacy = WorkoutCardLoadIdentity(account: account, scopeID: "test-scope", workoutID: old.id,
            workoutUpdatedAt: old.updatedAt, routeUpdatedAt: nil)
        XCTAssertEqual(legacy, identity(old, account: account, feed: false))
        XCTAssertEqual(legacy, identity(fresh, account: account, feed: false))
    }
    func testRouteContentStillInvalidatesBothFeedAndIndependentIdentity() throws {
        let (container, owner, record) = try fixture(); let account = try identityAccount()
        let workout = try XCTUnwrap(read(container, owner, record.id).workout)
        let route = PersistedWorkoutRoute(workoutId: workout.id, sourceRaw: workout.source.rawValue,
            encodedCoordinates: "before", totalDistanceMeters: 100)
        let before = WorkoutRouteReadSnapshot(route)
        route.encodedCoordinates = "after"
        let after = WorkoutRouteReadSnapshot(route)
        XCTAssertEqual(before.updatedAt, after.updatedAt)
        for feed in [true, false] {
            XCTAssertNotEqual(identity(workout, account: account, feed: feed, route: before),
                              identity(workout, account: account, feed: feed, route: after))
        }
    }

    func testOwnedHeaderUsesExactGrantAuthorInsteadOfStaleAuthSnapshot() {
        let owner = UUID(), staleOwner = UUID()
        let author = FeedProfileDTO(id: owner, displayName: "current grant", handle: nil, avatarPath: "current/path.jpg")
        let header = Feed61OwnedAuthorPresentation.resolve(.authorized(author), authName: "old auth",
            authID: staleOwner, authAvatarPath: "old/path.jpg")
        XCTAssertEqual(header.name, author.displayName); XCTAssertEqual(header.id, owner)
        XCTAssertEqual(header.avatarPath, author.avatarPath)
    }
    func testOwnedHeaderUnavailableDoesNotFallBackToAuth() {
        let header = Feed61OwnedAuthorPresentation.resolve(.unavailable, authName: "auth",
            authID: UUID(), authAvatarPath: "auth/path.jpg")
        XCTAssertEqual(header.name, "작성자 정보 확인 불가")
        XCTAssertNil(header.id); XCTAssertNil(header.avatarPath)
    }
    func testIndependentOwnedHeaderRetainsAuthPresentation() {
        let owner = UUID()
        let header = Feed61OwnedAuthorPresentation.resolve(nil, authName: "auth",
            authID: owner, authAvatarPath: "auth/path.jpg")
        XCTAssertEqual(header.name, "auth"); XCTAssertEqual(header.id, owner)
        XCTAssertEqual(header.avatarPath, "auth/path.jpg")
        XCTAssertEqual(Feed61OwnedAuthorPresentation.resolve(nil, authName: nil, authID: nil,
            authAvatarPath: nil).name, "나")
    }
    func testOwnedGrantAuthorWithoutAvatarNeverUsesAuthAvatar() {
        let author = FeedProfileDTO(id: UUID(), displayName: "grant", handle: nil, avatarPath: nil)
        let header = Feed61OwnedAuthorPresentation.resolve(.authorized(author), authName: "auth",
            authID: author.id, authAvatarPath: "old/avatar.jpg")
        XCTAssertEqual(header.id, author.id); XCTAssertNil(header.avatarPath)
    }
    func testOwnedHeaderDoesNotDependOnPhotoAvailabilityOrRouteIdentity() throws {
        let author = FeedProfileDTO(id: UUID(), displayName: "grant", handle: nil, avatarPath: "grant/avatar.jpg")
        let header = Feed61OwnedAuthorPresentation.resolve(.authorized(author), authName: nil,
            authID: nil, authAvatarPath: nil)
        for photos: Feed61OwnedPhotoPresentation in [.authorized([]), .unavailable] {
            XCTAssertTrue(photos.photos.isEmpty)
            XCTAssertEqual(Feed61OwnedAuthorPresentation.resolve(.authorized(author), authName: nil,
                authID: nil, authAvatarPath: nil), header)
        }
        let (container, owner, record) = try fixture(); let account = try identityAccount()
        let workout = try XCTUnwrap(read(container, owner, record.id).workout)
        XCTAssertEqual(identity(workout, account: account), identity(workout, account: account))
    }

}
