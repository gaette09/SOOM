import SwiftData
import Supabase
import SwiftUI
import UIKit
import XCTest
@testable import SOOM

@MainActor
final class WorkoutRecordManagementTests: XCTestCase {
    func testDescriptionPasteLimitsVisibleAndBoundValuesByGrapheme() {
        var value = ""
        let editor = WorkoutBoundedTextEditor(text: Binding(get: { value }, set: { value = $0 }),
            limit: 100, minimumLines: 3, identifier: "test")
        let coordinator = editor.makeCoordinator()
        let view = UITextView()
        view.text = ""
        let accepted = coordinator.textView(view, shouldChangeTextIn: NSRange(location: 0, length: 0),
            replacementText: String(repeating: "👨‍👩‍👧‍👦", count: 110))
        XCTAssertFalse(accepted)
        XCTAssertEqual(view.text.count, 100)
        XCTAssertEqual(value, view.text)
        XCTAssertEqual(view.selectedRange.location, value.utf16.count)
    }

    func testOverLimitInsertionDoesNotEraseExistingSuffix() {
        var value = String(repeating: "a", count: 99) + "Z"
        let editor = WorkoutBoundedTextEditor(text: Binding(get: { value }, set: { value = $0 }),
            limit: 100, minimumLines: 3, identifier: "test")
        let view = UITextView()
        view.text = value
        XCTAssertFalse(editor.makeCoordinator().textView(view, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: "NEW"))
        XCTAssertEqual(view.text, String(repeating: "a", count: 99) + "Z")
        XCTAssertEqual(value, view.text)
    }

    func testReplacingSelectedTextUsesOnlyAvailableCharacterBudget() {
        var value = String(repeating: "a", count: 99) + "Z"
        let editor = WorkoutBoundedTextEditor(text: Binding(get: { value }, set: { value = $0 }),
            limit: 100, minimumLines: 3, identifier: "test")
        let view = UITextView()
        view.text = value
        XCTAssertFalse(editor.makeCoordinator().textView(view, shouldChangeTextIn: NSRange(location: 0, length: 2), replacementText: "NEW"))
        XCTAssertTrue(value.hasPrefix("NE"))
        XCTAssertTrue(value.hasSuffix("Z"))
        XCTAssertEqual(value.count, 100)
        XCTAssertEqual(value, view.text)
    }

