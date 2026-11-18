import SwiftData
import XCTest
@testable import SOOM

@MainActor
final class HealthCloudSyncTests: XCTestCase {
    func test72LargeRouteBatchValidationMainThreadCost() throws {
        let id = UUID()
        let points = (0..<5000).map { i in WorkoutRouteCoordinate(latitude: 37 + Double(i) * 0.00001,
            longitude: 127 + Double(i) * 0.000001) }
        let record = PersistedWorkoutRoute(workoutId: id, sourceRaw: UnifiedDataSource.soomLocal.rawValue,
            encodedCoordinates: WorkoutRouteMapper().encodeCoordinates(points), coordinateCount: points.count,
            totalDistanceMeters: 5600)
        let data = try HealthCloudPayload(route: .init(record)).encoded()
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<16 { try HealthCloudJournal.validate(kind: "route", key: id.uuidString, data: data, deleted: false) }
        print("SOOM72_CLOUD_VALIDATION rows=16 points_each=5000 main_ms=\((CFAbsoluteTimeGetCurrent()-start)*1000)")
    }

    func test72BackgroundValidationAllowsMainActorProgressAndPreservesInvalidClassification() async throws {
        let id = UUID()
        let points = (0..<5000).map { i in WorkoutRouteCoordinate(latitude: 37 + Double(i) * 0.00001,
            longitude: 127 + Double(i) * 0.000001) }
        let record = PersistedWorkoutRoute(workoutId: id, sourceRaw: UnifiedDataSource.soomLocal.rawValue,
            encodedCoordinates: WorkoutRouteMapper().encodeCoordinates(points), coordinateCount: points.count,
            totalDistanceMeters: 5600)
        let data = try HealthCloudPayload(route: .init(record)).encoded()
        let good = HealthCloudRemoteRecord(kind: "route", recordKey: id.uuidString,
            payloadJSON: String(data: data, encoding: .utf8), isDeleted: false, version: 1, revision: 1)
        let invalid = HealthCloudRemoteRecord(kind: "route", recordKey: id.uuidString,
            payloadJSON: "{}", isDeleted: false, version: 1, revision: 2)
        let tombstone = HealthCloudRemoteRecord(kind: "route", recordKey: id.uuidString,
            payloadJSON: nil, isDeleted: true, version: 2, revision: 3)
        // Exclude host launch work from this phase measurement.
        try await Task.sleep(for: .milliseconds(500))
        var ticks = 0, maxGap = 0.0, last = CFAbsoluteTimeGetCurrent()
        let pulse = Task { @MainActor in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(2)) } catch { break }
                let now = CFAbsoluteTimeGetCurrent(); maxGap = max(maxGap, now - last); last = now; ticks += 1
            }
        }
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await HealthCloudJournal.validateBatch(Array(repeating: good, count: 16) + [invalid, tombstone])
        pulse.cancel()
        XCTAssertEqual(result, Array(repeating: true, count: 16) + [false, true])
        XCTAssertGreaterThan(ticks, 3, "Validation must not monopolize the UI executor")
        print("SOOM72_BACKGROUND_VALIDATION rows=18 elapsed_ms=\((CFAbsoluteTimeGetCurrent()-start)*1000) main_ticks=\(ticks) maximum_main_gap_ms=\(maxGap*1000)")
        let canceled = Task { try await HealthCloudJournal.validateBatch(Array(repeating: good, count: 100)) }
        canceled.cancel()
        do { _ = try await canceled.value; XCTFail("Cancelled validation must not return a usable grant") }
        catch is CancellationError { }
    }

    private func controller(_ remote: FakeHealthRemote? = nil) throws -> HealthAccountStorageController {
        try HealthAccountStorageController(remote: remote, inMemory: true,
            monitorNetwork: false, automaticallySync: false)
    }
    private func workout(id: UUID = UUID(), distance: Double = 1500) -> UnifiedWorkout {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return UnifiedWorkout(id: id, externalId: nil, source: .soomLocal, workoutType: .running,
            startDate: date, endDate: date.addingTimeInterval(600), durationSeconds: 600,
            distanceMeters: distance, activeEnergyKcal: nil, averageHeartRate: nil,
            maxHeartRate: nil, averageSpeedMetersPerSecond: nil, elevationGainMeters: nil,
            dataQuality: .partial, isExcludedFromAnalysis: true,
            createdAt: date, updatedAt: date, companionNames: ["Synthetic companion"])
    }
    private func entries(_ controller: HealthAccountStorageController) throws -> [HealthCloudOutboxRecord] {
        try controller.container.mainContext.fetch(FetchDescriptor<HealthCloudOutboxRecord>())
            .filter { HealthCloudKind(rawValue: $0.kind) != nil }
    }

    func testEmptyForegroundSyncDoesNotInvalidateFeedDataRevision() async throws {
        let remote = FakeHealthRemote(), subject = try controller(remote)
        try subject.switchAccount(userID: UUID()); try subject.setCloudConsent(true)
        let revision = subject.dataRevision
        for _ in 0..<3 { await subject.syncNow() }
        XCTAssertEqual(subject.dataRevision, revision, "Unchanged foreground sync must not trigger full feed reloads")
        XCTAssertNotNil(subject.lastSyncAt)
        XCTAssertFalse(subject.isSyncing)
    }

    func testActualPullChangesRevisionButRepeatedReceiptDoesNot() async throws {
        let remote = FakeHealthRemote(), subject = try controller(remote), owner = UUID()
        try subject.switchAccount(userID: owner); try subject.setCloudConsent(true)
        let before = subject.dataRevision, item = workout()
        remote.install(item, owner: owner)
        await subject.syncNow()
        XCTAssertGreaterThan(subject.dataRevision, before)
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 1)
        let settled = subject.dataRevision
        await subject.syncNow(); await subject.syncNow()
        XCTAssertEqual(subject.dataRevision, settled)
    }

    func testMultiPageSyncPublishesOneRevisionAndPartialFailureStillPublishesSavedChanges() async throws {
        let remote = FakeHealthRemote(), owner = UUID(), subject = try controller(remote)
        try subject.switchAccount(userID: owner); try subject.setCloudConsent(true)
        remote.pageSize = 1
        for _ in 0..<3 { remote.install(workout(), owner: owner) }
        let initial = subject.dataRevision
        await subject.syncNow()
        XCTAssertEqual(subject.dataRevision, initial + 1, "Saved pull pages must not restart the feed separately")
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 3)
        remote.install(workout(), owner: owner); remote.install(workout(), owner: owner)
        remote.failPullAfter = remote.calls + 1
        let beforeFailure = subject.dataRevision
        await subject.syncNow()
        XCTAssertEqual(subject.dataRevision, beforeFailure + 1, "A later failed page cannot hide an already committed change")
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 4)
        XCTAssertNotNil(subject.errorMessage)
        remote.failPullAfter = nil
        await subject.syncNow()
        XCTAssertEqual(subject.dataRevision, beforeFailure + 2)
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 5)
        await subject.syncNow()
        XCTAssertEqual(subject.dataRevision, beforeFailure + 2, "A subsequent empty sync remains silent")
    }

    func testGuestSavesLocallyAndNeverCallsRemote() async throws {
        let remote = FakeHealthRemote()
        let subject = try controller(remote)
        let item = workout()
        try await SwiftDataUnifiedWorkoutStore(modelContext: subject.container.mainContext).saveWorkout(item)
        await subject.syncNow()
        XCTAssertEqual(remote.calls, 0)
        XCTAssertTrue(try entries(subject).isEmpty)
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 1)
    }

    func testAccountSwitchSeparatesAllFourStoresAndLateWritesStayWithOldAccount() async throws {
        let subject = try controller()
        let a = UUID(), b = UUID()
        try subject.switchAccount(userID: a)
        let oldContext = subject.container.mainContext
        let item = workout()
        try await SwiftDataUnifiedWorkoutStore(modelContext: oldContext).saveWorkout(item)
        oldContext.insert(CheckInRecord(date: Date(), fatigueLevel: 2, sleepQuality: 3, muscleSoreness: 2, moodLevel: 4))
        oldContext.insert(DailyRecoverySnapshotRecord(date: Date(), score: 60, status: "known", recommendation: "rest", coachMessage: "test", dataQuality: "estimated", activityCount: 0))
        oldContext.insert(PersistedWorkoutRoute(workoutId: item.id, sourceRaw: "soomLocal", totalDistanceMeters: 1500))
        try oldContext.save()
        try subject.switchAccount(userID: b)
        try await SwiftDataUnifiedWorkoutStore(modelContext: oldContext).saveWorkout(workout())
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 0)
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<CheckInRecord>()), 0)
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<DailyRecoverySnapshotRecord>()), 0)
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<PersistedWorkoutRoute>()), 0)
        try subject.switchAccount(userID: a)
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 2)
        XCTAssertEqual(try entries(subject).count, 2)
    }

    func testConsentIsAccountScopedAndRequiredBeforeAnyNetwork() async throws {
        let remote = FakeHealthRemote()
        let subject = try controller(remote)
        let a = UUID()
        try subject.switchAccount(userID: a)
        try await SwiftDataUnifiedWorkoutStore(modelContext: subject.container.mainContext).saveWorkout(workout())
        await subject.syncNow()
        XCTAssertEqual(remote.calls, 0)
        XCTAssertEqual(try entries(subject).filter(\.pending).count, 1)
        try subject.setCloudConsent(true)
        await subject.syncNow()
        XCTAssertEqual(remote.rows[a]?.count, 1)
        try subject.switchAccount(userID: UUID())
        XCTAssertFalse(subject.cloudConsentGranted)
        try subject.switchAccount(userID: a)
        XCTAssertTrue(subject.cloudConsentGranted)
    }

    func testExplicitGuestImportIsIdempotentAndCannotBeClaimedBySecondAccount() async throws {
        let subject = try controller()
        try await SwiftDataUnifiedWorkoutStore(modelContext: subject.container.mainContext).saveWorkout(workout())
        let a = UUID(), b = UUID()
        try subject.switchAccount(userID: a)
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 0)
        try subject.setCloudConsent(true)
        try subject.importGuestData(expectedUserID: a)
        try subject.importGuestData(expectedUserID: a)
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 1)
        try subject.switchAccount(userID: b)
        try subject.setCloudConsent(true)
        XCTAssertThrowsError(try subject.importGuestData(expectedUserID: b))
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 0)
    }

    func testRepeatedExplicitGuestImportAddsNewRecordsAndPreservesAccountEdits() async throws {
        let subject = try controller(), owner = UUID()
        let original = workout()
        try await SwiftDataUnifiedWorkoutStore(modelContext: subject.container.mainContext).saveWorkout(original)
        try subject.switchAccount(userID: owner); try subject.setCloudConsent(true)
        try subject.importGuestData(expectedUserID: owner)
        try await SwiftDataUnifiedWorkoutStore(modelContext: subject.container.mainContext)
            .updateCompanions(id: original.id, names: ["Account edit"])
        try subject.switchAccount(userID: nil)
        let added = workout()
        try await SwiftDataUnifiedWorkoutStore(modelContext: subject.container.mainContext).saveWorkout(added)
        try subject.switchAccount(userID: owner)
        try subject.importGuestData(expectedUserID: owner)
        let accountStore = SwiftDataUnifiedWorkoutStore(modelContext: subject.container.mainContext)
        let preserved = try await accountStore.fetchWorkout(id: original.id)
        let imported = try await accountStore.fetchWorkout(id: added.id)
        XCTAssertEqual(preserved?.companionNames, ["Account edit"])
        XCTAssertNotNil(imported)
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 2)
    }

    func testFailedUploadRemainsPendingAndRetryRestoresFullWorkoutOnAnotherDevice() async throws {
        let remote = FakeHealthRemote()
        let a = UUID(), item = workout()
        let first = try controller(remote)
        try first.switchAccount(userID: a)
        try first.setCloudConsent(true)
        try await SwiftDataUnifiedWorkoutStore(modelContext: first.container.mainContext).saveWorkout(item)
        remote.failPush = true
        await first.syncNow()
        XCTAssertEqual(try entries(first).filter(\.pending).count, 1)
        XCTAssertNotNil(first.errorMessage)
        remote.failPush = false
        await first.syncNow()
        XCTAssertEqual(try entries(first).filter(\.pending).count, 0)
        let second = try controller(remote)
        try second.switchAccount(userID: a)
        try second.setCloudConsent(true)
        await second.syncNow()
        let restored = try await SwiftDataUnifiedWorkoutStore(modelContext: second.container.mainContext).fetchWorkout(id: item.id)
        XCTAssertEqual(restored, item)
        XCTAssertEqual(remote.rows[a]?.count, 1)
    }

    func testRouteCheckInAndSnapshotPayloadsRestoreWithoutMetricFabrication() async throws {
        let remote = FakeHealthRemote(), owner = UUID()
        let first = try controller(remote)
        try first.switchAccount(userID: owner); try first.setCloudConsent(true)
        let item = workout(), context = first.container.mainContext
        let checkIn = RecoveryCheckIn(date: item.startDate, fatigueLevel: 2, sleepQuality: 4,
            muscleSoreness: 3, moodLevel: 4, note: "Synthetic note")
        try await SwiftDataCheckInStore(modelContext: context).saveCheckIn(checkIn)
        let snapshot = DailyRecoverySnapshot(date: item.startDate, score: 64, status: "test",
            recommendation: "rest", coachMessage: "test", dataQuality: .estimated,
            activityCount: 0, activityCountKnown: false, checkInId: checkIn.id)
        try await SwiftDataDailyRecoverySnapshotStore(modelContext: context).saveSnapshot(snapshot)
        let route = WorkoutRoute(workoutId: item.id, source: .soomLocal,
            coordinates: [.init(latitude: 37.1, longitude: 127.1, altitude: 42)], totalDistanceMeters: 0)
        try await SwiftDataUnifiedWorkoutStore(modelContext: context).saveWorkout(item)
        try await SwiftDataWorkoutRoutePersistenceStore(modelContext: context).saveRoute(route)
        await first.syncNow()
        let second = try controller(remote)
        try second.switchAccount(userID: owner); try second.setCloudConsent(true)
        await second.syncNow()
        let restoredCheckIn = try second.container.mainContext.fetch(FetchDescriptor<CheckInRecord>()).first
        let restoredSnapshot = try second.container.mainContext.fetch(FetchDescriptor<DailyRecoverySnapshotRecord>()).first
        let restoredRoute = try await SwiftDataWorkoutRoutePersistenceStore(modelContext: second.container.mainContext).fetchRoute(workoutId: item.id)
        XCTAssertEqual(restoredCheckIn?.note, "Synthetic note")
        XCTAssertEqual(restoredSnapshot?.activityCountKnown, false)
        XCTAssertEqual(restoredSnapshot?.checkInId, checkIn.id)
        XCTAssertEqual(restoredRoute?.coordinates.first?.latitude, 37.1)
        XCTAssertEqual(restoredRoute?.coordinates.first?.altitude, 42)
        XCTAssertEqual(remote.rows[owner]?.count, 4)
    }

    func testLostUploadAcknowledgmentDoesNotDuplicateOrCreateFalseConflict() async throws {
        let remote = FakeHealthRemote(), owner = UUID()
        let subject = try controller(remote)
        try subject.switchAccount(userID: owner); try subject.setCloudConsent(true)
        try await SwiftDataUnifiedWorkoutStore(modelContext: subject.container.mainContext).saveWorkout(workout())
        remote.failAfterCommit = true
        await subject.syncNow()
        XCTAssertEqual(try entries(subject).filter(\.pending).count, 1)
        await subject.syncNow()
        XCTAssertEqual(subject.conflictCount, 0)
        XCTAssertEqual(subject.pendingCount, 0)
        XCTAssertEqual(remote.rows[owner]?.count, 1)
        XCTAssertEqual(remote.rows[owner]?.values.first?.version, 1)
    }

    func testWorkoutDeleteProducesDurableWorkoutAndRouteTombstones() async throws {
        let remote = FakeHealthRemote(), owner = UUID()
        let subject = try controller(remote)
        try subject.switchAccount(userID: owner)
        try subject.setCloudConsent(true)
        let item = workout(), context = subject.container.mainContext
        let store = SwiftDataUnifiedWorkoutStore(modelContext: context)
        try await store.saveWorkout(item)
        try await SwiftDataWorkoutRoutePersistenceStore(modelContext: context).saveRoute(
            WorkoutRoute(workoutId: item.id, source: .soomLocal,
                coordinates: [.init(latitude: 37, longitude: 127)], totalDistanceMeters: 0))
        await subject.syncNow()
        XCTAssertNil(subject.errorMessage)
        let beforeDeletion = try await store.fetchWorkout(id: item.id)
        XCTAssertNotNil(beforeDeletion, "Server acknowledgment must retain the saved workout")
        XCTAssertEqual(try entries(subject).count, 2)
        try await store.deleteWorkout(id: item.id)
        XCTAssertEqual(try entries(subject).filter { $0.pending && $0.isTombstone }.count, 2)
        await subject.syncNow()
        XCTAssertTrue(remote.rows[owner]!.values.allSatisfy(\.isDeleted))
        let second = try controller(remote)
        try second.switchAccount(userID: owner)
        try second.setCloudConsent(true)
        await second.syncNow()
        XCTAssertEqual(try second.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 0)
        XCTAssertEqual(try second.container.mainContext.fetchCount(FetchDescriptor<PersistedWorkoutRoute>()), 0)
    }

    func testConflictPreservesUnsentEditUntilExplicitServerResolution() async throws {
        let remote = FakeHealthRemote(), owner = UUID(), id = UUID()
        let first = try controller(remote), second = try controller(remote)
        for subject in [first, second] { try subject.switchAccount(userID: owner); try subject.setCloudConsent(true) }
        try await SwiftDataUnifiedWorkoutStore(modelContext: first.container.mainContext).saveWorkout(workout(id: id))
        await first.syncNow(); await second.syncNow()
        try await SwiftDataUnifiedWorkoutStore(modelContext: second.container.mainContext).saveWorkout(workout(id: id, distance: 2200))
        try await SwiftDataUnifiedWorkoutStore(modelContext: first.container.mainContext).saveWorkout(workout(id: id, distance: 3300))
        await first.syncNow(); await second.syncNow()
        XCTAssertEqual(second.conflictCount, 1)
        let unsent = try await SwiftDataUnifiedWorkoutStore(modelContext: second.container.mainContext).fetchWorkout(id: id)
        XCTAssertEqual(unsent?.distanceMeters, 2200)
        XCTAssertEqual(try entries(second).first?.pending, true)
        await second.resolveConflicts(expectedUserID: owner, keepingLocal: false)
        let restored = try await SwiftDataUnifiedWorkoutStore(modelContext: second.container.mainContext).fetchWorkout(id: id)
        XCTAssertEqual(restored?.distanceMeters, 3300)
        XCTAssertEqual(second.conflictCount, 0)
    }

    func testLatestReceiptResponseCannotRebaseNewLocalEditAcrossAnotherDeviceVersion() async throws {
        let remote = FakeHealthRemote(), owner = UUID(), id = UUID()
        let subject = try controller(remote)
        try subject.switchAccount(userID: owner); try subject.setCloudConsent(true)
        let store = SwiftDataUnifiedWorkoutStore(modelContext: subject.container.mainContext)
        let original = workout(id: id, distance: 1500)
        try await store.saveWorkout(original)
        let originalMutation = try XCTUnwrap(entries(subject).first?.mutationID)
        let started = expectation(description: "retry RPC awaits receipt")
        remote.pausePush = true
        remote.onPush = { started.fulfill() }
        let task = Task { await subject.syncNow() }
        await fulfillment(of: [started], timeout: 2)
        // The first request committed after the pull snapshot. Another device
        // then wrote v2 before this repeated receipt's response was delivered.
        remote.install(original, owner: owner)
        remote.seedReceipt(originalMutation)
        remote.install(workout(id: id, distance: 3300), owner: owner)
        try await store.saveWorkout(workout(id: id, distance: 2200))
        remote.resumePush()
        await task.value
        XCTAssertEqual(subject.conflictCount, 1)
        XCTAssertEqual(try entries(subject).first?.pending, true)
        let kept = try await store.fetchWorkout(id: id)
        XCTAssertEqual(kept?.distanceMeters, 2200)
        XCTAssertEqual(remote.rows[owner]?.values.first?.version, 2)
    }

    func testConflictActionForOldAccountCannotChangeNewAccount() async throws {
        let remote = FakeHealthRemote(), a = UUID(), b = UUID(), id = UUID()
        let subject = try controller(remote)
        try subject.switchAccount(userID: b); try subject.setCloudConsent(true)
        try await SwiftDataUnifiedWorkoutStore(modelContext: subject.container.mainContext).saveWorkout(workout(id: id, distance: 1500))
        remote.install(workout(id: id, distance: 3300), owner: b)
        await subject.syncNow()
        XCTAssertEqual(subject.conflictCount, 1)
        await subject.resolveConflicts(expectedUserID: a, keepingLocal: false)
        XCTAssertEqual(subject.conflictCount, 1)
        let item = try await SwiftDataUnifiedWorkoutStore(modelContext: subject.container.mainContext).fetchWorkout(id: id)
        XCTAssertEqual(item?.distanceMeters, 1500)
    }

    func testShortByteLimitedPagesContinueUntilEmptyAndInvalidRowDoesNotBlockLaterRows() async throws {
        let remote = FakeHealthRemote(), owner = UUID()
        remote.pageSize = 1
        remote.install(workout(), owner: owner)
        remote.installInvalid(owner: owner)
        remote.install(workout(), owner: owner)
        let subject = try controller(remote)
        try subject.switchAccount(userID: owner); try subject.setCloudConsent(true)
        await subject.syncNow()
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 2)
        XCTAssertEqual(subject.invalidRecordCount, 1)
        XCTAssertNotNil(subject.errorMessage)
        XCTAssertEqual(remote.calls, 4)
    }

    func testLatePullCannotPopulateReplacementAccount() async throws {
        let remote = FakeHealthRemote(), a = UUID(), b = UUID()
        let subject = try controller(remote)
        try subject.switchAccount(userID: a); try subject.setCloudConsent(true)
        let item = workout()
        remote.install(item, owner: a)
        let started = expectation(description: "pull suspended")
        remote.onPull = { started.fulfill() }
        remote.pausePull = true
        let operation = Task { await subject.syncNow() }
        await fulfillment(of: [started], timeout: 2)
        try subject.switchAccount(userID: b)
        remote.resumePull()
        await operation.value
        XCTAssertEqual(subject.userID, b)
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 0)
        try subject.switchAccount(userID: a)
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 0)
    }

    func testErasureRemovesSensitiveOutboxPayloadAndConsent() async throws {
        let subject = try controller(), owner = UUID()
        try subject.switchAccount(userID: owner); try subject.setCloudConsent(true)
        try await SwiftDataUnifiedWorkoutStore(modelContext: subject.container.mainContext).saveWorkout(workout())
        try subject.eraseCurrentScopeData(expectedUserID: owner)
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<HealthCloudOutboxRecord>()), 0)
        XCTAssertFalse(subject.cloudConsentGranted)
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 0)
    }

    func testDeletedAccountRejectsLateImporterWritesAndAllowsEmptyCleanupRetry() async throws {
        let subject = try controller(), owner = UUID()
        try subject.switchAccount(userID: owner)
        let context = subject.container.mainContext
        let oldStore = SwiftDataUnifiedWorkoutStore(modelContext: context)
        try await oldStore.saveWorkout(workout())
        try subject.eraseCurrentScopeData(expectedUserID: owner, retireScope: true)
        do {
            try await oldStore.saveWorkout(workout())
            XCTFail("A deleted account's delayed import must fail closed")
        } catch {}
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 0)
        try await oldStore.deleteAllWorkouts()
        try subject.switchAccount(userID: UUID())
        try await SwiftDataUnifiedWorkoutStore(modelContext: subject.container.mainContext).saveWorkout(workout())
        XCTAssertEqual(try subject.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 1)
    }

    func testAccountCountsExcludeUnknownKindsAndPreservePayloads() throws {
        let subject = try controller()
        let a = UUID(), b = UUID()
        try subject.switchAccount(userID: a)
        let context = subject.container.mainContext
        let kinds = HealthCloudKind.allCases.map(\.rawValue) + ["_invalid", "_metadata", "futureKind"]
        var originals: [String: Data] = [:]
        for (index, kind) in kinds.enumerated() {
            let payload = Data([UInt8(index), 42, 99])
            let entry = HealthCloudOutboxRecord(kind: kind, recordKey: UUID().uuidString, payload: payload)
            entry.conflicted = kind == "route" || kind == "_invalid" || kind == "_metadata"
            originals[entry.key] = payload
            context.insert(entry)
        }
        let sent = HealthCloudOutboxRecord(kind: "workout", recordKey: UUID().uuidString, payload: Data([17]))
        sent.pending = false
        context.insert(sent)
        try context.save()
        try subject.switchAccount(userID: b)
        XCTAssertEqual(subject.pendingCount, 0)
        XCTAssertEqual(subject.conflictCount, 0)
        XCTAssertEqual(subject.invalidRecordCount, 0)
        try subject.switchAccount(userID: a)
        XCTAssertEqual(subject.pendingCount, HealthCloudKind.allCases.count)
        XCTAssertEqual(subject.conflictCount, 3)
        XCTAssertEqual(subject.invalidRecordCount, 1)
        let rows = try context.fetch(FetchDescriptor<HealthCloudOutboxRecord>())
        XCTAssertEqual(rows.count, kinds.count + 1)
        for row in rows where originals[row.key] != nil { XCTAssertEqual(row.payload, originals[row.key]) }
        XCTAssertFalse(context.hasChanges)
    }

    func testReopenedAccountCountsReflectSavedStatusWithoutMixingOwners() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("SOOM-Counts-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let a = UUID(), b = UUID()
        func open() throws -> HealthAccountStorageController {
            let schema = HealthAccountStorageController.schema
            let guest = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            return try HealthAccountStorageController(baseDirectory: base, guestContainer: guest, monitorNetwork: false, automaticallySync: false)
        }
        try autoreleasepool {
            let subject = try open()
            try subject.switchAccount(userID: a)
            let entry = HealthCloudOutboxRecord(kind: "route", recordKey: UUID().uuidString, payload: Data([1, 2, 3]))
            entry.pending = false; entry.conflicted = true
            subject.container.mainContext.insert(entry)
            try subject.container.mainContext.save()
            try subject.switchAccount(userID: b)
            subject.container.mainContext.insert(HealthCloudOutboxRecord(kind: "workout", recordKey: UUID().uuidString, payload: Data([4])))
            try subject.container.mainContext.save()
        }
        let reopened = try open()
        try reopened.switchAccount(userID: a)
        XCTAssertEqual(reopened.pendingCount, 0)
        XCTAssertEqual(reopened.conflictCount, 1)
        XCTAssertEqual(reopened.invalidRecordCount, 0)
        let aContext = reopened.container.mainContext
        try reopened.switchAccount(userID: b)
        XCTAssertEqual(reopened.pendingCount, 1)
        XCTAssertEqual(reopened.conflictCount, 0)
        XCTAssertEqual(reopened.invalidRecordCount, 0)
        XCTAssertEqual(try aContext.fetch(FetchDescriptor<HealthCloudOutboxRecord>()).first?.payload, Data([1, 2, 3]))
    }

    func testOutboxAndConsentSurviveDiskStoreReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HealthCloudSynthetic-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID(), item = workout()
        func open() throws -> HealthAccountStorageController {
            let schema = HealthAccountStorageController.schema
            let guest = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            return try HealthAccountStorageController(baseDirectory: directory, guestContainer: guest,
                monitorNetwork: false, automaticallySync: false)
        }
        var first: HealthAccountStorageController? = try open()
        try first!.switchAccount(userID: owner); try first!.setCloudConsent(true)
        try await SwiftDataUnifiedWorkoutStore(modelContext: first!.container.mainContext).saveWorkout(item)
        first = nil
        let reopened = try open()
        try reopened.switchAccount(userID: owner)
        XCTAssertTrue(reopened.cloudConsentGranted)
        XCTAssertEqual(try entries(reopened).filter(\.pending).count, 1)
        let stored = try await SwiftDataUnifiedWorkoutStore(modelContext: reopened.container.mainContext).fetchWorkout(id: item.id)
        XCTAssertEqual(stored, item)
    }
}

