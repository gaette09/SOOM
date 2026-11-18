import SwiftData
import XCTest
@testable import SOOM

@MainActor
final class ManualWorkoutEntryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func controller(remote: (any HealthCloudRemote)? = nil) throws -> HealthAccountStorageController {
        try HealthAccountStorageController(remote: remote, inMemory: true,
            monitorNetwork: false, automaticallySync: false)
    }

    private func saver(_ storage: HealthAccountStorageController) -> ManualWorkoutEntrySaver {
        ManualWorkoutEntrySaver(store: SwiftDataUnifiedWorkoutStore(modelContext: storage.container.mainContext),
            expectedScopeID: storage.scopeID, currentScopeID: { storage.scopeID })
    }

    func testCompletedWorkoutPreservesInputAndHasNoFabricatedSensorData() throws {
        var draft = ManualWorkoutDraft(now: now)
        draft.workoutType = .cycling
        draft.title = "  저녁 라이딩  "
        draft.description = "기기를 두고 나와 직접 입력"
        draft.distanceKilometers = "12.5"
        draft.locationName = " 서울 "
        let workout = try draft.makeWorkout(now: now)
        XCTAssertEqual(workout.id, draft.id)
        XCTAssertEqual(workout.source, .manual)
        XCTAssertEqual(workout.workoutType, .cycling)
        XCTAssertEqual(workout.userTitle, "저녁 라이딩")
        XCTAssertEqual(workout.userDescription, draft.description)
        XCTAssertEqual(workout.locationName, "서울")
        XCTAssertEqual(workout.startDate, now.addingTimeInterval(-1800))
        XCTAssertEqual(workout.endDate, now)
        XCTAssertEqual(workout.durationSeconds, 1800)
        XCTAssertEqual(workout.distanceMeters, 12_500)
        XCTAssertEqual(workout.averageSpeedMetersPerSecond ?? 0, 12_500 / 1800, accuracy: 0.0001)
        XCTAssertEqual(workout.dataQuality, .estimated)
        XCTAssertEqual(workout.routeMissingReason, .notApplicable)
        XCTAssertEqual(workout.recordVisibility, .privatePost)
        XCTAssertNil(workout.externalId)
        XCTAssertNil(workout.activeEnergyKcal)
        XCTAssertNil(workout.averageHeartRate)
        XCTAssertNil(workout.maxHeartRate)
        XCTAssertNil(workout.elevationGainMeters)
        XCTAssertNil(workout.averagePowerWatts)
        XCTAssertNil(workout.averageCadence)
        XCTAssertNil(workout.deviceName)
    }

    func testTimeOnlyWorkoutAndEverySupportedSportCanBeEntered() throws {
        for sport in ManualWorkoutDraft.workoutTypes {
            var draft = ManualWorkoutDraft(now: now)
            draft.workoutType = sport
            let workout = try draft.makeWorkout(now: now)
            XCTAssertEqual(workout.userTitle, "\(sport.shareDisplayName) 기록")
            XCTAssertNil(workout.distanceMeters)
            XCTAssertNil(workout.averageSpeedMetersPerSecond)
            XCTAssertNil(workout.locationName)
        }
    }

    func testSecondsAndLocaleDecimalArePreserved() throws {
        var draft = ManualWorkoutDraft(now: now)
        draft.hours = ""
        draft.minutes = "1"
        draft.seconds = "25"
        draft.distanceKilometers = "0,25"
        let workout = try draft.makeWorkout(now: now, locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(workout.durationSeconds, 85)
        XCTAssertEqual(workout.distanceMeters, 250)
    }

    func testInvalidDurationsAndUnfinishedWorkoutsAreRejected() throws {
        for value in ["-1", "60", "1.5", "NaN", "999999999999999999999"] {
            var draft = ManualWorkoutDraft(now: now)
            draft.minutes = value
            XCTAssertThrowsError(try draft.makeWorkout(now: now), value)
        }
        var draft = ManualWorkoutDraft(now: now)
        draft.minutes = "0"
        XCTAssertThrowsError(try draft.makeWorkout(now: now))
        draft.minutes = "30"
        draft.startedAt = now
        XCTAssertThrowsError(try draft.makeWorkout(now: now))
        draft.startedAt = Date(timeIntervalSince1970: .infinity)
        XCTAssertThrowsError(try draft.makeWorkout(now: now))
        draft.startedAt = Date(timeIntervalSince1970: -1)
        XCTAssertThrowsError(try draft.makeWorkout(now: now))
    }

    func testInvalidDistanceAndOversizedTextAreRejected() {
        for value in ["0", "0.0001", "0.000000000000000000001", "-5", "NaN", "inf", "1e308", "10 000", "10001", "1.2.3", "1,000"] {
            var draft = ManualWorkoutDraft(now: now)
            draft.distanceKilometers = value
            XCTAssertThrowsError(try draft.makeWorkout(now: now, locale: Locale(identifier: "ko_KR")), value)
        }
        var draft = ManualWorkoutDraft(now: now)
        draft.title = String(repeating: "가", count: 81)
        XCTAssertThrowsError(try draft.makeWorkout(now: now))
        draft.title = ""
        draft.description = String(repeating: "나", count: 101)
        XCTAssertThrowsError(try draft.makeWorkout(now: now))
        draft.description = ""
        draft.locationName = String(repeating: "다", count: 101)
        XCTAssertThrowsError(try draft.makeWorkout(now: now))
    }

    func testGuestSavePersistsWithoutCloudOutboxOrInventedRoute() async throws {
        let storage = try controller()
        let saved = try await saver(storage).save(ManualWorkoutDraft(now: now), now: now)
        let reopened = ModelContext(storage.container)
        let restored = try await SwiftDataUnifiedWorkoutStore(modelContext: reopened).fetchWorkout(id: saved.id)
        XCTAssertEqual(restored, saved)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<HealthCloudOutboxRecord>()), 0)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<PersistedWorkoutRoute>()), 0)
    }

    func testSignedInSaveUsesCloudJournalAndRetryDoesNotDuplicate() async throws {
        let storage = try controller()
        try storage.switchAccount(userID: UUID())
        var draft = ManualWorkoutDraft(now: now)
        draft.locationName = "부산"
        let save = saver(storage)
        let first = try await save.save(draft, now: now)
        let second = try await save.save(draft, now: now)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try storage.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 1)
        let entries = try storage.container.mainContext.fetch(FetchDescriptor<HealthCloudOutboxRecord>())
            .filter { $0.kind == HealthCloudKind.workout.rawValue }
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(try XCTUnwrap(entries.first).pending)
        let payload = try HealthCloudPayload.decode(XCTUnwrap(entries.first?.payload))
        XCTAssertEqual(payload.workout, first)
    }

    func testAccountChangeBeforeSaveCannotWriteToEitherAccount() async throws {
        let storage = try controller()
        let firstOwner = UUID()
        try storage.switchAccount(userID: firstOwner)
        let save = saver(storage)
        try storage.switchAccount(userID: UUID())
        do {
            _ = try await save.save(ManualWorkoutDraft(now: now), now: now)
            XCTFail("A form from another account must be rejected")
        } catch {
            XCTAssertEqual(error as? ManualWorkoutEntryError, .accountChanged)
        }
        XCTAssertEqual(try storage.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 0)
        try storage.switchAccount(userID: firstOwner)
        XCTAssertEqual(try storage.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 0)
    }

    func testRetiredAccountContextRejectsAndRollsBackManualSave() async throws {
        let storage = try controller()
        try storage.switchAccount(userID: UUID())
        let save = saver(storage)
        HealthCloudJournal.retire(storage.container)
        do {
            _ = try await save.save(ManualWorkoutDraft(now: now), now: now)
            XCTFail("Deleted account scope must not accept new workouts")
        } catch {}
        XCTAssertEqual(try storage.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 0)
    }

    func testManualWorkoutWaitsForConsentAndRestoresOnSecondAccountDevice() async throws {
        let remote = ManualWorkoutTestRemote()
        let owner = UUID()
        let first = try controller(remote: remote)
        try first.switchAccount(userID: owner)
        var draft = ManualWorkoutDraft(now: now)
        draft.title = "수동 운동"
        draft.description = "클라우드 복원 확인"
        draft.distanceKilometers = "5"
        draft.locationName = "수지구"
        let saved = try await saver(first).save(draft, now: now)
        await first.syncNow()
        XCTAssertEqual(remote.calls, 0)
        try first.setCloudConsent(true)
        remote.failPush = true
        await first.syncNow()
        XCTAssertNotNil(first.errorMessage)
        XCTAssertTrue(remote.rows.isEmpty)
        remote.failPush = false
        await first.syncNow()
        XCTAssertEqual(remote.rows.count, 1)
        let second = try controller(remote: remote)
        try second.switchAccount(userID: owner)
        try second.setCloudConsent(true)
        await second.syncNow()
        let restored = try await SwiftDataUnifiedWorkoutStore(modelContext: second.container.mainContext).fetchWorkout(id: saved.id)
        XCTAssertEqual(restored, saved)
        XCTAssertEqual(try second.container.mainContext.fetchCount(FetchDescriptor<PersistedWorkoutRoute>()), 0)
    }

    func testPrivateFeedDraftRetryPreservesWorkoutIdentityAndMetadata() async throws {
        let drafts = ManualWorkoutTestDraftStore()
        let coordinator = ManualWorkoutFeedDraftCoordinator(store: drafts,
            expectedScopeID: "account-a", currentScopeID: { "account-a" })
        var draft = ManualWorkoutDraft(now: now)
        draft.locationName = "서울"
        let workout = try draft.makeWorkout(now: now)
        try await coordinator.savePreview(for: workout)
        try await coordinator.savePreview(for: workout)
        let saved = try await drafts.fetchDrafts()
        XCTAssertEqual(saved.count, 1)
        let preview = try XCTUnwrap(saved.first)
        XCTAssertEqual(preview.id, workout.id)
        XCTAssertEqual(preview.sourceWorkoutId, workout.id)
        XCTAssertEqual(preview.visibility.shareableVisibility, .privateOnly)
        XCTAssertEqual(preview.activityDate, workout.startDate)
        XCTAssertEqual(preview.deviceName, "직접 입력")
        XCTAssertEqual(preview.locationName, "서울")
        XCTAssertEqual(preview.routePreviewPayload?.routeExists, false)
        XCTAssertTrue(preview.makeFeedItem().isLocalDraft)
    }

    func testRemotePhotoPostCleanupOnlyRemovesMatchingWorkoutDraft() async throws {
        let drafts = ManualWorkoutTestDraftStore()
        let coordinator = ManualWorkoutFeedDraftCoordinator(store: drafts,
            expectedScopeID: "account-a", currentScopeID: { "account-a" })
        let first = try ManualWorkoutDraft(now: now).makeWorkout(now: now)
        let second = try ManualWorkoutDraft(now: now).makeWorkout(now: now)
        try await coordinator.savePreview(for: first)
        try await coordinator.savePreview(for: second)
        try await coordinator.removePreviewAfterConfirmedRemotePost(workoutID: first.id)
        let saved = try await drafts.fetchDrafts()
        XCTAssertEqual(saved.map(\.sourceWorkoutId), [second.id])
    }

    func testAccountChangeDoesNotWriteOrDeletePrivateDrafts() async throws {
        let drafts = ManualWorkoutTestDraftStore()
        var scope = "account-a"
        let coordinator = ManualWorkoutFeedDraftCoordinator(store: drafts,
            expectedScopeID: scope, currentScopeID: { scope })
        let workout = try ManualWorkoutDraft(now: now).makeWorkout(now: now)
        try await coordinator.savePreview(for: workout)
        scope = "account-b"
        do {
            try await coordinator.savePreview(for: workout)
            XCTFail("Changed scope must reject draft writes")
        } catch { XCTAssertEqual(error as? ManualWorkoutEntryError, .accountChanged) }
        do {
            try await coordinator.removePreviewAfterConfirmedRemotePost(workoutID: workout.id)
            XCTFail("Changed scope must reject draft deletion")
        } catch { XCTAssertEqual(error as? ManualWorkoutEntryError, .accountChanged) }
        let saved = try await drafts.fetchDrafts()
        XCTAssertEqual(saved.count, 1)
    }
}