    func testLegacyWorkoutCloudPayloadDecodesMissingMetadataAndKeepsUnknownVisibility() throws {
        let original = workout()
        let payload = HealthCloudPayload(workout: original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload.encoded()) as? [String: Any])
        var item = try XCTUnwrap(json["workout"] as? [String: Any])
        for key in ["userTitle", "userDescription", "sharingVisibilityRaw", "isBookmarked"] { item.removeValue(forKey: key) }
        json["workout"] = item
        let decoded = try XCTUnwrap(HealthCloudPayload.decode(JSONSerialization.data(withJSONObject: json)).workout)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertNil(decoded.userTitle)
        XCTAssertNil(decoded.userDescription)
        XCTAssertNil(decoded.recordVisibility)
        XCTAssertNil(decoded.isBookmarked)
        XCTAssertFalse(decoded.displayTitle.isEmpty)
        let roundTrip = try XCTUnwrap(HealthCloudPayload.decode(HealthCloudPayload(workout: decoded).encoded()).workout)
        XCTAssertEqual(roundTrip, decoded)
    }

    func testMetadataRoundTripsThroughPayloadAndNewAndExistingCloudRestore() async throws {
        var value = workout()
        value.userTitle = "저녁 러닝"
        value.userDescription = "강변에서 가볍게 달렸어요 👟"
        value.sharingVisibilityRaw = FeedPostVisibility.privatePost.rawValue
        value.isBookmarked = true
        let data = try HealthCloudPayload(workout: value).encoded()
        let decoded = try XCTUnwrap(HealthCloudPayload.decode(data).workout)
        XCTAssertEqual(decoded, value)
        let controller = try storage()
        try controller.switchAccount(userID: UUID())
        let context = controller.container.mainContext
        try HealthCloudJournal.apply(kind: "workout", key: value.id.uuidString.lowercased(), data: data, deleted: false, context: context)
        try context.save()
        let store = SwiftDataUnifiedWorkoutStore(modelContext: context)
        let loadedValue1 = try await store.fetchWorkout(id: value.id)
        let restored = try XCTUnwrap(loadedValue1)
        assertMetadata(restored, equals: value)
        value.userTitle = "다른 기기에서 수정한 제목"
        value.userDescription = nil
        value.sharingVisibilityRaw = FeedPostVisibility.publicPost.rawValue
        value.isBookmarked = false
        try HealthCloudJournal.apply(kind: "workout", key: value.id.uuidString.lowercased(), data: HealthCloudPayload(workout: value).encoded(), deleted: false, context: context)
        try context.save()
        let loadedValue2 = try await store.fetchWorkout(id: value.id)
        let updated = try XCTUnwrap(loadedValue2)
        assertMetadata(updated, equals: value)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 1)
    }

    func testImportUpsertKeepsUserMetadataAndStableIdentity() async throws {
        let controller = try storage()
        let store = SwiftDataUnifiedWorkoutStore(modelContext: controller.container.mainContext)
        var original = workout(externalID: "synthetic-import")
        original.userTitle = "내가 정한 제목"; original.userDescription = "설명"
        original.sharingVisibilityRaw = FeedPostVisibility.privatePost.rawValue; original.isBookmarked = true
        try await store.saveWorkout(original)
        let reimport = workout(externalID: "synthetic-import", distance: 2300)
        try await store.saveWorkout(reimport)
        let loadedValue3 = try await store.fetchByExternalId("synthetic-import", source: .soomLocal)
        let stored = try XCTUnwrap(loadedValue3)
        XCTAssertEqual(stored.id, original.id)
        XCTAssertEqual(stored.distanceMeters, 2300)
        assertMetadata(stored, equals: original)
    }

    func testCompanionAndRouteHelpersPreserveEditedMetadata() {
        var original = workout()
        original.userTitle = "내 제목"; original.userDescription = "내 설명"
        original.sharingVisibilityRaw = FeedPostVisibility.publicPost.rawValue; original.isBookmarked = true
        assertMetadata(original.withCompanionNames(["동행"], updatedAt: original.updatedAt), equals: original)
        assertMetadata(original.withRouteMissingReason(.routeFetchFailed, updatedAt: original.updatedAt), equals: original)
    }

    func testDescriptionLimitCountsUserPerceivedUnicodeCharactersIncludingSpaces() throws {
        let emoji = "👨‍👩‍👧‍👦"
        XCTAssertEqual(emoji.count, 1)
        try WorkoutRecordEditPolicy.validate(title: "한글 운동", description: String(repeating: emoji, count: 99) + " ")
        XCTAssertThrowsError(try WorkoutRecordEditPolicy.validate(title: "운동", description: String(repeating: emoji, count: 100) + " "))
        XCTAssertThrowsError(try WorkoutRecordEditPolicy.validate(title: "   ", description: ""))
        XCTAssertThrowsError(try WorkoutRecordEditPolicy.validate(title: String(repeating: "가", count: 81), description: ""))
        try WorkoutRecordEditPolicy.validate(title: String(repeating: "가", count: 80), description: "")
    }

    func testFailedRemoteEditLeavesWorkoutDraftAndOutboxUnchanged() async throws {
        let fixture = try await fixture()
        let before = Set(try entries(fixture.storage).map(\.mutationID))
        let draft = makeDraft(fixture.workout)
        try await fixture.drafts.saveDraft(draft)
        fixture.remote.failure = URLError(.notConnectedToInternet)
        let saved = await fixture.model.edit(title: "저장되지 않을 제목", description: "새 설명")
        XCTAssertFalse(saved)
        XCTAssertNotNil(fixture.model.errorMessage)
        XCTAssertNil(fixture.model.notice)
        let loadedValue4 = try await fixture.store.fetchWorkout(id: fixture.workout.id)
        XCTAssertEqual(loadedValue4, fixture.workout)
        let loadedValue5 = try await fixture.drafts.fetchDrafts()
        XCTAssertEqual(loadedValue5, [draft])
        XCTAssertEqual(Set(try entries(fixture.storage).map(\.mutationID)), before)
    }

    func testSuccessfulEditUpdatesLocalDraftAndOutboxWithoutPublishingNewPost() async throws {
        let fixture = try await fixture()
        try await fixture.drafts.saveDraft(makeDraft(fixture.workout))
        let saved = await fixture.model.edit(title: "  변경한 제목  ", description: "100자 이내 설명", location: "  김포시, 경기도  ")
        XCTAssertTrue(saved)
        let loadedValue6 = try await fixture.store.fetchWorkout(id: fixture.workout.id)
        let stored = try XCTUnwrap(loadedValue6)
        XCTAssertEqual(stored.userTitle, "변경한 제목")
        XCTAssertEqual(stored.userDescription, "100자 이내 설명")
        XCTAssertEqual(stored.locationName, "김포시, 경기도")
        XCTAssertEqual(fixture.remote.updates.count, 1)
        XCTAssertEqual(fixture.remote.updates[0].workout.locationName, "김포시, 경기도")
        XCTAssertFalse(fixture.remote.updates[0].createIfMissing)
        XCTAssertNil(fixture.remote.updates[0].visibility)
        let loadedValue7 = try await fixture.drafts.fetchDrafts().first
        let draft = try XCTUnwrap(loadedValue7)
        XCTAssertEqual(draft.title, "변경한 제목")
        XCTAssertEqual(draft.body, "100자 이내 설명")
        XCTAssertEqual(draft.locationName, "김포시, 경기도")
        let outbox = try XCTUnwrap(entries(fixture.storage).first { $0.kind == "workout" })
        let queued = try XCTUnwrap(HealthCloudPayload.decode(XCTUnwrap(outbox.payload)).workout)
        assertMetadata(queued, equals: stored)
        XCTAssertNotNil(fixture.model.notice)
    }

    func testInvalidEditDoesNotReachRemoteOrChangeLocalRecord() async throws {
        let fixture = try await fixture()
        let saved = await fixture.model.edit(title: "제목", description: String(repeating: "가", count: 101))
        XCTAssertFalse(saved)
        XCTAssertTrue(fixture.remote.updates.isEmpty)
        let loadedValue8 = try await fixture.store.fetchWorkout(id: fixture.workout.id)
        XCTAssertEqual(loadedValue8, fixture.workout)
    }

    func testVisibilityIsNotAppliedLocallyUntilRemoteAcknowledgesAndRetryCanSucceed() async throws {
        let fixture = try await fixture()
        fixture.remote.failure = URLError(.notConnectedToInternet)
        await fixture.model.setVisibility(.publicPost)
        XCTAssertNil(fixture.model.workout.recordVisibility)
        let loadedValue9 = try await fixture.store.fetchWorkout(id: fixture.workout.id)?.recordVisibility
        XCTAssertNil(loadedValue9)
        XCTAssertNil(fixture.model.notice)
        fixture.remote.failure = nil
        await fixture.model.setVisibility(.publicPost)
        let loadedValue10 = try await fixture.store.fetchWorkout(id: fixture.workout.id)?.recordVisibility
        XCTAssertEqual(loadedValue10, .publicPost)
        XCTAssertTrue(fixture.remote.updates.last?.createIfMissing == true)
        await fixture.model.setVisibility(.privatePost)
        let loadedValue11 = try await fixture.store.fetchWorkout(id: fixture.workout.id)?.recordVisibility
        XCTAssertEqual(loadedValue11, .privatePost)
        XCTAssertFalse(fixture.remote.updates.last?.createIfMissing == true)
    }

    func testNewImportPendingPublishesOnceAndDoesNotRepublishAfterPrivateChoice() async throws {
        let fixture = try await fixture()
        let context = fixture.storage.container.mainContext
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<UnifiedWorkoutRecord>()).first)
        record.sharingVisibilityRaw = ImportedWorkoutPublication.pendingVisibility
        try context.save()
        let publisher = ImportedWorkoutPublication(context: context, storage: fixture.storage, remote: fixture.remote, privacy: PublicationPrivacyStub(owner:fixture.storage.userID))
        let first = await publisher.publish(ids: [record.id])
        if ProfileOnlyPrivacyReleaseGate.productionReady {
            XCTAssertEqual(first.published,0);XCTAssertEqual(first.failed,0)
            XCTAssertTrue(fixture.remote.updates.isEmpty)
            XCTAssertEqual(record.sharingVisibilityRaw,ImportedWorkoutPublication.pendingVisibility)
            return // v2 canonical worker, never the legacy feed publisher, owns this marker.
        }
        XCTAssertEqual(first.published, 1)
        XCTAssertEqual(first.failed, 0)
        XCTAssertEqual(fixture.remote.updates.last?.visibility, .publicPost)
        XCTAssertTrue(fixture.remote.updates.last?.createIfMissing == true)
        await fixture.model.setVisibility(.privatePost)
        let calls = fixture.remote.updates.count
        let second = await publisher.publish(ids: [record.id])
        XCTAssertEqual(second.published, 0)
        XCTAssertEqual(fixture.remote.updates.count, calls)
        XCTAssertEqual(record.sharingVisibilityRaw, FeedPostVisibility.privatePost.rawValue)
    }

    func testCrossSourceCopyDoesNotCreateSecondFeedPost() async throws {
        let fixture = try await fixture()
        let context = fixture.storage.container.mainContext
        let original = fixture.workout
        var imported = UnifiedWorkout(
            id: UUID(), externalId: "health-copy", source: .appleHealthKit,
            workoutType: original.workoutType, startDate: original.startDate,
            endDate: original.endDate, durationSeconds: original.durationSeconds,
            distanceMeters: original.distanceMeters, activeEnergyKcal: nil,
            averageHeartRate: nil, maxHeartRate: nil, averageSpeedMetersPerSecond: nil,
            elevationGainMeters: nil, dataQuality: .partial,
            createdAt: original.createdAt, updatedAt: original.updatedAt
        )
        imported.sharingVisibilityRaw = ImportedWorkoutPublication.pendingVisibility
        try await fixture.store.saveWorkout(imported)

        let result = await ImportedWorkoutPublication(context: context, storage: fixture.storage,
            remote: fixture.remote, privacy: PublicationPrivacyStub(owner:fixture.storage.userID)).publish(ids: [imported.id])

        XCTAssertEqual(result.published, 0)
        XCTAssertEqual(result.leftPrivate, ProfileOnlyPrivacyReleaseGate.productionReady ? 0 : 1)
        XCTAssertTrue(fixture.remote.updates.isEmpty)
        let savedCopy = try await fixture.store.fetchWorkout(id: imported.id)
        XCTAssertEqual(savedCopy?.recordVisibility, ProfileOnlyPrivacyReleaseGate.productionReady ? nil : FeedPostVisibility.privatePost)
        if ProfileOnlyPrivacyReleaseGate.productionReady {
            XCTAssertEqual(savedCopy?.sharingVisibilityRaw,ImportedWorkoutPublication.pendingVisibility)
        }
    }

    func testFailedAutoPublicationRemainsPendingForRetry() async throws {
        let fixture = try await fixture()
        let context = fixture.storage.container.mainContext
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<UnifiedWorkoutRecord>()).first)
        record.sharingVisibilityRaw = ImportedWorkoutPublication.pendingVisibility
        try context.save()
        let publisher = ImportedWorkoutPublication(context: context, storage: fixture.storage, remote: fixture.remote, privacy: PublicationPrivacyStub(owner:fixture.storage.userID))
        fixture.remote.failure = URLError(.notConnectedToInternet)
        let failed = await publisher.publish()
        if ProfileOnlyPrivacyReleaseGate.productionReady {
            XCTAssertEqual(failed.failed,0);XCTAssertTrue(fixture.remote.updates.isEmpty)
            fixture.remote.failure=nil
            let repeated=await publisher.publish()
            XCTAssertEqual(repeated.published,0);XCTAssertTrue(fixture.remote.updates.isEmpty)
            XCTAssertEqual(record.sharingVisibilityRaw,ImportedWorkoutPublication.pendingVisibility)
            return
        }
        XCTAssertEqual(failed.failed, 1)
        XCTAssertEqual(record.sharingVisibilityRaw, ImportedWorkoutPublication.pendingVisibility)
        fixture.remote.failure = nil
        let retried = await publisher.publish()
        XCTAssertEqual(retried.published, 1)
        XCTAssertEqual(record.sharingVisibilityRaw, FeedPostVisibility.publicPost.rawValue)
    }

    func testAllPrivateDisablesFutureAutoPublicationAndConvertsPendingToPrivate() async throws {
        let fixture = try await fixture()
        let context = fixture.storage.container.mainContext
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<UnifiedWorkoutRecord>()).first)
        record.sharingVisibilityRaw = ImportedWorkoutPublication.pendingVisibility
        try context.save()
        let publisher = ImportedWorkoutPublication(context: context, storage: fixture.storage, remote: fixture.remote, privacy: PublicationPrivacyStub(owner:fixture.storage.userID))
        let key = "SOOM.autoPublishImportedWorkouts.\(fixture.storage.scopeID)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        XCTAssertTrue(fixture.storage.autoPublishImportedWorkouts)
        let hidden = await publisher.makeAllPrivate()
        XCTAssertEqual(hidden.failed, 0)
        XCTAssertEqual(hidden.leftPrivate, 1)
        XCTAssertEqual(fixture.remote.bulkPrivateOwners, [fixture.storage.userID!])
        XCTAssertFalse(fixture.storage.autoPublishImportedWorkouts)
        XCTAssertEqual(record.sharingVisibilityRaw, FeedPostVisibility.privatePost.rawValue)
        let later = await publisher.publish()
        XCTAssertEqual(later.published, 0)
    }

    func testAllPrivateServerFailureLeavesRecordsPendingAndReportsFailure() async throws {
        let fixture = try await fixture()
        let context = fixture.storage.container.mainContext
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<UnifiedWorkoutRecord>()).first)
        record.sharingVisibilityRaw = ImportedWorkoutPublication.pendingVisibility
        try context.save()
        fixture.remote.failure = URLError(.notConnectedToInternet)
        let key = "SOOM.autoPublishImportedWorkouts.\(fixture.storage.scopeID)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let result = await ImportedWorkoutPublication(context: context, storage: fixture.storage,
            remote: fixture.remote, privacy: PublicationPrivacyStub(owner:fixture.storage.userID)).makeAllPrivate()
        XCTAssertTrue(result.serverFailed)
        XCTAssertGreaterThan(result.failed, 0)
        XCTAssertEqual(record.sharingVisibilityRaw, ImportedWorkoutPublication.pendingVisibility)
        XCTAssertFalse(fixture.storage.autoPublishImportedWorkouts)
    }

    func testGuestCannotPublishButCanEditAndBookmarkWithoutRemoteCalls() async throws {
        let fixture = try await fixture(owner: nil)
        await fixture.model.setVisibility(.publicPost)
        XCTAssertNotNil(fixture.model.errorMessage)
        XCTAssertTrue(fixture.remote.updates.isEmpty)
        let saved = await fixture.model.edit(title: "기기 제목", description: "")
        XCTAssertTrue(saved)
        await fixture.model.toggleBookmark()
        XCTAssertTrue(fixture.model.isBookmarked)
        XCTAssertTrue(fixture.remote.updates.isEmpty)
        XCTAssertTrue(try entries(fixture.storage).isEmpty)
    }

    func testBookmarkSurvivesDiskStoreReopeningAndCanBeRemoved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WorkoutBookmarkTests-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID(), item = workout()
        do {
            let controller = try diskStorage(directory)
            try controller.switchAccount(userID: owner)
            let store = SwiftDataUnifiedWorkoutStore(modelContext: controller.container.mainContext)
            try await store.saveWorkout(item)
            let model = WorkoutRecordManagement(workout: item)
            model.configure(context: controller.container.mainContext, storage: controller, remote: ManagementRemoteStub(), drafts: ManagementDraftStore())
            await model.toggleBookmark()
            XCTAssertTrue(model.isBookmarked)
        }
        let reopened = try diskStorage(directory)
        try reopened.switchAccount(userID: owner)
        let store = SwiftDataUnifiedWorkoutStore(modelContext: reopened.container.mainContext)
        let loadedValue12 = try await store.fetchWorkout(id: item.id)
        let persisted = try XCTUnwrap(loadedValue12)
        XCTAssertEqual(persisted.isBookmarked, true)
        let model = WorkoutRecordManagement(workout: persisted)
        model.configure(context: reopened.container.mainContext, storage: reopened, remote: ManagementRemoteStub(), drafts: ManagementDraftStore())
        await model.toggleBookmark()
        let loadedValue13 = try await store.fetchWorkout(id: item.id)?.isBookmarked
        XCTAssertEqual(loadedValue13, false)
    }

    func testRemoteDeleteFailureKeepsWorkoutRouteDraftAndPendingMutations() async throws {
        let fixture = try await fixture()
        let routeStore = SwiftDataWorkoutRoutePersistenceStore(modelContext: fixture.storage.container.mainContext)
        try await routeStore.saveRoute(route(fixture.workout))
        let draft = makeDraft(fixture.workout)
        try await fixture.drafts.saveDraft(draft)
        let before = Set(try entries(fixture.storage).map(\.mutationID))
        fixture.remote.failure = URLError(.notConnectedToInternet)
        await fixture.model.delete()
        XCTAssertFalse(fixture.model.isDeleted)
        let loadedValue14 = try await fixture.store.fetchWorkout(id: fixture.workout.id)
        XCTAssertNotNil(loadedValue14)
        let loadedValue15 = try await routeStore.fetchRoute(workoutId: fixture.workout.id)
        XCTAssertNotNil(loadedValue15)
        let loadedValue16 = try await fixture.drafts.fetchDrafts()
        XCTAssertEqual(loadedValue16, [draft])
        XCTAssertEqual(Set(try entries(fixture.storage).map(\.mutationID)), before)
    }

    func testSuccessfulDeleteRemovesWorkoutRouteAndMatchingDraftAndCreatesBothTombstones() async throws {
        let fixture = try await fixture()
        let routeStore = SwiftDataWorkoutRoutePersistenceStore(modelContext: fixture.storage.container.mainContext)
        try await routeStore.saveRoute(route(fixture.workout))
        let other = makeDraft(workout())
        try await fixture.drafts.saveDraft(makeDraft(fixture.workout))
        try await fixture.drafts.saveDraft(other)
        await fixture.model.delete()
        XCTAssertTrue(fixture.model.isDeleted)
        let loadedValue17 = try await fixture.store.fetchWorkout(id: fixture.workout.id)
        XCTAssertNil(loadedValue17)
        let loadedValue18 = try await routeStore.fetchRoute(workoutId: fixture.workout.id)
        XCTAssertNil(loadedValue18)
        let loadedValue19 = try await fixture.drafts.fetchDrafts()
        XCTAssertEqual(loadedValue19, [other])
        let tombstones = try entries(fixture.storage)
        XCTAssertEqual(Set(tombstones.map(\.kind)), Set(["workout", "route"]))
        XCTAssertTrue(tombstones.allSatisfy { $0.isTombstone && $0.pending && $0.payload == nil })
        XCTAssertEqual(fixture.remote.deletedIDs, [fixture.workout.id])
    }

    func testAccountSwitchWhileRemoteEditWaitsCannotChangeEitherScopeLocally() async throws {
        let fixture = try await fixture()
        let started = expectation(description: "remote edit started")
        var continuation: CheckedContinuation<Void, Never>?
        fixture.remote.onUpdate = { await withCheckedContinuation { continuation = $0; started.fulfill() } }
        let task = Task { await fixture.model.edit(title: "A의 늦은 수정", description: "설명") }
        await fulfillment(of: [started], timeout: 2)
        try fixture.storage.switchAccount(userID: UUID())
        let bContext = fixture.storage.container.mainContext
        let bItem = workout()
        let bStore = SwiftDataUnifiedWorkoutStore(modelContext: bContext)
        try await bStore.saveWorkout(bItem)
        continuation?.resume()
        let saved = await task.value
        XCTAssertFalse(saved)
        let loadedValue20 = try await fixture.store.fetchWorkout(id: fixture.workout.id)
        XCTAssertEqual(loadedValue20, fixture.workout)
        let loadedValue21 = try await bStore.fetchWorkout(id: bItem.id)
        XCTAssertEqual(loadedValue21, bItem)
        XCTAssertEqual(try bContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 1)
        XCTAssertNil(fixture.model.notice)
    }

    func testAccountSwitchWhileRemoteDeleteWaitsCannotEraseReplacementScope() async throws {
        let fixture = try await fixture()
        let started = expectation(description: "remote delete started")
        var continuation: CheckedContinuation<Void, Never>?
        fixture.remote.onDelete = { await withCheckedContinuation { continuation = $0; started.fulfill() } }
        let task = Task { await fixture.model.delete() }
        await fulfillment(of: [started], timeout: 2)
        try fixture.storage.switchAccount(userID: UUID())
        let other = workout()
        let bStore = SwiftDataUnifiedWorkoutStore(modelContext: fixture.storage.container.mainContext)
        try await bStore.saveWorkout(other)
        continuation?.resume()
        await task.value
        XCTAssertFalse(fixture.model.isDeleted)
        let loadedValue22 = try await fixture.store.fetchWorkout(id: fixture.workout.id)
        XCTAssertNotNil(loadedValue22)
        let loadedValue23 = try await bStore.fetchWorkout(id: other.id)
        XCTAssertEqual(loadedValue23, other)
    }

    func testExplicitMetadataUploadRestoresOnAnotherDeviceForSameOwnerOnly() async throws {
        let remote = ManagementHealthRemote(), owner = UUID()
        let first = try storage(remote: remote)
        try first.switchAccount(userID: owner)
        try first.setCloudConsent(true)
        var item = workout()
        item.userTitle = "복원할 제목"; item.userDescription = "복원할 설명"
        item.sharingVisibilityRaw = FeedPostVisibility.privatePost.rawValue; item.isBookmarked = true
        try await SwiftDataUnifiedWorkoutStore(modelContext: first.container.mainContext).saveWorkout(item)
        await first.syncNow()
        XCTAssertNil(first.errorMessage)
        let second = try storage(remote: remote)
        try second.switchAccount(userID: owner); try second.setCloudConsent(true)
        await second.syncNow()
        let loadedValue24 = try await SwiftDataUnifiedWorkoutStore(modelContext: second.container.mainContext).fetchWorkout(id: item.id)
        let restored = try XCTUnwrap(loadedValue24)
        assertMetadata(restored, equals: item)
        try second.switchAccount(userID: UUID()); try second.setCloudConsent(true)
        await second.syncNow()
        XCTAssertEqual(try second.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 0)
    }

    func testStableRemotePostIDIsIdempotentAndOwnerScoped() {
        let owner = UUID(), otherOwner = UUID(), item = UUID()
        XCTAssertEqual(SupabaseWorkoutRecordRemote.postID(owner: owner, workout: item), SupabaseWorkoutRecordRemote.postID(owner: owner, workout: item))
        XCTAssertNotEqual(SupabaseWorkoutRecordRemote.postID(owner: owner, workout: item), SupabaseWorkoutRecordRemote.postID(owner: otherOwner, workout: item))
    }

    func testLateConfigurationWithOldContextCannotPublishOldAccountRecordAsNewOwner() async throws {
        let controller = try storage()
        try controller.switchAccount(userID: UUID())
        let oldContext = controller.container.mainContext
        let oldStore = SwiftDataUnifiedWorkoutStore(modelContext: oldContext)
        let oldItem = workout()
        try await oldStore.saveWorkout(oldItem)
        try controller.switchAccount(userID: UUID())
        let model = WorkoutRecordManagement(workout: oldItem)
        let remote = ManagementRemoteStub()
        model.configure(context: oldContext, storage: controller, remote: remote, drafts: ManagementDraftStore())
        await model.setVisibility(.publicPost)
        XCTAssertTrue(remote.updates.isEmpty)
        XCTAssertNotNil(model.errorMessage)
        let unchanged = try await oldStore.fetchWorkout(id: oldItem.id)
        XCTAssertEqual(unchanged, oldItem)
        XCTAssertEqual(try controller.container.mainContext.fetchCount(FetchDescriptor<UnifiedWorkoutRecord>()), 0)
    }

    func testDelayedPrivateRefreshCannotOverwriteNewlyAcknowledgedPublicVisibility() async throws {
        let fixture = try await fixture()
        let started = expectation(description: "old sharing lookup started")
        var continuation: CheckedContinuation<[FeedPostDTO], Error>?
        fixture.remote.onLookup = {
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        }
        let refresh = Task { await fixture.model.refreshSharing() }
        await fulfillment(of: [started], timeout: 2)
        await fixture.model.setVisibility(.publicPost)
        XCTAssertEqual(fixture.model.visibility, .publicPost)
        let acknowledgedMutation = try XCTUnwrap(entries(fixture.storage).first { $0.kind == "workout" }).mutationID
        continuation?.resume(returning: []) // Old server snapshot: no public linked post.
        await refresh.value
        let stored = try await fixture.store.fetchWorkout(id: fixture.workout.id)
        XCTAssertEqual(stored?.recordVisibility, .publicPost)
        XCTAssertEqual(fixture.model.visibility, .publicPost)
        XCTAssertTrue(fixture.model.sharingChecked)
        XCTAssertNil(fixture.model.sharingError)
        XCTAssertEqual(try entries(fixture.storage).first { $0.kind == "workout" }?.mutationID, acknowledgedMutation)
    }

    func testDelayedEditPreservesBookmarkWrittenByAnotherScreen() async throws {
        let fixture = try await fixture()
        let started = expectation(description: "edit waiting for server")
        var continuation: CheckedContinuation<Void, Never>?
        fixture.remote.onUpdate = { await withCheckedContinuation { continuation = $0; started.fulfill() } }
        let editing = Task { await fixture.model.edit(title: "수정한 제목", description: "수정한 설명") }
        await fulfillment(of: [started], timeout: 2)
        let otherScreen = WorkoutRecordManagement(workout: fixture.workout)
        otherScreen.configure(context: fixture.storage.container.mainContext, storage: fixture.storage,
                              remote: ManagementRemoteStub(), drafts: fixture.drafts)
        await otherScreen.toggleBookmark()
        XCTAssertTrue(otherScreen.isBookmarked)
        continuation?.resume()
        let saved = await editing.value
        XCTAssertTrue(saved)
        let storedValue = try await fixture.store.fetchWorkout(id: fixture.workout.id)
        let stored = try XCTUnwrap(storedValue)
        XCTAssertEqual(stored.userTitle, "수정한 제목")
        XCTAssertEqual(stored.userDescription, "수정한 설명")
        XCTAssertEqual(stored.isBookmarked, true)
        XCTAssertTrue(fixture.model.isBookmarked)
        let payload = try XCTUnwrap(entries(fixture.storage).first { $0.kind == "workout" }?.payload)
        let queued = try XCTUnwrap(HealthCloudPayload.decode(payload).workout)
        assertMetadata(queued, equals: stored)
    }

    func testDelayedRefreshFromAnotherScreenCannotOverwritePersistedPublicChange() async throws {
        let fixture = try await fixture()
        let started = expectation(description: "other screen sharing lookup")
        var continuation: CheckedContinuation<[FeedPostDTO], Error>?
        fixture.remote.onLookup = {
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        }
        let refresh = Task { await fixture.model.refreshSharing() }
        await fulfillment(of: [started], timeout: 2)
        let otherScreen = WorkoutRecordManagement(workout: fixture.workout)
        otherScreen.configure(context: fixture.storage.container.mainContext, storage: fixture.storage,
                              remote: ManagementRemoteStub(), drafts: fixture.drafts)
        await otherScreen.setVisibility(.publicPost)
        continuation?.resume(returning: [])
        await refresh.value
        let stored = try await fixture.store.fetchWorkout(id: fixture.workout.id)
        XCTAssertEqual(stored?.recordVisibility, .publicPost)
        XCTAssertFalse(fixture.model.sharingChecked, "The stale reader must not present an old result as verified")
        XCTAssertNil(fixture.model.visibility)
    }

    func testReviewDemoEditsPublishesBookmarksAndDeletesOnlyDemoData() async throws {
        let controller = ReviewDemoController.shared
        controller.start()
        defer { controller.exit() }
        let runtime = try XCTUnwrap(controller.runtime)
        let storage = runtime.storage
        let store = SwiftDataUnifiedWorkoutStore(modelContext: storage.container.mainContext)
        let item = workout()
        try await store.saveWorkout(item)
        let realRemote = ManagementRemoteStub()
        realRemote.failure = URLError(.notConnectedToInternet)
        let model = WorkoutRecordManagement(workout: item)
        model.configure(context: storage.container.mainContext, storage: storage,
                        remote: realRemote, drafts: ManagementDraftStore())

        await model.refreshSharing()
        XCTAssertTrue(model.sharingChecked)
        XCTAssertEqual(model.visibility, .privatePost)
        let edited = await model.edit(title: "Demo evening run", description: "Edited in demo", location: "Demo park")
        XCTAssertTrue(edited, model.errorMessage ?? "")
        XCTAssertTrue(model.canSavePhotos)
        let samplePhoto = WorkoutPhotoDraft(jpegData: try XCTUnwrap(ReviewDemoPhotoStore.sampleJPEGData()))
        let photosSaved = await model.edit(title: "Demo evening run", description: "Edited in demo", photos: [samplePhoto])
        XCTAssertTrue(photosSaved, model.errorMessage ?? "")
        await model.refreshPhotos()
        XCTAssertEqual(model.photos.count, 1)
        let photoReference = try XCTUnwrap(model.photos.first?.reference)
        XCTAssertNotNil(ReviewDemoPhotoStore.shared.bytes(for: photoReference))
        await model.toggleBookmark()
        let published = await model.setVisibility(.publicPost)
        XCTAssertTrue(published, model.errorMessage ?? "")
        let saved = try await store.fetchWorkout(id: item.id)
        XCTAssertEqual(saved?.userTitle, "Demo evening run")
        XCTAssertEqual(saved?.userDescription, "Edited in demo")
        XCTAssertEqual(saved?.locationName, "Demo park")
        XCTAssertEqual(saved?.isBookmarked, true)
        XCTAssertEqual(saved?.recordVisibility, .publicPost)
        let publicItem = ReviewDemoCommunityStore.shared.items.first { $0.sourceWorkoutId == item.id }
        XCTAssertEqual(publicItem?.visibility, .publicFeed)
        XCTAssertEqual(publicItem?.activityContext, "Demo evening run")

        let madePrivate = await model.setVisibility(.privatePost)
        XCTAssertTrue(madePrivate, model.errorMessage ?? "")
        XCTAssertEqual(ReviewDemoCommunityStore.shared.items.first { $0.sourceWorkoutId == item.id }?.visibility, .privateOnly)
        await model.delete()
        XCTAssertTrue(model.isDeleted)
        let deleted = try await store.fetchWorkout(id: item.id)
        XCTAssertNil(deleted)
        XCTAssertFalse(ReviewDemoCommunityStore.shared.items.contains { $0.sourceWorkoutId == item.id })
        let removedPhotos = try await ReviewDemoPhotoStore.shared.load(workoutID: item.id, ownerID: ReviewDemoMode.userID)
        XCTAssertTrue(removedPhotos.isEmpty)
        XCTAssertNil(ReviewDemoPhotoStore.shared.bytes(for: photoReference))
        XCTAssertTrue(realRemote.updates.isEmpty)
        XCTAssertTrue(realRemote.deletedIDs.isEmpty)
    }

    func testReviewDemoImportPublicationAndBulkPrivateStayInDemo() async throws {
        let controller = ReviewDemoController.shared
        controller.start()
        defer { controller.exit() }
        let storage = try XCTUnwrap(controller.runtime?.storage)
        let store = SwiftDataUnifiedWorkoutStore(modelContext: storage.container.mainContext)
        var item = workout()
        item.sharingVisibilityRaw = ImportedWorkoutPublication.pendingVisibility
        try await store.saveWorkout(item)
        storage.setAutoPublishImportedWorkouts(true)
        let realRemote = ManagementRemoteStub()
        realRemote.failure = URLError(.notConnectedToInternet)
        let publication = ImportedWorkoutPublication(context: storage.container.mainContext,
            storage: storage, remote: realRemote)
        let published = await publication.publish(ids: [item.id])
        XCTAssertEqual(published.published, 1)
        XCTAssertEqual(published.failed, 0)
        XCTAssertEqual(ReviewDemoCommunityStore.shared.items.first { $0.sourceWorkoutId == item.id }?.visibility, .publicFeed)
        let hidden = await publication.makeAllPrivate()
        XCTAssertFalse(hidden.serverFailed)
        XCTAssertEqual(hidden.failed, 0)
        XCTAssertGreaterThan(hidden.leftPrivate, 0)
        let saved = try await store.fetchWorkout(id: item.id)
        XCTAssertEqual(saved?.recordVisibility, .privatePost)
        XCTAssertEqual(ReviewDemoCommunityStore.shared.items.first { $0.sourceWorkoutId == item.id }?.visibility, .privateOnly)
        XCTAssertTrue(realRemote.updates.isEmpty)
        XCTAssertTrue(realRemote.bulkPrivateOwners.isEmpty)
    }

    func testReviewDemoExitRejectsRetainedWorkoutEditor() async throws {
        let controller = ReviewDemoController.shared
        controller.start()
        defer { controller.exit() }
        let storage = try XCTUnwrap(controller.runtime?.storage)
        let store = SwiftDataUnifiedWorkoutStore(modelContext: storage.container.mainContext)
        let item = workout()
        try await store.saveWorkout(item)
        let model = WorkoutRecordManagement(workout: item)
        model.configure(context: storage.container.mainContext, storage: storage, drafts: ManagementDraftStore())
        controller.exit()
        let changed = await model.edit(title: "Stale demo change", description: "")
        XCTAssertFalse(changed)
        XCTAssertNotNil(model.errorMessage)
        let unchanged = try await store.fetchWorkout(id: item.id)
        XCTAssertEqual(unchanged, item)
    }

    func testEnteringReviewDemoRejectsRetainedRealAccountEditor() async throws {
        let fixture = try await fixture()
        let controller = ReviewDemoController.shared
        controller.start()
        defer { controller.exit() }
        _ = try XCTUnwrap(controller.runtime)
        fixture.remote.onLookup = {
            XCTFail("The retained account screen must not read remote posts during demo")
            return []
        }
        await fixture.model.refreshSharing()
        let changed = await fixture.model.edit(title: "Must not reach account", description: "")
        XCTAssertFalse(changed)
        XCTAssertTrue(fixture.remote.updates.isEmpty)
        let unchanged = try await fixture.store.fetchWorkout(id: fixture.workout.id)
        XCTAssertEqual(unchanged, fixture.workout)
    }

    func testRefreshMutualSharingPreservesLocalMutualMetadataWithoutPublishing() async throws {
        let owner = UUID()
        let fixture = try await fixture(owner: owner)
        let edited = await fixture.model.edit(title: "내 기록 제목", description: "내 기록 설명")
        XCTAssertTrue(edited)
        let original = fixture.model.workout
        fixture.remote.updates.removeAll()
        fixture.remote.onLookup = {
            [FeedPostDTO(id: UUID(), userId: owner, sourceWorkoutId: fixture.workout.id,
                sport: .running, title: "맞팔 기록", body: "서버 게시 설명", visibility: .mutual, createdAt: fixture.workout.createdAt)]
        }
        await fixture.model.refreshSharing()
        XCTAssertEqual(fixture.model.visibility, .mutual)
        let fetched = try await fixture.store.fetchWorkout(id: fixture.workout.id)
        let saved = try XCTUnwrap(fetched)
        XCTAssertEqual(saved.recordVisibility, .mutual)
        XCTAssertEqual(saved.userTitle, original.userTitle)
        XCTAssertEqual(saved.userDescription, original.userDescription)
        XCTAssertTrue(fixture.remote.updates.isEmpty)
        XCTAssertTrue(fixture.remote.deletedIDs.isEmpty)
    }

    func testOpeningUnpublishedImportedCardPreservesEveryCapturedAudience() async throws {
        for scope in [FeedPostVisibility.privatePost,.followers,.publicPost] {
            let f = try await fixture()
            var item=f.workout; item.sharingVisibilityRaw=ImportedWorkoutPublication.pendingVisibility(for:scope)
            let records=try f.storage.container.mainContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>())
            let record=try XCTUnwrap(records.first(where:{$0.id == item.id}))
            record.sharingVisibilityRaw=item.sharingVisibilityRaw
            try f.storage.container.mainContext.save()
            let model=WorkoutRecordManagement(workout:item)
            model.configure(context:f.storage.container.mainContext,storage:f.storage,remote:f.remote,drafts:f.drafts)
            f.remote.onLookup = { [] }
            await model.refreshSharing()
            let persisted=try await f.store.fetchWorkout(id:item.id)
            XCTAssertEqual(persisted?.sharingVisibilityRaw,item.sharingVisibilityRaw)
            XCTAssertTrue(f.remote.updates.isEmpty)
        }
    }

    func testResolutionNeverAdoptsLaterDefaultForUnknownOrCapturedPrivateIntent() {
        XCTAssertEqual(ImportedWorkoutPublication.resolutionAudience("source_review_pending", autoPublish:true), .privatePost)
        XCTAssertEqual(ImportedWorkoutPublication.resolutionAudience("auto_public_pending", autoPublish:true), .privatePost)
        for scope in [FeedPostVisibility.privatePost,.followers,.publicPost] {
            XCTAssertEqual(ImportedWorkoutPublication.resolutionAudience(ImportedWorkoutPublication.pendingVisibility(for:scope), autoPublish:true),scope)
            XCTAssertEqual(ImportedWorkoutPublication.resolutionAudience(ImportedWorkoutPublication.pendingVisibility(for:scope), autoPublish:false),.privatePost)
        }
    }

    func testUnverifiedSocialPreservesLocalOwnerEditWithoutSendingRemoteUpdate() async throws {
        let f=try await fixture()
        let owner=try XCTUnwrap(f.storage.userID)
        let state=CommunitySafetyStore(client:nil,viewerID:owner,requiresSocialVerification:true)
        let model=WorkoutRecordManagement(workout:f.workout)
        model.configure(context:f.storage.container.mainContext,storage:f.storage,remote:f.remote,drafts:f.drafts,socialState:state)
        let edited=await model.edit(title:"오프라인 내 기록",description:"개인 메모");XCTAssertTrue(edited)
        XCTAssertTrue(f.remote.updates.isEmpty)
        let saved=try await f.store.fetchWorkout(id:f.workout.id)
        XCTAssertEqual(saved?.userTitle,"오프라인 내 기록")
        XCTAssertEqual(saved?.sharingVisibilityRaw,f.workout.sharingVisibilityRaw)
        XCTAssertTrue(model.notice?.contains("소셜 공유 내용은 변경하지 않았어요") == true)
    }

    func testOldPendingWorkoutRemainsUnchangedAfterNewSharingCompletionUntilExplicitRetry() async throws {
        let fixture = try await fixture(), owner = try XCTUnwrap(fixture.storage.userID)
        let context = fixture.storage.container.mainContext
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<UnifiedWorkoutRecord>()).first)
        record.sharingVisibilityRaw = ImportedWorkoutPublication.pendingVisibility(for: .publicPost)
        try context.save()
        FullWorkoutSharingConsent.record(owner: owner, revision: 1, at: record.startDate.addingTimeInterval(1))
        let publisher = ImportedWorkoutPublication(context: context, storage: fixture.storage, remote: fixture.remote, privacy: PublicationPrivacyStub(owner: owner))
        let pending = record.sharingVisibilityRaw
        let automatic = await publisher.publish()
        XCTAssertEqual(automatic.published, 0); XCTAssertEqual(automatic.failed, 0)
        XCTAssertTrue(fixture.remote.updates.isEmpty)
        XCTAssertEqual(record.sharingVisibilityRaw, pending)
        let explicit = await publisher.publish(ids: [record.id], explicitlySharingWorkoutID: record.id)
        XCTAssertEqual(explicit.published, ProfileOnlyPrivacyReleaseGate.productionReady ? 0 : 1)
        XCTAssertEqual(fixture.remote.updates.count, ProfileOnlyPrivacyReleaseGate.productionReady ? 0 : 1)
        if ProfileOnlyPrivacyReleaseGate.productionReady {XCTAssertEqual(record.sharingVisibilityRaw,pending)}
        UserDefaults.standard.removeObject(forKey: FullWorkoutSharingConsent.key(owner: owner))
    }
    func testUnacknowledgedOrDifferentConsentRevisionCannotAutoPublishPendingWorkout() async throws {
        let fixture = try await fixture(), owner = try XCTUnwrap(fixture.storage.userID)
        let context = fixture.storage.container.mainContext
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<UnifiedWorkoutRecord>()).first)
        record.sharingVisibilityRaw = ImportedWorkoutPublication.pendingVisibility(for: .publicPost)
        try context.save()
        let publisher = ImportedWorkoutPublication(context: context, storage: fixture.storage, remote: fixture.remote, privacy: PublicationPrivacyStub(owner: owner))
        UserDefaults.standard.removeObject(forKey: FullWorkoutSharingConsent.key(owner: owner))
        let unacknowledged = await publisher.publish()
        XCTAssertEqual(unacknowledged.published, 0)
        FullWorkoutSharingConsent.record(owner: owner, revision: 2, at: Date(timeIntervalSince1970: 0))
        let mismatched = await publisher.publish()
        XCTAssertEqual(mismatched.published, 0)
        XCTAssertTrue(fixture.remote.updates.isEmpty)
        XCTAssertEqual(record.sharingVisibilityRaw, ImportedWorkoutPublication.pendingVisibility(for: .publicPost))
        UserDefaults.standard.removeObject(forKey: FullWorkoutSharingConsent.key(owner: owner))
    }

    func testPhotoOnlySavePreservesMetadataAndVisibility() async throws {
        let controller = ReviewDemoController.shared
        controller.start()
        defer { controller.exit() }
        let runtime = try XCTUnwrap(controller.runtime)
        let store = SwiftDataUnifiedWorkoutStore(modelContext: runtime.storage.container.mainContext)
        var item = workout()
        item.userTitle = "보존할 제목"
        item.userDescription = "보존할 설명"
        item.locationName = "보존할 지역"
        item.sharingVisibilityRaw = FeedPostVisibility.privatePost.rawValue
        try await store.saveWorkout(item)
        let model = WorkoutRecordManagement(workout: item)
        model.configure(context: runtime.storage.container.mainContext, storage: runtime.storage,
            remote: ManagementRemoteStub(), drafts: ManagementDraftStore())
        await model.refreshPhotos()
        let photo = WorkoutPhotoDraft(jpegData: try XCTUnwrap(ReviewDemoPhotoStore.sampleJPEGData()))
        let saved = await model.replacePhotos([photo])
        XCTAssertTrue(saved, model.errorMessage ?? "")
        let after = try await store.fetchWorkout(id: item.id)
        XCTAssertEqual(after?.userTitle, item.userTitle)
        XCTAssertEqual(after?.userDescription, item.userDescription)
        XCTAssertEqual(after?.locationName, item.locationName)
        XCTAssertEqual(after?.sharingVisibilityRaw, item.sharingVisibilityRaw)
        await model.refreshPhotos()
        XCTAssertEqual(model.photos.count, 1)
    }

    func testGuestPhotoOnlySaveIsRejectedWithoutMetadataChanges() async throws {
        let f = try await fixture(owner: nil)
        let saved = await f.model.replacePhotos([])
        XCTAssertFalse(saved)
        XCTAssertTrue(f.remote.updates.isEmpty)
        let after = try await f.store.fetchWorkout(id: f.workout.id)
        XCTAssertEqual(after?.userTitle, f.workout.userTitle)
        XCTAssertEqual(after?.userDescription, f.workout.userDescription)
    }

    func testAutomaticShareChoosesRichRecordAndPreservesOriginalsAndRetryIdentity() async throws {
        let f = try await fixture()
        let date = f.workout.startDate
        let rich = UnifiedWorkout(id: UUID(), externalId: "watch-rich", source: .appleHealthKit,
            workoutType: .running, startDate: date, endDate: date.addingTimeInterval(600), durationSeconds: 600,
            distanceMeters: 1500, activeEnergyKcal: 120, averageHeartRate: 140, maxHeartRate: 170,
            averageSpeedMetersPerSecond: 2.5, elevationGainMeters: 5, dataQuality: .partial,
            createdAt: date, updatedAt: date)
        try await f.store.saveWorkout(rich)
        var hidden: [UUID] = []
        let flow = UnifiedWorkoutAutomaticShare(context: f.storage.container.mainContext, validate: {},
            makeSecondaryPrivate: { hidden.append($0.id) })
        let first = try await flow.prepare(workoutID: f.workout.id)
        XCTAssertEqual(first.id, rich.id)
        XCTAssertEqual(first.averageHeartRate, 140)
        XCTAssertEqual(first.distanceMeters, 1500) // Never sum two copies.
        XCTAssertEqual(hidden, [f.workout.id])
        let retry = try await flow.prepare(workoutID: f.workout.id)
        XCTAssertEqual(retry.id, first.id)
        XCTAssertEqual(retry.resolutionRequestID, first.resolutionRequestID)
        let original = try await f.store.fetchWorkout(id: f.workout.id)
        XCTAssertNil(original?.averageHeartRate)
        XCTAssertEqual(original?.distanceMeters, f.workout.distanceMeters)
        try flow.complete(primaryID: first.id)
        let rows = try f.storage.container.mainContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.preferredWorkoutID == rich.id && $0.resolutionRequestID == nil })
    }

    func testAutomaticShareFailureKeepsPendingIdentityAndDoesNotReturnPublishableSnapshot() async throws {
        let f = try await fixture()
        let second = workout()
        try await f.store.saveWorkout(second)
        let flow = UnifiedWorkoutAutomaticShare(context: f.storage.container.mainContext, validate: {},
            makeSecondaryPrivate: { _ in throw URLError(.notConnectedToInternet) })
        do { _ = try await flow.prepare(workoutID: second.id); XCTFail("Must stop before publishing") }
        catch { XCTAssertTrue(error is URLError) }
        let rows = try f.storage.container.mainContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.compactMap(\.preferredWorkoutID)).count, 1)
        XCTAssertTrue(rows.allSatisfy { $0.resolutionRequestID != nil })
    }

    func testAutomaticShareLeavesUnrelatedAndExplicitlySeparateRecordsAlone() async throws {
        let f = try await fixture()
        var second = workout()
        second.keepSeparate = true
        try await f.store.saveWorkout(second)
        var hidden = false
        let flow = UnifiedWorkoutAutomaticShare(context: f.storage.container.mainContext, validate: {},
            makeSecondaryPrivate: { _ in hidden = true })
        let prepared = try await flow.prepare(workoutID: second.id)
        XCTAssertEqual(prepared.id, second.id)
        XCTAssertFalse(hidden)
        let rows = try f.storage.container.mainContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>())
        XCTAssertTrue(rows.allSatisfy { $0.preferredWorkoutID == nil })
    }

    func testAutomaticShareCoverageTieIsOrderIndependentAndExistingIdentityStaysStable() {
        var a = workout(), b = workout()
        let engine = UnifiedWorkoutDeduplicationEngine()
        XCTAssertEqual(engine.automaticPublicationPrimary(in: [a,b])?.id,
            engine.automaticPublicationPrimary(in: [b,a])?.id)
        XCTAssertEqual(engine.automaticPublicationPrimary(in: [a,b], measuredCoverage: [b.id: 4])?.id, b.id)
        a.preferredWorkoutID = a.id
        b.preferredWorkoutID = a.id
        XCTAssertEqual(engine.automaticPublicationPrimary(in: [a,b], measuredCoverage: [b.id: 100])?.id, a.id)
    }

    func testPassiveReadbackReceiptRequiresExactOwnerGenerationAndProfileOnlyPolicy() async throws {
        let f = try await fixture(), owner = try XCTUnwrap(f.storage.userID)
        let captured = PassiveChangeCapture()
        let token = NotificationCenter.default.addObserver(forName: WorkoutRecordManagement.didChange, object: nil, queue: nil) { captured.append($0) }
        defer { NotificationCenter.default.removeObserver(token) }
        let generation = CommunitySafetyStore.shared.accountGeneration
        await f.model.refreshSharing()
        let note = try XCTUnwrap(captured.notes.last)
        func classify(_ n: Notification, viewer: UUID? = nil, auth: UUID? = nil, gen: Int? = nil, policy: AccountActivityReadPolicy = .profileOnlyV2) -> UUID? {
            WorkoutRecordChange.passiveReadbackWorkoutID(n, viewerID: viewer ?? owner, authOwnerID: auth ?? owner, generation: gen ?? generation, policy: policy)
        }
        XCTAssertEqual(classify(note), f.workout.id)
        XCTAssertNil(WorkoutRecordChange.passiveReadbackWorkoutID(note, viewerID: nil, authOwnerID: owner, generation: generation, policy: .profileOnlyV2))
        XCTAssertNil(WorkoutRecordChange.passiveReadbackWorkoutID(note, viewerID: owner, authOwnerID: nil, generation: generation, policy: .profileOnlyV2))
        XCTAssertNil(classify(note, viewer: UUID()))
        XCTAssertNil(classify(note, auth: UUID()))
        XCTAssertNil(classify(note, gen: generation + 1))
        XCTAssertNil(classify(note, policy: .approvedFollowersV1))
        XCTAssertNil(classify(Notification(name: note.name, object: UUID(), userInfo: note.userInfo)))
        XCTAssertNil(classify(Notification(name: Notification.Name("untrusted"), object: owner, userInfo: note.userInfo)))
        XCTAssertNil(classify(Notification(name: note.name, object: owner, userInfo: ["passiveReadback": "forged"])))
        XCTAssertNil(classify(Notification(name: note.name, object: owner)))
        let afterFirst = captured.notes.count
        await f.model.refreshSharing()
        XCTAssertEqual(captured.notes.count, afterFirst, "Stable readback does not churn notifications")
        let local = try await f.store.fetchWorkout(id: f.workout.id)
        XCTAssertEqual(local?.recordVisibility, .privatePost, "The existing local mirror still updates")
        XCTAssertTrue(f.remote.updates.isEmpty)
    }

    func testUserMutationsNeverAcquirePassiveReadbackReceipt() async throws {
        let f = try await fixture(), owner = try XCTUnwrap(f.storage.userID)
        let captured = PassiveChangeCapture()
        let token = NotificationCenter.default.addObserver(forName: WorkoutRecordManagement.didChange, object: nil, queue: nil) { captured.append($0) }
        defer { NotificationCenter.default.removeObserver(token) }
        await f.model.toggleBookmark()
        await f.model.setVisibility(.publicPost)
        let edited = await f.model.edit(title: "Explicit user title", description: "Explicit user description")
        XCTAssertTrue(edited)
        await f.model.delete()
        XCTAssertGreaterThanOrEqual(captured.notes.count, 4)
        for note in captured.notes {
            XCTAssertNil(WorkoutRecordChange.passiveReadbackWorkoutID(note, viewerID: owner, authOwnerID: owner, generation: CommunitySafetyStore.shared.accountGeneration, policy: .profileOnlyV2))
        }
    }

    private struct Fixture {
        let storage: HealthAccountStorageController
        let store: SwiftDataUnifiedWorkoutStore
        let workout: UnifiedWorkout
        let model: WorkoutRecordManagement
        let remote: ManagementRemoteStub
        let drafts: ManagementDraftStore
    }
    func testProfileOnlySourceRefreshPreservesOriginalRouteAndConsentWithoutLegacyLookupOrUpload() async throws {
        let f=try await fixture(existingDetailRefresher:ExistingDetailRefreshStub()),owner=try XCTUnwrap(f.storage.userID)
        let routeStore=SwiftDataWorkoutRoutePersistenceStore(modelContext:f.storage.container.mainContext)
        try await routeStore.saveRoute(route(f.workout))
        let beforeWorkout=try await f.store.fetchWorkout(id:f.workout.id)
        let beforeRoute=try await routeStore.fetchRoute(workoutId:f.workout.id)
        let consentKey=FullWorkoutSharingConsent.key(owner:owner),beforeConsent=UserDefaults.standard.dictionary(forKey:consentKey) as NSDictionary?
        XCTAssertNotNil(beforeConsent)
        var lookups=0
        f.remote.onLookup={lookups += 1;return []}
        let ok=await f.model.refreshProviderMeasurements();XCTAssertTrue(ok)
        XCTAssertEqual(lookups,ImportedWorkoutPublication.usesLegacyPublication ? 1 : 0)
        XCTAssertTrue(f.remote.updates.isEmpty)
        let afterWorkout=try await f.store.fetchWorkout(id:f.workout.id),afterRoute=try await routeStore.fetchRoute(workoutId:f.workout.id)
        XCTAssertEqual(beforeWorkout,afterWorkout);XCTAssertEqual(beforeRoute,afterRoute)
        XCTAssertEqual(UserDefaults.standard.dictionary(forKey:consentKey) as NSDictionary?,beforeConsent)
    }
    private func fixture(owner: UUID? = UUID(), existingDetailRefresher:(any WorkoutExistingDetailRefreshing)? = nil) async throws -> Fixture {
        let controller = try storage()
        try controller.switchAccount(userID: owner)
        if let owner {
            UserDefaults.standard.set("public",forKey:"SOOM.workoutAudience.v1.\(owner.uuidString.lowercased())")
            FullWorkoutSharingConsent.record(owner: owner, revision: 1, at: Date(timeIntervalSince1970: 0))
        }
        let store = SwiftDataUnifiedWorkoutStore(modelContext: controller.container.mainContext)
        let item = workout()
        try await store.saveWorkout(item)
        let model = WorkoutRecordManagement(workout: item)
        let remote = ManagementRemoteStub(), drafts = ManagementDraftStore()
        model.configure(context: controller.container.mainContext, storage: controller, remote: remote, drafts: drafts, existingDetailRefresher:existingDetailRefresher)
        return Fixture(storage: controller, store: store, workout: item, model: model, remote: remote, drafts: drafts)
    }
    private func storage(remote: ManagementHealthRemote? = nil) throws -> HealthAccountStorageController {
        try HealthAccountStorageController(remote: remote, inMemory: true, monitorNetwork: false, automaticallySync: false)
    }
    private func diskStorage(_ directory: URL) throws -> HealthAccountStorageController {
        let schema = HealthAccountStorageController.schema
        let guest = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        return try HealthAccountStorageController(baseDirectory: directory, guestContainer: guest, monitorNetwork: false, automaticallySync: false)
    }
    private func workout(externalID: String? = nil, distance: Double = 1500) -> UnifiedWorkout {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return UnifiedWorkout(id: UUID(), externalId: externalID, source: .soomLocal, workoutType: .running,
            startDate: date, endDate: date.addingTimeInterval(600), durationSeconds: 600,
            distanceMeters: distance, activeEnergyKcal: nil, averageHeartRate: nil, maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: .partial,
            createdAt: date, updatedAt: date)
    }
    private func route(_ item: UnifiedWorkout) -> WorkoutRoute {
        WorkoutRoute(workoutId: item.id, source: .soomLocal,
            coordinates: [.init(latitude: 37.1, longitude: 127.1), .init(latitude: 37.2, longitude: 127.2)], totalDistanceMeters: 1500)
    }
    private func makeDraft(_ item: UnifiedWorkout) -> FeedShareDraft {
        FeedShareDraft(id: UUID(), sourceWorkoutId: item.id, sport: item.workoutType,
            title: item.displayTitle, body: item.userDescription ?? "", distanceMeters: item.distanceMeters,
            durationSeconds: item.durationSeconds, averagePaceSecondsPerKm: nil, routePreviewPayload: nil,
            photoPlaceholders: [], tags: [], visibility: .privateOnly, createdAt: item.createdAt)
    }
    private func entries(_ storage: HealthAccountStorageController) throws -> [HealthCloudOutboxRecord] {
        try storage.container.mainContext.fetch(FetchDescriptor<HealthCloudOutboxRecord>()).filter { HealthCloudKind(rawValue: $0.kind) != nil }
    }
    private func assertMetadata(_ actual: UnifiedWorkout, equals expected: UnifiedWorkout, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.userTitle, expected.userTitle, file: file, line: line)
        XCTAssertEqual(actual.userDescription, expected.userDescription, file: file, line: line)
        XCTAssertEqual(actual.sharingVisibilityRaw, expected.sharingVisibilityRaw, file: file, line: line)
        XCTAssertEqual(actual.isBookmarked, expected.isBookmarked, file: file, line: line)
    }
}