@MainActor
private final class FakeHealthRemote: HealthCloudRemote {
    var rows: [UUID: [String: HealthCloudRemoteRecord]] = [:]
    var calls = 0
    var failPullAfter: Int?
    var failPush = false
    var failAfterCommit = false
    var pageSize = 200
    var pausePush = false
    var onPush: (() -> Void)?
    private var pushContinuation: CheckedContinuation<Void, Never>?
    var pausePull = false
    var onPull: (() -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?
    private var revision: Int64 = 0
    private var receipts: Set<UUID> = []

    func install(_ workout: UnifiedWorkout, owner: UUID) {
        revision += 1
        let row = HealthCloudRemoteRecord(kind: "workout", recordKey: workout.id.uuidString.lowercased(),
            payloadJSON: String(data: try! HealthCloudPayload(workout: workout).encoded(), encoding: .utf8),
            isDeleted: false, version: (rows[owner]?["workout" + workout.id.uuidString.lowercased()]?.version ?? 0) + 1, revision: revision)
        rows[owner, default: [:]][row.kind + row.recordKey] = row
    }
    func seedReceipt(_ id: UUID) { receipts.insert(id) }
    func resumePush() { pausePush = false; pushContinuation?.resume(); pushContinuation = nil }
    func installInvalid(owner: UUID) {
        revision += 1
        let key = UUID().uuidString.lowercased()
        rows[owner, default: [:]]["workout" + key] = HealthCloudRemoteRecord(kind: "workout", recordKey: key,
            payloadJSON: "{\"formatVersion\":1}", isDeleted: false, version: 1, revision: revision)
    }
    func resumePull() { pausePull = false; continuation?.resume(); continuation = nil }
    func pull(after revision: Int64, expectedUserID: UUID) async throws -> [HealthCloudRemoteRecord] {
        calls += 1
        if let limit = failPullAfter, calls > limit { throw URLError(.notConnectedToInternet) }
        let result = (rows[expectedUserID] ?? [:]).values.filter { $0.revision > revision }.sorted { $0.revision < $1.revision }
        if pausePull { onPull?(); await withCheckedContinuation { continuation = $0 } }
        return Array(result.prefix(pageSize))
    }
    func push(_ mutation: HealthCloudMutation, expectedUserID: UUID) async throws -> HealthCloudRemoteRecord {
        calls += 1
        if failPush { throw URLError(.notConnectedToInternet) }
        if pausePush { onPush?(); await withCheckedContinuation { pushContinuation = $0 } }
        let key = mutation.kind + mutation.recordKey
        if var previous = rows[expectedUserID]?[key] {
            if receipts.contains(mutation.mutationID) { previous.accepted = true; return previous }
            if previous.version != mutation.baseVersion { previous.accepted = false; return previous }
        }
        revision += 1
        let value = HealthCloudRemoteRecord(kind: mutation.kind, recordKey: mutation.recordKey,
            payloadJSON: mutation.payload.flatMap { String(data: $0, encoding: .utf8) },
            isDeleted: mutation.isDeleted, version: mutation.baseVersion + 1, revision: revision, accepted: true)
        rows[expectedUserID, default: [:]][key] = value
        receipts.insert(mutation.mutationID)
        if failAfterCommit { failAfterCommit = false; throw URLError(.networkConnectionLost) }
        return value
    }
}