private actor ManualWorkoutTestDraftStore: FeedShareDraftStoreProtocol {
    private var drafts: [FeedShareDraft] = []
    func saveDraft(_ draft: FeedShareDraft) async throws {
        drafts.removeAll { $0.id == draft.id || $0.sourceWorkoutId == draft.sourceWorkoutId }
        drafts.append(draft)
    }
    func fetchDrafts() async throws -> [FeedShareDraft] { drafts }
    func deleteDraft(id: UUID) async throws { drafts.removeAll { $0.id == id } }
    func deleteAllDrafts() async throws { drafts = [] }
}

@MainActor
private final class ManualWorkoutTestRemote: HealthCloudRemote {
    var rows: [HealthCloudRemoteRecord] = []
    var calls = 0
    var failPush = false
    private var owner: UUID?
    func pull(after revision: Int64, expectedUserID: UUID) async throws -> [HealthCloudRemoteRecord] {
        calls += 1
        guard owner == nil || owner == expectedUserID else { return [] }
        return rows.filter { $0.revision > revision }
    }
    func push(_ mutation: HealthCloudMutation, expectedUserID: UUID) async throws -> HealthCloudRemoteRecord {
        calls += 1
        if failPush { throw URLError(.notConnectedToInternet) }
        owner = expectedUserID
        let result = HealthCloudRemoteRecord(kind: mutation.kind, recordKey: mutation.recordKey,
            payloadJSON: mutation.payload.flatMap { String(data: $0, encoding: .utf8) },
            isDeleted: mutation.isDeleted, version: mutation.baseVersion + 1,
            revision: Int64(rows.count + 1), accepted: true)
        rows.append(result)
        return result
    }
}