@MainActor
private final class ManagementRemoteStub: WorkoutRecordRemoteManaging {
    struct Update { let workout: UnifiedWorkout; let owner: UUID; let visibility: FeedPostVisibility?; let createIfMissing: Bool }
    var updates: [Update] = []
    var deletedIDs: [UUID] = []
    var bulkPrivateOwners: [UUID] = []
    var failure: Error?
    var onLookup: (() async throws -> [FeedPostDTO])?
    var onUpdate: (() async -> Void)?
    var onDelete: (() async -> Void)?
    func linkedPosts(workoutID: UUID, ownerID: UUID) async throws -> [FeedPostDTO] {
        if let failure { throw failure }
        if let onLookup { return try await onLookup() }
        return []
    }
    func update(workout: UnifiedWorkout, ownerID: UUID, visibility: FeedPostVisibility?, createIfMissing: Bool) async throws {
        updates.append(Update(workout: workout, owner: ownerID, visibility: visibility, createIfMissing: createIfMissing))
        if let failure { throw failure }
        await onUpdate?()
    }
    func makeAllWorkoutPostsPrivate(ownerID: UUID) async throws {
        if let failure { throw failure }
        bulkPrivateOwners.append(ownerID)
    }
    func delete(workoutID: UUID, ownerID: UUID) async throws {
        deletedIDs.append(workoutID)
        if let failure { throw failure }
        await onDelete?()
    }
}
private actor ManagementDraftStore: FeedShareDraftStoreProtocol {
    private var values: [FeedShareDraft] = []
    func saveDraft(_ draft: FeedShareDraft) async throws {
        values.removeAll { $0.id == draft.id || $0.sourceWorkoutId == draft.sourceWorkoutId }; values.append(draft)
    }
    func fetchDrafts() async throws -> [FeedShareDraft] { values }
    func deleteDraft(id: UUID) async throws { values.removeAll { $0.id == id } }
    func deleteAllDrafts() async throws { values.removeAll() }
}
@MainActor
private final class ManagementHealthRemote: HealthCloudRemote {
    var rows: [UUID: [String: HealthCloudRemoteRecord]] = [:]
    private var revision: Int64 = 0
    func push(_ mutation: HealthCloudMutation, expectedUserID: UUID) async throws -> HealthCloudRemoteRecord {
        revision += 1
        let value = HealthCloudRemoteRecord(kind: mutation.kind, recordKey: mutation.recordKey,
            payloadJSON: mutation.payload.flatMap { String(data: $0, encoding: .utf8) }, isDeleted: mutation.isDeleted,
            version: mutation.baseVersion + 1, revision: revision, accepted: true)
        rows[expectedUserID, default: [:]][mutation.kind + mutation.recordKey] = value
        return value
    }
    func pull(after revision: Int64, expectedUserID: UUID) async throws -> [HealthCloudRemoteRecord] {
        (rows[expectedUserID] ?? [:]).values.filter { $0.revision > revision }.sorted { $0.revision < $1.revision }
    }
}

