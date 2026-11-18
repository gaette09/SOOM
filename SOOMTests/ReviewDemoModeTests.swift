import Foundation
import SwiftData
import XCTest
@testable import SOOM

@MainActor
final class ReviewDemoModeTests: XCTestCase {
    func testExplicitDemoUsesDisposableHealthDataAndPreservesGuestHistory() async throws {
        let guest = try HealthAccountStorageController(inMemory: true,
            monitorNetwork: false, automaticallySync: false)
        let guestContainer = guest.container
        let guestStore = SwiftDataUnifiedWorkoutStore(modelContext: guestContainer.mainContext)
        let existingWorkout = makeGuestWorkout()
        try await guestStore.saveWorkout(existingWorkout)
        let originalSession = AuthSessionStore.shared.loadSession()
        XCTAssertFalse(ReviewDemoMode.isActive)

        let runtime = try startDemo()
        defer { ReviewDemoController.shared.exit() }
        XCTAssertTrue(ReviewDemoMode.isActive)
        XCTAssertEqual(runtime.auth.session.currentUser?.id, ReviewDemoMode.userID)
        XCTAssertEqual(runtime.storage.userID, ReviewDemoMode.userID)
        XCTAssertFalse(runtime.storage.cloudConsentGranted)
        XCTAssertFalse(runtime.storage.isSyncing)
        XCTAssertTrue(runtime.storage.container.configurations.allSatisfy(\.isStoredInMemoryOnly))
        XCTAssertFalse(runtime.storage.container === guestContainer)
        let context = runtime.storage.container.mainContext
        let store = SwiftDataUnifiedWorkoutStore(modelContext: context)
        let samples = try await store.fetchRecentWorkouts(days: 90)
        XCTAssertFalse(samples.isEmpty)
        XCTAssertEqual(Set(samples.map { $0.workoutType.rawValue }), ["running", "cycling", "swimming"])
        XCTAssertTrue(samples.allSatisfy { $0.source == .manual })
        XCTAssertFalse(samples.contains { $0.id == existingWorkout.id })
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<CheckInRecord>()), 0)
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<DailyRecoverySnapshotRecord>()), 0)

        let sample = try XCTUnwrap(samples.first)
        try await store.updateCompanions(id: sample.id, names: ["Demo reviewer"])
        let edited = try await store.fetchWorkout(id: sample.id)
        XCTAssertEqual(edited?.companionNames, ["Demo reviewer"])
        try await store.deleteWorkout(id: sample.id)
        let deleted = try await store.fetchWorkout(id: sample.id)
        XCTAssertNil(deleted)

        ReviewDemoController.shared.exit()
        XCTAssertFalse(ReviewDemoMode.isActive)
        XCTAssertNil(ReviewDemoController.shared.runtime)
        XCTAssertTrue(guest.container === guestContainer)
        XCTAssertNil(guest.userID)
        let preserved = try await guestStore.fetchRecentWorkouts(days: 90)
        XCTAssertEqual(preserved, [existingWorkout])
        XCTAssertEqual(AuthSessionStore.shared.loadSession(), originalSession)
    }

    func testMonthBoundarySeedIncludesTodayWorkoutAndLeavesTodayCheckInEmpty() throws {
        let calendar = Calendar.current
        // Match the app's local calendar on a month's first day, before the
        // usual 07:00 sample start, when a history-only seed looked empty.
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 1, hour: 5, minute: 30)))
        let today = try XCTUnwrap(calendar.dateInterval(of: .day, for: referenceDate))
        let currentMonth = try XCTUnwrap(calendar.dateInterval(of: .month, for: referenceDate))
        let storage = try HealthAccountStorageController(inMemory: true,
            monitorNetwork: false, automaticallySync: false)
        let context = storage.container.mainContext

        try ReviewDemoData.seed(in: context, referenceDate: referenceDate)

        let workouts = try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>())
        XCTAssertEqual(workouts.count, 18)
        XCTAssertGreaterThanOrEqual(workouts.filter { currentMonth.contains($0.startDate) }.count, 1,
            "The default calendar month must show a sample even on its first day.")
        XCTAssertEqual(workouts.filter { today.contains($0.startDate) }.count, 1)
        XCTAssertTrue(workouts.allSatisfy { $0.startDate <= referenceDate },
            "Opening demo before 07:00 must not give today's sample a future start.")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PersistedWorkoutRoute>()), 12)
        let checkIns = try context.fetch(FetchDescriptor<CheckInRecord>())
        XCTAssertEqual(checkIns.count, 14)
        XCTAssertEqual(checkIns.filter { today.contains($0.date) }.count, 0,
            "Today's check-in stays empty so the reviewer can submit it.")
    }

    func testSampleImportProducesReadableWorkoutRouteAndTelemetry() async throws {
        let runtime = try startDemo()
        defer { ReviewDemoController.shared.exit() }
        let context = runtime.storage.container.mainContext
        let store = SwiftDataUnifiedWorkoutStore(modelContext: context)
        let before = try await store.fetchRecentWorkouts(days: 90)
        let previousIDs = Set(before.map(\.id))

        try await ReviewDemoData.importSample(in: context)

        let after = try await store.fetchRecentWorkouts(days: 90)
        let imported = after.filter { !previousIDs.contains($0.id) }
        XCTAssertEqual(imported.count, 1)
        let workout = try XCTUnwrap(imported.first)
        XCTAssertEqual(workout.source, .manual)
        XCTAssertGreaterThan(workout.distanceMeters ?? 0, 0)
        let route = try await SwiftDataWorkoutRoutePersistenceStore(modelContext: context)
            .fetchRoute(workoutId: workout.id)
        XCTAssertFalse(try XCTUnwrap(route).coordinates.isEmpty)
        let telemetry = try XCTUnwrap(WorkoutTelemetryStore(modelContext: context).load(workoutID: workout.id))
        XCTAssertFalse(telemetry.samples.isEmpty)
        XCTAssertFalse(telemetry.splits.isEmpty)
        XCTAssertFalse(runtime.storage.cloudConsentGranted)
    }

    func testExitRestoresSelectedSettingsDraftsAndPreferenceKeys() async throws {
        let originalTraining = TrainingSettingsStore.shared
        let originalDrafts = FileFeedShareDraftStore.live
        let originalSection = UserDefaults.standard.object(forKey: "activityHubSelectedSection")
        let originalClubKey = LocalClubPersistence.accountKey
        let originalCheckInKey = MorningCheckInSkipStore.accountKey
        let suiteName = "ReviewDemoModeTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
        let training = TrainingSettingsStore(userDefaults: defaults)
        let drafts = FileFeedShareDraftStore(fileURL: directory.appendingPathComponent("drafts.json"))
        defer {
            ReviewDemoController.shared.exit()
            TrainingSettingsStore.useDemoScope(originalTraining)
            FileFeedShareDraftStore.useDemoScope(originalDrafts)
            LocalClubPersistence.accountKey = originalClubKey
            MorningCheckInSkipStore.accountKey = originalCheckInKey
            if let originalSection {
                UserDefaults.standard.set(originalSection, forKey: "activityHubSelectedSection")
            } else {
                UserDefaults.standard.removeObject(forKey: "activityHubSelectedSection")
            }
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        training.saveMaxHeartRate(201)
        let existingDraft = makeDraft(title: "Existing personal draft")
        try await drafts.saveDraft(existingDraft)
        TrainingSettingsStore.useDemoScope(training)
        FileFeedShareDraftStore.useDemoScope(drafts)
        UserDefaults.standard.set("history", forKey: "activityHubSelectedSection")
        let safetyViewer = CommunitySafetyStore.shared.viewerID

        let runtime = try startDemo()
        let demoScopeDirectory = runtime.storage.scopeDirectory
        let demoClubKey = LocalClubPersistence.accountKey
        let demoCheckInKey = MorningCheckInSkipStore.accountKey
        XCTAssertFalse(TrainingSettingsStore.shared === training)
        XCTAssertFalse(FileFeedShareDraftStore.live === drafts)
        XCTAssertNotEqual(demoClubKey, originalClubKey)
        XCTAssertNotEqual(demoCheckInKey, originalCheckInKey)
        TrainingSettingsStore.shared.saveMaxHeartRate(155)
        try await FileFeedShareDraftStore.live.saveDraft(makeDraft(title: "Disposable demo draft"))
        UserDefaults.standard.set("sample club", forKey: demoClubKey)
        UserDefaults.standard.set(Date(), forKey: demoCheckInKey)
        ReviewDemoController.shared.start()
        XCTAssertTrue(ReviewDemoController.shared.runtime === runtime)

        ReviewDemoController.shared.exit()
        ReviewDemoController.shared.exit()

        XCTAssertTrue(TrainingSettingsStore.shared === training)
        XCTAssertEqual(training.loadSettings().maxHeartRate, 201)
        XCTAssertTrue(FileFeedShareDraftStore.live === drafts)
        let preservedDrafts = try await FileFeedShareDraftStore.live.fetchDrafts()
        XCTAssertEqual(preservedDrafts, [existingDraft])
        XCTAssertEqual(LocalClubPersistence.accountKey, originalClubKey)
        XCTAssertEqual(MorningCheckInSkipStore.accountKey, originalCheckInKey)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "activityHubSelectedSection"), "history")
        XCTAssertNil(UserDefaults.standard.object(forKey: demoClubKey))
        XCTAssertNil(UserDefaults.standard.object(forKey: demoCheckInKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: demoScopeDirectory.path))
        XCTAssertEqual(CommunitySafetyStore.shared.viewerID, safetyViewer)
    }

    func testCommunityReactionsBookmarksAndCommentsAreMutable() async throws {
        _ = try startDemo()
        defer { ReviewDemoController.shared.exit() }
        let community = ReviewDemoCommunityStore.shared
        let before = try await community.fetchFeed(limit: 100)
        XCTAssertGreaterThan(Set(before.map(\.authorId)).count, 1)
        let post = try XCTUnwrap(before.first { $0.authorId != ReviewDemoMode.userID })
        XCTAssertFalse(post.viewerHasCheered)
        try await community.addReaction(postId: post.id, reactionType: "cheer")
        try await community.addReaction(postId: post.id, reactionType: "cheer")
        let cheered = try await community.fetchPost(id: post.id)
        XCTAssertTrue(try XCTUnwrap(cheered).viewerHasCheered)
        XCTAssertEqual(cheered?.reactions.count, post.reactions.count + 1)
        try await community.removeReaction(postId: post.id, reactionType: "cheer")
        let uncheered = try await community.fetchPost(id: post.id)
        XCTAssertFalse(try XCTUnwrap(uncheered).viewerHasCheered)
        XCTAssertEqual(uncheered?.reactions, post.reactions)

        try await community.addBookmark(postId: post.id)
        let saved = try await community.fetchSavedPosts()
        XCTAssertTrue(saved.contains { $0.id == post.id })
        try await community.removeBookmark(postId: post.id)
        let unsaved = try await community.fetchSavedPosts()
        XCTAssertFalse(unsaved.contains { $0.id == post.id })
        try await community.addComment(postId: post.id, body: "  Demo review comment  ")
        let commented = try await community.fetchPost(id: post.id)
        XCTAssertEqual(commented?.comments.count, post.comments.count + 1)
        XCTAssertEqual(commented?.comments.last?.body, "Demo review comment")
        XCTAssertEqual(commented?.comments.last?.authorId, ReviewDemoMode.userID)
        XCTAssertEqual(commented?.comments.last?.isViewerAuthor, true)
    }

    func testCommunityPublishingEditingAndDeletionRespectOwnership() async throws {
        _ = try startDemo()
        defer { ReviewDemoController.shared.exit() }
        let community = ReviewDemoCommunityStore.shared
        let draft = makeDraft(title: "Demo published workout")
        try await community.postPublicPost(draft, visibility: .publicPost)
        let published = try await community.fetchPost(id: draft.id)
        XCTAssertEqual(published?.authorId, ReviewDemoMode.userID)
        XCTAssertEqual(published?.sourceWorkoutId, draft.sourceWorkoutId)
        XCTAssertEqual(published?.visibility, .publicFeed)
        XCTAssertEqual(published?.isLocalDraft, false)
        try await community.editPost(id: draft.id, ownerID: ReviewDemoMode.userID,
            title: "Edited demo workout", description: "Updated demo story")
        try await community.setVisibility(postID: draft.id, ownerID: ReviewDemoMode.userID, visibility: .privatePost)
        let edited = try await community.fetchPost(id: draft.id)
        XCTAssertEqual(edited?.activityContext, "Edited demo workout")
        XCTAssertEqual(edited?.caption, "Updated demo story")
        XCTAssertEqual(edited?.visibility, .privateOnly)

        let feed = try await community.fetchFeed(limit: 100)
        let other = try XCTUnwrap(feed.first { $0.authorId != ReviewDemoMode.userID })
        do {
            try await community.deletePost(id: other.id, ownerID: ReviewDemoMode.userID)
            XCTFail("Demo users must not delete another author's post")
        } catch {
            XCTAssertEqual(error as? CommunitySafetyError, .invalidTarget)
        }
        let preserved = try await community.fetchPost(id: other.id)
        XCTAssertNotNil(preserved)
        try await community.deletePost(id: draft.id, ownerID: ReviewDemoMode.userID)
        let deleted = try await community.fetchPost(id: draft.id)
        XCTAssertNil(deleted)
    }

    func testBlockingHidesOnlySelectedAuthorAndUnblockingRestoresFeed() async throws {
        _ = try startDemo()
        defer { ReviewDemoController.shared.exit() }
        let community = ReviewDemoCommunityStore.shared
        let before = try await community.fetchFeed(limit: 100)
        let other = try XCTUnwrap(before.first { $0.authorId != ReviewDemoMode.userID })
        try await community.addBookmark(postId: other.id)
        try await community.block(userID: other.authorId)
        let blocked = try await community.fetchFeed(limit: 100)
        XCTAssertEqual(Set(blocked.map(\.id)), Set(before.filter { $0.authorId != other.authorId }.map(\.id)))
        XCTAssertTrue(blocked.contains { $0.authorId == ReviewDemoMode.userID })
        let saved = try await community.fetchSavedPosts()
        XCTAssertFalse(saved.contains { $0.id == other.id })
        let hidden = try await community.fetchPost(id: other.id)
        XCTAssertNil(hidden)
        try await community.unblock(userID: other.authorId)
        let restored = try await community.fetchFeed(limit: 100)
        XCTAssertEqual(Set(restored.map(\.id)), Set(before.map(\.id)))
    }

    func testExitRejectsStaleCommunityActionsAndRestartResetsChanges() async throws {
        let first = try startDemo()
        defer { ReviewDemoController.shared.exit() }
        let community = ReviewDemoCommunityStore.shared
        let draft = makeDraft(title: "Session-only post")
        try await community.postPublicPost(draft, visibility: .publicPost)
        try await community.addBookmark(postId: draft.id)
        ReviewDemoController.shared.exit()
        XCTAssertNil(community.sessionUserID)
        do {
            try await community.addComment(postId: draft.id, body: "Late action")
            XCTFail("An exited demo session must reject delayed writes")
        } catch {
            XCTAssertEqual(error as? CommunitySafetyError, .accountChanged)
        }
        let next = try startDemo()
        XCTAssertNotEqual(next.id, first.id)
        let feed = try await community.fetchFeed(limit: 100)
        XCTAssertFalse(feed.contains { $0.id == draft.id })
        let saved = try await community.fetchSavedPosts()
        XCTAssertFalse(saved.contains { $0.id == draft.id })
        let drafts = try await FileFeedShareDraftStore.live.fetchDrafts()
        XCTAssertTrue(drafts.isEmpty)
    }

    private func startDemo(file: StaticString = #filePath, line: UInt = #line) throws -> ReviewDemoRuntime {
        ReviewDemoController.shared.start()
        XCTAssertNil(ReviewDemoController.shared.errorMessage, file: file, line: line)
        return try XCTUnwrap(ReviewDemoController.shared.runtime, file: file, line: line)
    }

    private func makeDraft(title: String) -> FeedShareDraft {
        FeedShareDraft(id: UUID(), sourceWorkoutId: UUID(), sport: .running,
            title: title, body: "Sample activity", distanceMeters: 5_000,
            durationSeconds: 1_800, averagePaceSecondsPerKm: 360,
            routePreviewPayload: nil, photoPlaceholders: [], tags: [],
            visibility: .draft, createdAt: Date())
    }

    private func makeGuestWorkout() -> UnifiedWorkout {
        let date = Date().addingTimeInterval(-3_600)
        return UnifiedWorkout(id: UUID(), externalId: nil, source: .manual, workoutType: .running,
            startDate: date, endDate: date.addingTimeInterval(1_800), durationSeconds: 1_800,
            distanceMeters: 4_000, activeEnergyKcal: 250, averageHeartRate: nil,
            maxHeartRate: nil, averageSpeedMetersPerSecond: nil, elevationGainMeters: nil,
            dataQuality: .partial, createdAt: date, updatedAt: date,
            userTitle: "Existing personal workout")
    }
}