@MainActor
private struct PublicationPrivacyStub: AccountPrivacyServing {
    let owner:UUID?
    var viewerID:UUID? { owner }
    func fetch() async throws -> AccountPrivacyReceipt { .init(enabled:true,accountScope:.publicAccount,workoutDefault:.publicPost,revision:1,shareMeasurements:true) }
    func save(owner:UUID,scope:AccountAudience,defaultWorkout:FeedPostVisibility,expectedRevision:Int64,shareMeasurements:Bool) async throws -> AccountPrivacyReceipt { throw CommunitySafetyError.unavailable }
}

final class FeedCommentPendingReleaseTests: XCTestCase {
    func testPendingRequestRoundTripPreservesIDAndScope() throws {
        let defaults = UserDefaults(suiteName: "soom.pending.test.\(UUID())")!
        let request = FeedCommentPendingRequest(postID: UUID(), viewerID: UUID(), body: "test", parentID: UUID(), mentions: [])
        try FeedCommentPendingStore.save(request, defaults: defaults)
        XCTAssertEqual(try FeedCommentPendingStore.read(viewer: request.viewerID, post: request.postID, defaults: defaults), request)
        XCTAssertNil(try FeedCommentPendingStore.read(viewer: UUID(), post: request.postID, defaults: defaults))
        FeedCommentPendingStore.clear(viewer: request.viewerID, post: request.postID, defaults: defaults)
        XCTAssertNil(try FeedCommentPendingStore.read(viewer: request.viewerID, post: request.postID, defaults: defaults))
    }
    func testRetryDoesNotAcceptEditedPayloadOrAnotherParent() {
        let p = FeedCommentPendingRequest(postID: UUID(), viewerID: UUID(), body: "test", parentID: UUID(), mentions: [])
        XCTAssertTrue(p.matches(postID: p.postID, viewerID: p.viewerID, body: p.body, parentID: p.parentID, mentions: []))
        XCTAssertFalse(p.matches(postID: p.postID, viewerID: p.viewerID, body: "edited", parentID: p.parentID, mentions: []))
        XCTAssertFalse(p.matches(postID: p.postID, viewerID: p.viewerID, body: p.body, parentID: UUID(), mentions: []))
    }
    func testProductionGateRemainsClosedBeforeBackendDeployment() {
        XCTAssertFalse(FeedReplyReleaseGate.productionReady)
    }
}

final class FeedCommentFailureReleaseTests: XCTestCase {
    func testOnlyExplicitValidationOrAccessRollbackIsDefinitive() {
        XCTAssertTrue(FeedCommentFailurePolicy.isDefinitiveFirstRejection(code: "22023"))
        XCTAssertTrue(FeedCommentFailurePolicy.isDefinitiveFirstRejection(code: "42501"))
        for code in [nil, "23505", "57014", "PGRST202", "500"] {
            XCTAssertFalse(FeedCommentFailurePolicy.isDefinitiveFirstRejection(code: code))
        }
    }
}

final class FeedCommentRecoveryContractTests: XCTestCase {
    func testOnlyExplicitAbsentAndIdenticalFrozenPayloadPermitRetry() {
        let p = FeedCommentPendingRequest(postID: UUID(), viewerID: UUID(), body: "frozen", parentID: UUID(), mentions: [])
        for state in [FeedCommentRecoveryState.found, .unavailable] {
            XCTAssertFalse(state.permitsRetry(p, postID: p.postID, viewerID: p.viewerID, body: p.body, parentID: p.parentID, mentions: []))
        }
        XCTAssertTrue(FeedCommentRecoveryState.absent.permitsRetry(p, postID: p.postID, viewerID: p.viewerID, body: p.body, parentID: p.parentID, mentions: []))
        XCTAssertFalse(FeedCommentRecoveryState.absent.permitsRetry(p, postID: p.postID, viewerID: p.viewerID, body: "edited", parentID: p.parentID, mentions: []))
        XCTAssertFalse(FeedCommentRecoveryState.absent.permitsRetry(p, postID: p.postID, viewerID: UUID(), body: p.body, parentID: p.parentID, mentions: []))
        XCTAssertFalse(FeedCommentRecoveryState.absent.permitsRetry(p, postID: UUID(), viewerID: p.viewerID, body: p.body, parentID: p.parentID, mentions: []))
    }
    func testUnknownAndNullStateCannotAuthorizeRetry() {
        XCTAssertThrowsError(try JSONDecoder().decode(FeedCommentRecoveryState.self, from: Data("null".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(FeedCommentRecoveryState.self, from: Data("\"missing\"".utf8)))
    }
    func testThirdPartyMentionLinksRemainServerIdentityBased() {
        let user = UUID()
        let linked = FeedMentionText.attributed("@third hello", references: [.init(userID: user, handle: "third")])
        XCTAssertTrue(linked.runs.contains { $0.link?.absoluteString == "soom-mention://profile/\(user.uuidString)" })
        XCTAssertFalse(FeedMentionText.attributed("@third hello", references: []).runs.contains { $0.link != nil })
    }
}


@MainActor private final class ExistingDetailRefreshStub:WorkoutExistingDetailRefreshing {
    var failure:Error?
    func refresh(sourceID:UUID,ownerID:UUID,validate:@escaping () throws -> Void,loadInput:@escaping () async throws -> WorkoutSharedDetailInput) async throws -> Int {
        try validate();if let failure {throw failure};return 0
    }
}
@MainActor final class WorkoutExistingDetailRefreshTests:XCTestCase {
    func testNoExistingGrantDoesNotLoadGPSOrWrite() async throws {
        let f=ExistingDetailTransportFixture();f.rows=[];var reads=0
        let count=try await WorkoutExistingDetailRefreshService(transport:f).refresh(sourceID:f.source,ownerID:f.owner,validate:{},loadInput:{reads += 1;return f.input})
        XCTAssertEqual(count,0);XCTAssertEqual(reads,0);XCTAssertTrue(f.writes.isEmpty)
    }
    func testAuthorizedRefreshCarriesExactCASAndDoesNotCreateAnotherEndpoint() async throws {
        let f=ExistingDetailTransportFixture();var reads=0
        let count=try await WorkoutExistingDetailRefreshService(transport:f).refresh(sourceID:f.source,ownerID:f.owner,validate:{},loadInput:{reads += 1;return f.input})
        XCTAssertEqual(count,1);XCTAssertEqual(reads,1);XCTAssertEqual(f.writes.count,1)
        let p=try XCTUnwrap(f.writes.first)
        XCTAssertEqual(p.p_post_id,f.post);XCTAssertEqual(p.p_source_id,f.source)
        XCTAssertEqual(p.p_expected_profile_revision,2);XCTAssertEqual(p.p_expected_measurement_revision,3);XCTAssertEqual(p.p_expected_detail_revision,4)
        XCTAssertEqual(p.p_input,f.input)
    }
    func testOwnerSwitchDuringLocalInputReadStopsTransmission() async throws {
        let f=ExistingDetailTransportFixture()
        do {_=try await WorkoutExistingDetailRefreshService(transport:f).refresh(sourceID:f.source,ownerID:f.owner,validate:{},loadInput:{f.ownerID=UUID();return f.input});XCTFail()} catch {}
        XCTAssertTrue(f.writes.isEmpty)
    }
    func testMalformedOrMaxRevisionReceiptFailsBeforeGPSRead() async throws {
        for variant in 0..<5 {
            let f=ExistingDetailTransportFixture();var reads=0
            switch variant {
            case 0:f.detailRevision=Int64.max
            case 1:f.profileRevision=Int64.max
            case 2:f.measurementRevision=Int64.max
            case 3:f.releaseReady=false
            default:f.rows=[.init(post_id:f.post,canonical_id:f.source,detail_revision:4),.init(post_id:UUID(),canonical_id:f.source,detail_revision:4)]
            }
            do {_=try await WorkoutExistingDetailRefreshService(transport:f).refresh(sourceID:f.source,ownerID:f.owner,validate:{},loadInput:{reads += 1;return f.input});XCTFail()} catch {}
            XCTAssertEqual(reads,0);XCTAssertTrue(f.writes.isEmpty)
        }
    }
    func testServerWithdrawalCASFailureIsNotReportedAsSuccess() async throws {
        let f=ExistingDetailTransportFixture();f.failure=PostgrestError(code:"PT409",message:"consent changed")
        do {_=try await WorkoutExistingDetailRefreshService(transport:f).refresh(sourceID:f.source,ownerID:f.owner,validate:{},loadInput:{f.input});XCTFail()} catch {}
        XCTAssertEqual(f.writes.count,1)
    }
    func testPendingExactTokenProtectsNewerRefreshAndOtherOwner() {
        let owner=UUID(),other=UUID(),id=UUID()
        let old=WorkoutExistingDetailRefreshPending.mark(ownerID:owner,workoutID:id)
        let new=WorkoutExistingDetailRefreshPending.mark(ownerID:owner,workoutID:id)
        let otherToken=WorkoutExistingDetailRefreshPending.mark(ownerID:other,workoutID:id)
        WorkoutExistingDetailRefreshPending.acknowledge(ownerID:owner,workoutID:id,token:old)
        XCTAssertEqual(WorkoutExistingDetailRefreshPending.entries(ownerID:owner)[id],new)
        WorkoutExistingDetailRefreshPending.acknowledge(ownerID:owner,workoutID:id,token:new)
        XCTAssertEqual(WorkoutExistingDetailRefreshPending.count(ownerID:owner),0)
        XCTAssertEqual(WorkoutExistingDetailRefreshPending.count(ownerID:other),1)
        WorkoutExistingDetailRefreshPending.acknowledge(ownerID:other,workoutID:id,token:otherToken)
    }
}
@MainActor private final class ExistingDetailTransportFixture:WorkoutExistingDetailRefreshTransport {
    let owner=UUID(),source=UUID(),post=UUID()
    lazy var ownerID:UUID?=owner
    var profileRevision:Int64=2,measurementRevision:Int64=3,detailRevision:Int64=4
    var releaseReady=true
    var rows:[WorkoutExistingDetailLookup.Row]?
    var writes=[WorkoutExistingDetailRefreshParameters]()
    var failure:Error?
    let input=WorkoutSharedDetailInput(durationSeconds:600,distanceMeters:1000,route:[],samples:[])
    func lookup(sourceID:UUID) async throws -> WorkoutExistingDetailLookup {
        .init(version:2,owner_id:owner,source_id:source,profile_revision:profileRevision,measurement_revision:measurementRevision,
              rows:rows ?? [.init(post_id:post,canonical_id:source,detail_revision:detailRevision)],release_ready:releaseReady)
    }
    func refresh(_ p:WorkoutExistingDetailRefreshParameters) async throws -> WorkoutExistingDetailRefreshReceipt {
        writes.append(p);if let failure {throw failure}
        return .init(version:2,owner_id:owner,post_id:post,source_id:source,detail_revision:p.p_expected_detail_revision+1,
                     profile_revision:profileRevision,measurement_revision:measurementRevision,refreshed:true,release_ready:true)
    }
}


@MainActor final class WorkoutExistingDetailRetryTests:XCTestCase {
    private func storageWithWorkout() async throws -> (HealthAccountStorageController,UUID) {
        let storage=try HealthAccountStorageController(inMemory:true,monitorNetwork:false,automaticallySync:false)
        try storage.switchAccount(userID:UUID());let id=UUID(),date=Date(timeIntervalSince1970:1_700_000_000)
        let value=UnifiedWorkout(id:id,externalId:nil,source:.appleHealthKit,workoutType:.running,startDate:date,endDate:date.addingTimeInterval(60),durationSeconds:60,distanceMeters:100,activeEnergyKcal:nil,averageHeartRate:nil,maxHeartRate:nil,averageSpeedMetersPerSecond:nil,elevationGainMeters:nil,dataQuality:.partial,createdAt:date,updatedAt:date)
        try await SwiftDataUnifiedWorkoutStore(modelContext:storage.container.mainContext).saveWorkout(value)
        WorkoutExistingDetailRefreshPending.mark(ownerID:storage.userID!,workoutID:id)
        return (storage,id)
    }
    func testForegroundRetryWaitsForCancelledPriorOwnerRunThenContinues() async throws {
        guard ProfileOnlyPrivacyReleaseGate.productionReady else{return}
        let (storage,_)=try await storageWithWorkout(),held=HeldExistingDetailRefresher()
        let entered=expectation(description:"held refresh");held.entered={entered.fulfill()}
        let first=Task {await WorkoutExistingDetailRefreshRetry.run(storage:storage,makeRefresher:{_ in held})}
        await fulfillment(of:[entered],timeout:2);first.cancel()
        let second=Task {await WorkoutExistingDetailRefreshRetry.run(storage:storage,makeRefresher:{_ in held})}
        try await Task.sleep(for:.milliseconds(75));XCTAssertEqual(held.calls,1)
        held.resume?.resume();await first.value;await second.value
        XCTAssertEqual(held.calls,2);XCTAssertEqual(held.maximumActive,1)
        XCTAssertEqual(WorkoutExistingDetailRefreshPending.count(ownerID:storage.userID!),0)
    }
    func testCancelledWaiterDoesNotStartAndAnotherOwnerIsIndependent() async throws {
        guard ProfileOnlyPrivacyReleaseGate.productionReady else{return}
        let (storage,_)=try await storageWithWorkout(),held=HeldExistingDetailRefresher()
        let entered=expectation(description:"held refresh");held.entered={entered.fulfill()}
        let first=Task {await WorkoutExistingDetailRefreshRetry.run(storage:storage,makeRefresher:{_ in held})}
        await fulfillment(of:[entered],timeout:2)
        let waiter=Task {await WorkoutExistingDetailRefreshRetry.run(storage:storage,makeRefresher:{_ in held})}
        waiter.cancel();await waiter.value
        let (other,_)=try await storageWithWorkout()
        await WorkoutExistingDetailRefreshRetry.run(storage:other,makeRefresher:{_ in ExistingDetailRefreshStub()})
        XCTAssertEqual(WorkoutExistingDetailRefreshPending.count(ownerID:other.userID!),0)
        XCTAssertEqual(held.calls,1)
        held.resume?.resume();await first.value
        XCTAssertEqual(held.calls,1)
    }
    func testRoundRobinReachesSuccessBeyondOneHundredPersistentFailures() async throws {
        guard ProfileOnlyPrivacyReleaseGate.productionReady else{return}
        let storage=try HealthAccountStorageController(inMemory:true,monitorNetwork:false,automaticallySync:false)
        try storage.switchAccount(userID:UUID());let owner=storage.userID!,date=Date(timeIntervalSince1970:1_700_000_000)
        let ids=(1...101).map{UUID(uuidString:String(format:"00000000-0000-0000-0000-%012d",$0))!}
        let values=ids.map{id in UnifiedWorkout(id:id,externalId:nil,source:.appleHealthKit,workoutType:.running,startDate:date,endDate:date.addingTimeInterval(60),durationSeconds:60,distanceMeters:100,activeEnergyKcal:nil,averageHeartRate:nil,maxHeartRate:nil,averageSpeedMetersPerSecond:nil,elevationGainMeters:nil,dataQuality:.partial,createdAt:date,updatedAt:date)}
        try await SwiftDataUnifiedWorkoutStore(modelContext:storage.container.mainContext).saveWorkouts(values)
        for id in ids {WorkoutExistingDetailRefreshPending.mark(ownerID:owner,workoutID:id)}
        let refresher=SelectiveExistingDetailRefresher(successID:ids[100])
        await WorkoutExistingDetailRefreshRetry.run(storage:storage,makeRefresher:{_ in refresher})
        XCTAssertEqual(refresher.attempts.count,100);XCTAssertFalse(refresher.attempts.contains(ids[100]))
        await WorkoutExistingDetailRefreshRetry.run(storage:storage,makeRefresher:{_ in refresher})
        XCTAssertEqual(refresher.attempts[100],ids[100]);XCTAssertNil(WorkoutExistingDetailRefreshPending.entries(ownerID:owner)[ids[100]])
        XCTAssertEqual(WorkoutExistingDetailRefreshPending.count(ownerID:owner),100)
        let other=UUID();WorkoutExistingDetailRefreshPending.mark(ownerID:other,workoutID:ids[0])
        XCTAssertEqual(WorkoutExistingDetailRefreshPending.nextBatch(ownerID:other).first?.key,ids[0])
        for account in [owner,other] {for (id,token) in WorkoutExistingDetailRefreshPending.entries(ownerID:account) {WorkoutExistingDetailRefreshPending.acknowledge(ownerID:account,workoutID:id,token:token)}}
    }
    func testRetryBatchIsBoundedToOneHundredAndMissingLocalRecordsDoNotTouchServer() async throws {
        guard ProfileOnlyPrivacyReleaseGate.productionReady else{return}
        let storage=try HealthAccountStorageController(inMemory:true,monitorNetwork:false,automaticallySync:false)
        try storage.switchAccount(userID:UUID());let owner=storage.userID!
        for _ in 0..<101 {WorkoutExistingDetailRefreshPending.mark(ownerID:owner,workoutID:UUID())}
        var factories=0
        await WorkoutExistingDetailRefreshRetry.run(storage:storage,makeRefresher:{_ in factories += 1;return ExistingDetailRefreshStub()})
        XCTAssertEqual(WorkoutExistingDetailRefreshPending.count(ownerID:owner),1);XCTAssertEqual(factories,0)
        await WorkoutExistingDetailRefreshRetry.run(storage:storage)
        XCTAssertEqual(WorkoutExistingDetailRefreshPending.count(ownerID:owner),0)
    }
}
@MainActor private final class HeldExistingDetailRefresher:WorkoutExistingDetailRefreshing {
    var calls=0,active=0,maximumActive=0
    var entered:(()->Void)?,resume:CheckedContinuation<Void,Never>?
    func refresh(sourceID:UUID,ownerID:UUID,validate:@escaping () throws -> Void,loadInput:@escaping () async throws -> WorkoutSharedDetailInput) async throws -> Int {
        calls += 1;active += 1;maximumActive=max(maximumActive,active);defer{active -= 1}
        if calls==1 {await withCheckedContinuation {resume=$0;entered?()}}
        try validate();return 0
    }
}

@MainActor private final class SelectiveExistingDetailRefresher:WorkoutExistingDetailRefreshing {
    let successID:UUID;var attempts=[UUID]()
    init(successID:UUID){self.successID=successID}
    func refresh(sourceID:UUID,ownerID:UUID,validate:@escaping () throws -> Void,loadInput:@escaping () async throws -> WorkoutSharedDetailInput) async throws -> Int {
        attempts.append(sourceID);try validate()
        if sourceID != successID {throw URLError(.timedOut)}
        return 1
    }
}

private final class PassiveChangeCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Notification] = []
    func append(_ note: Notification) { lock.lock(); values.append(note); lock.unlock() }
    var notes: [Notification] { lock.lock(); defer { lock.unlock() }; return values }
}
