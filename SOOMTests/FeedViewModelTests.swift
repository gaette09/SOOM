import Combine
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import SOOM

@MainActor
final class FeedViewModelTests: XCTestCase {
    func testProductionReadinessObserverDeliversSwiftUIAndUIKitEventsOnce() async throws {
        let state = Feed66ReadinessHarnessState()
        let host = UIHostingController(rootView: Feed66ReadinessHarness(state: state))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.loadViewIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        state.retry.deferUntilReady()
        state.ready = true
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(state.consumed, 1, "Real SwiftUI onChange must deliver readiness")
        for _ in 0..<5 { NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil) }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(state.consumed, 1, "Duplicate lifecycle notifications must not reschedule")
        state.retry.deferUntilReady()
        // The UIKit event directly rechecks even without another observed-state change.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(state.consumed, 2)
        state.ready = false
        try await Task.sleep(for: .milliseconds(50))
        state.retry.deferUntilReady()
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(state.consumed, 2, "Not-ready is never granted by notification delivery")
    }

    func testInitialAuthorizationDeferredWhileProductionPipelineCompletesSummary() async throws {
        let storage = try HealthAccountStorageController(inMemory: true, monitorNetwork: false, automaticallySync: false)
        let owner = UUID()
        try storage.switchAccount(userID: owner)
        let context = storage.container.mainContext
        let record = UnifiedWorkoutRecord(sourceRaw: UnifiedDataSource.soomLocal.rawValue,
            workoutTypeRaw: UnifiedWorkoutType.running.rawValue, startDate: Date(), endDate: Date(),
            durationSeconds: 600, dataQualityRaw: UnifiedDataQuality.complete.rawValue)
        context.insert(record); try context.save()
        var projectionCalls = 0
        let project: @MainActor ([FeedItem]) -> [FeedItem] = { items in
            projectionCalls += 1
            guard let snapshot = try? OwnerWorkoutFeedProjection.read(context: context, storage: storage,
                expectedOwnerID: owner, expectedScopeID: storage.scopeID) else { return [] }
            return snapshot.merging(serverItems: items, currentOwnerID: owner, currentScopeID: storage.scopeID)
        }
        let source = FeedDataSource(remoteRepository: Feed66EmptyHomeRepository(),
            ownerProjection: project, homeContractAvailable: true)
        let vm = FeedViewModel(feedLoader: source,
            weeklyProgressProvider: StubWeeklyProgressProvider(result: .success(makeProgress(workoutCount: 1))),
            recoveryPreviewProvider: StubRecoveryPreviewProvider(result: .failure(StubError.failed)),
            streakDatesProvider: StubStreakDatesProvider(result: .success([])),
            initialAudience: .home, normalizeItems: project)
        var ready = false
        var batchCalls = 0
        var retry = FeedInitialAuthorizationRetry()
        await vm.load(awaitSupplementaryContent: true, onPrimaryContentReady: {
            if retry.authorizeNowOrDefer(ready: ready) { batchCalls += 1 }
        })
        XCTAssertGreaterThanOrEqual(projectionCalls, 2, "Real source owner projection and VM normalization must both execute")
        XCTAssertEqual(vm.readModel.items.count, 1)
        XCTAssertNotNil(vm.readModel.weeklySnapshot, "Summary can finish despite missing primary authority")
        XCTAssertEqual(batchCalls, 0, "Build65-shaped callback skipped auth while context was absent")
        ready = true
        XCTAssertEqual(batchCalls, 0, "Readiness alone did not run any old callback")
        if retry.consumeIfReady(ready) { batchCalls += 1 }
        for _ in 0..<20 { if retry.consumeIfReady(ready) { batchCalls += 1 } }
        XCTAssertEqual(batchCalls, 1, "The new scheduling latch consumes a ready transition once")
        // Scheduling does not confer authority or manufacture server grants.
        XCTAssertTrue(vm.readModel.items.allSatisfy(\.isLocalDraft))
        print("FEED66_PIPELINE: realSwiftData/sourceProjection/normalize/summary PASS; original-style ready-only calls=0; retry-consumed=1; not a SwiftUI lifecycle or server-grant test")
    }

    func testInitialAuthorizationRetryPermanentDenialDoesNotPoll() {
        var retry = FeedInitialAuthorizationRetry()
        retry.deferUntilReady()
        for _ in 0..<100 { XCTAssertFalse(retry.consumeIfReady(false)) }
        XCTAssertTrue(retry.pending)
        retry.invalidate()
        XCTAssertFalse(retry.consumeIfReady(true))
    }

    func testInitialAuthorizationRetryAccountBoundaryClearsDeferredWork() {
        var retry = FeedInitialAuthorizationRetry()
        retry.deferUntilReady()
        retry.invalidate() // same call made by suspend/safety invalidation
        XCTAssertFalse(retry.consumeIfReady(true), "New account readiness cannot consume old deferred work")
        retry.deferUntilReady()
        XCTAssertTrue(retry.consumeIfReady(true))
        XCTAssertFalse(retry.consumeIfReady(true))
    }

    func testReturnPerformanceIsBoundedNumericAndAccountScoped() {
        var metrics = SOOMFeedReturnPerformance()
        for _ in 0..<100 { metrics.record(path: .batch, seconds: 0.125, hits: 4, misses: 0, evictions: 0, bytes: 2048) }
        XCTAssertEqual(metrics.samples.count, 64)
        XCTAssertEqual(metrics.samples.last?.milliseconds, 125)
        XCTAssertEqual(metrics.samples.last?.residentKiB, 2)
        metrics.record(path: .failedBatch, seconds: .nan, hits: 0, misses: 0, evictions: 0, bytes: 0)
        XCTAssertEqual(metrics.samples.count, 64)
        metrics = SOOMFeedReturnPerformance()
        XCTAssertTrue(metrics.samples.isEmpty)
    }

    func testHomeNotificationTargetDoesNotEnterTimeline() async {
        let items = FeedMockData.items
        let loader = StubFeedLoader(items: items)
        let vm = makeViewModel(feedLoader: loader)
        await vm.selectAudience(.home)
        let before = vm.readModel.items.map(\.id)
        if let item = items.last { vm.includeNotificationItem(item) }
        XCTAssertEqual(vm.readModel.items.map(\.id), before)
        XCTAssertEqual(vm.audience, .home)
    }

    func testNotificationTargetUsesFreshLookupAndDoesNotAdvancePagination() async {
        let items = (0..<19).map { index in
            FeedItem(id: UUID(), authorName: "합성 운동", authorHandle: nil,
                createdAt: Date(timeIntervalSince1970: 1_900_000_000 - Double(index)),
                itemType: .workoutSession, visibility: .publicFeed,
                cardData: FeedMockData.items[0].cardData, caption: nil, activityContext: "합성")
        }
        let loader = StubFeedLoader(items: items)
        let vm = makeViewModel(feedLoader: loader)
        await vm.load()
        XCTAssertEqual(vm.readModel.items.count, 8)
        let target = await vm.resolveFeedItem(postId: items[18].id)
        XCTAssertEqual(target?.id, items[18].id)
        if let target { vm.includeNotificationItem(target) }
        XCTAssertEqual(loader.loadedPostIDs, [items[18].id])
        XCTAssertEqual(loader.listLoadCount, 1)
        await vm.loadMore()
        XCTAssertEqual(Set(vm.readModel.items.map(\.id)), Set((Array(items.prefix(16)) + [items[18]]).map(\.id)))
        loader.postItems = []
        let denied = await vm.resolveFeedItem(postId: items[18].id)
        XCTAssertNil(denied, "Previously loaded card must not bypass the current server lookup")
    }

    func testFeedLoadsEightCardsThenAppendsNextPageOnDemand() async {
        let items = (0..<11).map { index in
            FeedItem(id: UUID(), authorName: "러너 \(index)", authorHandle: nil,
                createdAt: Date(timeIntervalSince1970: 1_900_000_000 - Double(index)),
                itemType: .workoutSession, visibility: .publicFeed,
                cardData: FeedMockData.items[0].cardData, caption: nil,
                activityContext: "러닝 \(index)")
        }
        let viewModel = makeViewModel(feedLoader: StubFeedLoader(items: items))

        await viewModel.load()
        XCTAssertEqual(viewModel.readModel.items.count, 8)
        XCTAssertTrue(viewModel.readModel.hasMore)

        await viewModel.loadMore()
        XCTAssertEqual(viewModel.readModel.items.map(\.id), items.map(\.id))
        XCTAssertFalse(viewModel.readModel.hasMore)
        XCTAssertFalse(viewModel.readModel.isLoadingMore)
    }

    func testRefreshingAfterPagingKeepsTheOlderCardAvailableForReturnNavigation() async {
        let items = (0..<19).map { index in
            FeedItem(id: UUID(), authorName: "러너 \(index)", authorHandle: nil,
                createdAt: Date(timeIntervalSince1970: 1_900_000_000 - Double(index)),
                itemType: .workoutSession, visibility: .publicFeed,
                cardData: FeedMockData.items[0].cardData, caption: nil,
                activityContext: "러닝 \(index)")
        }
        let viewModel = makeViewModel(feedLoader: StubFeedLoader(items: items))
        await viewModel.load()
        await viewModel.loadMore()
        let previouslyViewedID = items[12].id
        XCTAssertTrue(viewModel.readModel.items.contains { $0.id == previouslyViewedID })

        await viewModel.load()

        XCTAssertEqual(viewModel.readModel.items.count, 16)
        XCTAssertTrue(viewModel.readModel.items.contains { $0.id == previouslyViewedID })
        XCTAssertTrue(viewModel.readModel.hasMore)
        await viewModel.loadMore()
        XCTAssertEqual(viewModel.readModel.items.map(\.id), items.map(\.id))
    }

    func testTransientFeedFailureRetriesWithoutShowingAnErrorCard() async {
        let loader = StubFeedLoader(items: Array(FeedMockData.items.prefix(2)))
        loader.transientFailuresRemaining = 1
        let viewModel = makeViewModel(feedLoader: loader)

        await viewModel.load()

        XCTAssertEqual(viewModel.readModel.items.count, 2)
        XCTAssertNil(viewModel.readModel.loadFailure)
        XCTAssertEqual(loader.listLoadCount, 2)
    }

    func testFailedPullRefreshKeepsPreviouslyLoadedCardsAndCanRecover() async {
        let items = (0..<19).map { index in
            FeedItem(id: UUID(), authorName: "러너 \(index)", authorHandle: nil,
                createdAt: Date(timeIntervalSince1970: 1_900_000_000 - Double(index)),
                itemType: .workoutSession, visibility: .publicFeed,
                cardData: FeedMockData.items[0].cardData, caption: nil,
                activityContext: "러닝 \(index)")
        }
        let loader = StubFeedLoader(items: items)
        let viewModel = makeViewModel(feedLoader: loader)
        await viewModel.load()
        await viewModel.loadMore()
        let visibleIDs = viewModel.readModel.items.map(\.id)

        loader.failure = .remoteFailed
        await viewModel.load()
        XCTAssertEqual(viewModel.readModel.items.map(\.id), visibleIDs)
        XCTAssertEqual(viewModel.readModel.loadFailure, .remoteFailed)
        XCTAssertTrue(viewModel.readModel.hasMore)

        loader.failure = nil
        await viewModel.load()
        XCTAssertEqual(viewModel.readModel.items.map(\.id), visibleIDs)
        XCTAssertNil(viewModel.readModel.loadFailure)
        await viewModel.loadMore()
        XCTAssertEqual(viewModel.readModel.items.map(\.id), items.map(\.id))
    }

    func testOlderPageCanLoadAutomaticallyAfterPreviousFailure() async {
        let items = (0..<11).map { index in
            FeedItem(id: UUID(), authorName: "러너 \(index)", authorHandle: nil,
                createdAt: Date(timeIntervalSince1970: 1_900_000_000 - Double(index)),
                itemType: .workoutSession, visibility: .publicFeed,
                cardData: FeedMockData.items[0].cardData, caption: nil,
                activityContext: "러닝 \(index)")
        }
        let loader = StubFeedLoader(items: items)
        let viewModel = makeViewModel(feedLoader: loader)
        await viewModel.load()

        loader.failure = .remoteFailed
        await viewModel.loadMore()
        XCTAssertEqual(viewModel.readModel.items.count, 8)
        XCTAssertEqual(viewModel.readModel.loadMoreFailure, .remoteFailed)

        loader.failure = nil
        await viewModel.loadMore()
        XCTAssertEqual(viewModel.readModel.items.map(\.id), items.map(\.id))
        XCTAssertNil(viewModel.readModel.loadMoreFailure)
        XCTAssertFalse(viewModel.readModel.hasMore)
    }

    func testPrimaryLaneAllowsNextPageAndAuthorizationWhileSummaryIsHeld() async {
        let items = (0..<16).map { index in
            FeedItem(id: UUID(), authorName: "Synthetic \(index)", authorHandle: nil,
                createdAt: Date(timeIntervalSince1970: 1_900_000_000 - Double(index)),
                itemType: .workoutSession, visibility: .publicFeed,
                cardData: FeedMockData.items[0].cardData, caption: nil, activityContext: "Synthetic")
        }
        let loader = StubFeedLoader(items: items), weekly = SuspendedWeeklyProgressProvider()
        let model = FeedViewModel(feedLoader: loader, weeklyProgressProvider: weekly,
            recoveryPreviewProvider: StubRecoveryPreviewProvider(result: .failure(StubError.failed)),
            streakDatesProvider: StubStreakDatesProvider(result: .success([])))
        let coordinator = SOOMFeedRefreshCoordinator()
        var primaryAuthorized = false, nextAuthorized = false
        await coordinator.refresh(requiresFollowUp: false) {
            await model.load(awaitSupplementaryContent: false, onPrimaryContentReady: { primaryAuthorized = true })
        }
        XCTAssertTrue(primaryAuthorized)
        XCTAssertFalse(coordinator.isRefreshing, "Optional summaries cannot retain the authorization owner")
        XCTAssertFalse(model.readModel.isLoading)
        XCTAssertEqual(model.readModel.items.count, 8)
        await model.loadMore()
        await coordinator.refresh(requiresFollowUp: true) { nextAuthorized = true }
        XCTAssertTrue(nextAuthorized)
        XCTAssertEqual(model.readModel.items.count, 16, "Next page must finish before releasing the slow summary")
        let ids = model.readModel.items.map(\.id)
        await weekly.resume()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(model.readModel.items.map(\.id), ids, "Late optional fields cannot overwrite the newer page")
    }

    func testFirstPageIsVisibleBeforeWeeklySummaryFinishes() async {
        let item = FeedMockData.items[0]
        let pageVisible = expectation(description: "first feed page visible")
        let weeklyProvider = SuspendedWeeklyProgressProvider()
        let viewModel = FeedViewModel(
            feedLoader: StubFeedLoader(items: [item]),
            weeklyProgressProvider: weeklyProvider,
            recoveryPreviewProvider: StubRecoveryPreviewProvider(result: .failure(StubError.failed)),
            streakDatesProvider: StubStreakDatesProvider(result: .success([]))
        )
        var observed = false
        let observation = viewModel.$readModel.sink { model in
            if !observed, model.items.contains(where: { $0.id == item.id }) {
                observed = true
                pageVisible.fulfill()
            }
        }
        let authorized = expectation(description: "Primary authorization does not await optional summaries")
        let loading = Task { await viewModel.load(onPrimaryContentReady: {
            XCTAssertTrue(viewModel.readModel.items.contains(where: { $0.id == item.id }))
            authorized.fulfill()
        }) }
        await fulfillment(of: [pageVisible, authorized], timeout: 5)
        XCTAssertTrue(viewModel.readModel.isLoading)
        await weeklyProvider.resume()
        await loading.value
        XCTAssertFalse(viewModel.readModel.isLoading)
        withExtendedLifetime(observation) {}
    }

    func testLoadBuildsProductionReadModelFromProviders() async {
        let item = FeedMockData.items[0]
        let progress = makeProgress(workoutCount: 3)
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let viewModel = FeedViewModel(
            feedLoader: StubFeedLoader(items: [item]),
            weeklyProgressProvider: StubWeeklyProgressProvider(result: .success(progress)),
            recoveryPreviewProvider: StubRecoveryPreviewProvider(result: .success(
                UnifiedWorkoutRecoveryPreviewResult(summary: .mockToday, usedWorkoutCount: 3)
            )),
            streakDatesProvider: StubStreakDatesProvider(result: .success([referenceDate])),
            now: { referenceDate }
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.readModel.items, [item])
        XCTAssertEqual(viewModel.readModel.weeklySnapshot?.progress, progress)
        XCTAssertEqual(viewModel.readModel.weeklySnapshot?.sportSummary, "이번 주 3회 움직였어요")
        XCTAssertEqual(viewModel.readModel.recoveryInsight?.score, RecoverySummary.mockToday.score)
        XCTAssertEqual(viewModel.readModel.streak.weekCount, 1)
        XCTAssertEqual(viewModel.readModel.streak.activityCount, 1)
        XCTAssertFalse(viewModel.readModel.isLoading)
    }

    func testEmptyRecoveryPreviewNeverPresentsDefaultScoreOrCoachingAdvice() {
        let summary = RecoveryCalculator().calculateSummary(from: [])
        let insight = FeedRecoveryInsight(preview: UnifiedWorkoutRecoveryPreviewResult(summary: summary, usedWorkoutCount: 0))
        XCTAssertNil(insight.score)
        XCTAssertEqual(insight.status, "데이터 부족")
        XCTAssertNil(insight.coachMessage)
        XCTAssertFalse(insight.accessibilityValue.contains("72"))
        XCTAssertFalse(insight.accessibilityValue.contains("점"))
        XCTAssertTrue(insight.recommendation.contains("운동 기록"))
    }

    func testRecoveryPreviewWithInputsPreservesCalculatedPresentation() {
        let summary = RecoverySummary.mockToday
        let insight = FeedRecoveryInsight(preview: UnifiedWorkoutRecoveryPreviewResult(summary: summary, usedWorkoutCount: 1))
        XCTAssertEqual(insight.score, summary.score)
        XCTAssertEqual(insight.status, summary.status)
        XCTAssertEqual(insight.recommendation, summary.recommendation)
        XCTAssertEqual(insight.coachMessage, summary.coachMessage.message)
        XCTAssertTrue(insight.accessibilityValue.contains("\(summary.score)점"))
    }

    func testRecoveryReloadClearsPreviouslyVisibleScoreWhenInputsDisappear() async {
        let provider = MutableRecoveryPreviewProvider(result: .success(
            UnifiedWorkoutRecoveryPreviewResult(summary: .mockToday, usedWorkoutCount: 1)
        ))
        let viewModel = FeedViewModel(
            feedLoader: StubFeedLoader(items: []),
            weeklyProgressProvider: StubWeeklyProgressProvider(result: .failure(StubError.failed)),
            recoveryPreviewProvider: provider,
            streakDatesProvider: StubStreakDatesProvider(result: .success([]))
        )
        await viewModel.load()
        XCTAssertEqual(viewModel.readModel.recoveryInsight?.score, RecoverySummary.mockToday.score)

        provider.result = .success(UnifiedWorkoutRecoveryPreviewResult(
            summary: RecoveryCalculator().calculateSummary(from: []), usedWorkoutCount: 0
        ))
        await viewModel.load()
        XCTAssertNotNil(viewModel.readModel.recoveryInsight)
        XCTAssertNil(viewModel.readModel.recoveryInsight?.score)

        provider.result = .failure(StubError.failed)
        await viewModel.load()
        XCTAssertNil(viewModel.readModel.recoveryInsight)

        provider.result = .success(UnifiedWorkoutRecoveryPreviewResult(summary: .mockToday, usedWorkoutCount: 1))
        await viewModel.load()
        XCTAssertEqual(viewModel.readModel.recoveryInsight?.score, RecoverySummary.mockToday.score)
    }

    func testLoadKeepsSocialFeedWhenWorkoutSummariesFail() async {
        let item = FeedMockData.items[0]
        let viewModel = FeedViewModel(
            feedLoader: StubFeedLoader(items: [item]),
            weeklyProgressProvider: StubWeeklyProgressProvider(result: .failure(StubError.failed)),
            recoveryPreviewProvider: StubRecoveryPreviewProvider(result: .failure(StubError.failed)),
            streakDatesProvider: StubStreakDatesProvider(result: .failure(StubError.failed))
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.readModel.items, [item])
        XCTAssertNil(viewModel.readModel.weeklySnapshot)
        XCTAssertNil(viewModel.readModel.recoveryInsight)
        XCTAssertEqual(viewModel.readModel.streak.weekCount, 0)
        XCTAssertFalse(viewModel.readModel.isLoading)
    }

    func testLoadPublishesFailureAlongsideAvailableLocalDrafts() async {
        let draft = FeedItem(
            id: UUID(),
            authorName: "나",
            authorHandle: nil,
            isLocalDraft: true,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            itemType: .workoutSession,
            visibility: .privateOnly,
            cardData: FeedMockData.items[0].cardData,
            caption: nil,
            activityContext: "오늘의 라이딩"
        )
        let loader = StubFeedLoader(items: [draft], failure: .remoteFailed)
        let viewModel = makeViewModel(feedLoader: loader)

        await viewModel.load()

        XCTAssertEqual(viewModel.readModel.items, [draft])
        XCTAssertEqual(viewModel.readModel.loadFailure, .remoteFailed)
        XCTAssertFalse(viewModel.readModel.isLoading)
    }

    func testRetryReplacesFailedStateAndClearsErrorOnSuccess() async {
        let loader = StubFeedLoader(items: [], failure: .remoteFailed)
        let viewModel = makeViewModel(feedLoader: loader)
        await viewModel.load()
        XCTAssertEqual(viewModel.readModel.loadFailure, .remoteFailed)

        let post = FeedMockData.items[0]
        loader.items = [post]
        loader.failure = nil
        await viewModel.load()

        XCTAssertEqual(viewModel.readModel.items, [post])
        XCTAssertNil(viewModel.readModel.loadFailure)
        XCTAssertFalse(viewModel.readModel.isLoading)
    }

    func testSuccessfulEmptyRetryClearsFailureWithoutSamplePosts() async {
        let loader = StubFeedLoader(items: [], failure: .remoteFailed)
        let viewModel = makeViewModel(feedLoader: loader)
        await viewModel.load()

        loader.failure = nil
        await viewModel.load()

        XCTAssertTrue(viewModel.readModel.items.isEmpty)
        XCTAssertNil(viewModel.readModel.loadFailure)
        XCTAssertFalse(viewModel.readModel.isLoading)
    }

    func testReadOnlyLegacyReceiptCannotCreateOrRemoveReaction() async {
        for cheered in [false, true] {
            var item = FeedMockData.items[0]
            item.viewerHasCheered = cheered
            item.previewLegacyReadContext = .init(viewerID: UUID(), generation: 0, safetyRevision: 0)
            let poster = StubReactionPoster()
            let model = makeViewModel(feedLoader: StubFeedLoader(items: [item]), reactionPoster: poster)
            await model.load()
            await model.toggleCheer(for: item)
            XCTAssertTrue(poster.added.isEmpty)
            XCTAssertTrue(poster.removed.isEmpty)
        }
    }

    func testToggleCheerAddsReactionAndUpdatesReadModelOptimistically() async {
        let item = FeedMockData.items[0]
        XCTAssertFalse(item.viewerHasCheered)
        let reactionPoster = StubReactionPoster()
        let loader = StubFeedLoader(items: [item])
        var confirmed = item
        confirmed.viewerHasCheered = true
        loader.postItems = [confirmed]
        let viewModel = makeViewModel(feedLoader: loader, reactionPoster: reactionPoster)
        await viewModel.load()

        await viewModel.toggleCheer(for: item)

        XCTAssertEqual(reactionPoster.added, [FeedReactionCall(postId: item.id, reactionType: "cheer")])
        XCTAssertTrue(reactionPoster.removed.isEmpty)
        XCTAssertEqual(viewModel.readModel.items.first?.viewerHasCheered, true)
    }

    func testToggleCheerRemovesReactionWhenAlreadyCheered() async {
        var item = FeedMockData.items[0]
        item.viewerHasCheered = true
        let reactionPoster = StubReactionPoster()
        let loader = StubFeedLoader(items: [item])
        var confirmed = item
        confirmed.viewerHasCheered = false
        loader.postItems = [confirmed]
        let viewModel = makeViewModel(feedLoader: loader, reactionPoster: reactionPoster)
        await viewModel.load()

        await viewModel.toggleCheer(for: item)

        XCTAssertEqual(reactionPoster.removed, [FeedReactionCall(postId: item.id, reactionType: "cheer")])
        XCTAssertEqual(viewModel.readModel.items.first?.viewerHasCheered, false)
    }

    func testCheerConfirmationRefreshesAvatarAndCountWithoutResettingLoadedPages() async {
        let owner = UUID(), viewer = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let items = (0..<11).map { offset in
            FeedPostBundleDTO(post: FeedPostDTO(id: UUID(), userId: owner, sport: .running, title: "Run \(offset)",
                createdAt: start.addingTimeInterval(-Double(offset) * 86_400))).makeFeedItem()
        }
        let loader = StubFeedLoader(items: items)
        let profile = FeedProfileDTO(id: viewer, displayName: "응원자", handle: "runner", avatarPath: "avatar.jpg")
        let reaction = FeedReaction(id: UUID(), symbol: "👏", label: "응원", authorId: viewer,
            createdAt: start, profile: profile)
        var confirmed = items[8]
        confirmed.viewerHasCheered = true
        confirmed.reactions = [reaction]
        loader.postItems = [confirmed]
        let viewModel = makeViewModel(feedLoader: loader, reactionPoster: StubReactionPoster())
        await viewModel.load()
        await viewModel.loadMore()
        let before = viewModel.readModel.items.map(\.id)
        let listLoads = loader.listLoadCount

        await viewModel.toggleCheer(for: items[8])

        let updated = viewModel.readModel.items.first { $0.id == confirmed.id }
        XCTAssertEqual(updated?.viewerHasCheered, true)
        XCTAssertEqual(updated?.orderedCheers.count, 1)
        XCTAssertEqual(updated?.orderedCheers.first?.profile, profile)
        XCTAssertEqual(viewModel.readModel.items.map(\.id), before)
        XCTAssertEqual(viewModel.readModel.items.count, 11)
        XCTAssertFalse(viewModel.readModel.hasMore)
        XCTAssertEqual(loader.listLoadCount, listLoads)
        XCTAssertEqual(loader.loadedPostIDs, [confirmed.id])
    }

    func testToggleCheerRevertsOptimisticUpdateOnFailure() async {
        let item = FeedMockData.items[0]
        let reactionPoster = StubReactionPoster(error: StubError.failed)
        let viewModel = makeViewModel(items: [item], reactionPoster: reactionPoster)
        await viewModel.load()

        await viewModel.toggleCheer(for: item)

        XCTAssertEqual(viewModel.readModel.items.first?.viewerHasCheered, false)
    }

    func testToggleSaveAddsBookmarkAndUpdatesReadModelOptimistically() async {
        let item = FeedMockData.items[0]
        XCTAssertFalse(item.viewerHasSaved)
        let bookmarkPoster = StubBookmarkPoster()
        let viewModel = makeViewModel(items: [item], bookmarkPoster: bookmarkPoster)
        await viewModel.load()

        await viewModel.toggleSave(for: item)

        XCTAssertEqual(bookmarkPoster.addedPostIds, [item.id])
        XCTAssertTrue(bookmarkPoster.removedPostIds.isEmpty)
        XCTAssertEqual(viewModel.readModel.items.first?.viewerHasSaved, true)
    }

    func testToggleSaveRemovesBookmarkWhenAlreadySaved() async {
        var item = FeedMockData.items[0]
        item.viewerHasSaved = true
        let bookmarkPoster = StubBookmarkPoster()
        let viewModel = makeViewModel(items: [item], bookmarkPoster: bookmarkPoster)
        await viewModel.load()

        await viewModel.toggleSave(for: item)

        XCTAssertEqual(bookmarkPoster.removedPostIds, [item.id])
        XCTAssertEqual(viewModel.readModel.items.first?.viewerHasSaved, false)
    }

    func testToggleSaveRevertsOptimisticUpdateOnFailure() async {
        let item = FeedMockData.items[0]
        let bookmarkPoster = StubBookmarkPoster(error: StubError.failed)
        let viewModel = makeViewModel(items: [item], bookmarkPoster: bookmarkPoster)
        await viewModel.load()

        await viewModel.toggleSave(for: item)

        XCTAssertEqual(viewModel.readModel.items.first?.viewerHasSaved, false)
    }

    func testToggleCheerIsNoOpForLocalDraft() async {
        var item = FeedMockData.items[0]
        item = FeedItem(
            id: item.id,
            authorName: item.authorName,
            authorHandle: item.authorHandle,
            isLocalDraft: true,
            createdAt: item.createdAt,
            itemType: item.itemType,
            visibility: item.visibility,
            cardData: item.cardData,
            caption: item.caption,
            activityContext: item.activityContext
        )
        let reactionPoster = StubReactionPoster()
        let viewModel = makeViewModel(items: [item], reactionPoster: reactionPoster)
        await viewModel.load()

        await viewModel.toggleCheer(for: item)

        XCTAssertTrue(reactionPoster.added.isEmpty)
        XCTAssertTrue(reactionPoster.removed.isEmpty)
    }

    func testPostCommentCallsPosterThenReloads() async throws {
        let item = FeedMockData.items[0]
        let commentPoster = StubCommentPoster()
        let viewModel = makeViewModel(items: [item], commentPoster: commentPoster)
        await viewModel.load()

        try await viewModel.postComment("좋은 흐름이에요!", on: item)

        XCTAssertEqual(commentPoster.posted, [FeedCommentCall(postId: item.id, body: "좋은 흐름이에요!")])
    }

    func testCommentDuringRefreshQueuesAnotherLoadBeforeOwnerReturns() async throws {
        let item = FeedMockData.items[0]
        let comment = FeedComment(
            id: UUID(),
            authorId: UUID(),
            body: "좋은 흐름이에요!",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            isViewerAuthor: true
        )
        let updatedItem = FeedItem(
            id: item.id,
            authorName: item.authorName,
            authorHandle: item.authorHandle,
            authorId: item.authorId,
            createdAt: item.createdAt,
            itemType: item.itemType,
            visibility: item.visibility,
            cardData: item.cardData,
            caption: item.caption,
            activityContext: item.activityContext,
            comments: item.comments + [comment]
        )
        let firstLoadStarted = expectation(description: "Refresh captured the pre-comment feed")
        let loader = SuspendedFeedLoader(
            initialItems: [item],
            refreshedItems: [updatedItem],
            firstLoadStarted: firstLoadStarted
        )
        let commentPoster = StubCommentPoster()
        let viewModel = makeViewModel(feedLoader: loader, commentPoster: commentPoster)
        let refresh = Task { await viewModel.load() }
        await fulfillment(of: [firstLoadStarted], timeout: 3)

        try await viewModel.postComment(comment.body, on: item)
        XCTAssertTrue(viewModel.readModel.isLoading)
        await loader.resumeInitialLoad()
        await refresh.value

        let loadCount = await loader.loadCount
        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(commentPoster.posted, [FeedCommentCall(postId: item.id, body: comment.body)])
        XCTAssertEqual(viewModel.readModel.items, [updatedItem])
        XCTAssertFalse(viewModel.readModel.isLoading)
    }

    func testDeletePostRemovesRemotePostAndUpdatesReadModel() async {
        let item = FeedMockData.items[0]
        let postDeleter = StubPostDeleter()
        let viewModel = makeViewModel(items: [item], postDeleter: postDeleter)
        await viewModel.load()

        await viewModel.deletePost(item)

        XCTAssertEqual(postDeleter.deletedIds, [item.id])
        XCTAssertTrue(viewModel.readModel.items.isEmpty)
    }

    func testDeleteDuringRefreshDoesNotRestoreDeletedPost() async {
        let item = FeedMockData.items[0]
        let refreshStarted = expectation(description: "Refresh captured the pre-deletion feed")
        let loader = SuspendedFeedLoader(
            initialItems: [item],
            refreshedItems: [],
            suspendOnLoad: 2,
            firstLoadStarted: refreshStarted
        )
        let postDeleter = StubPostDeleter()
        let viewModel = makeViewModel(feedLoader: loader, postDeleter: postDeleter)
        await viewModel.load()
        let refresh = Task { await viewModel.load() }
        await fulfillment(of: [refreshStarted], timeout: 3)

        await viewModel.deletePost(item)
        XCTAssertTrue(viewModel.readModel.items.isEmpty)
        await loader.resumeInitialLoad()
        await refresh.value

        let loadCount = await loader.loadCount
        XCTAssertEqual(loadCount, 3)
        XCTAssertEqual(postDeleter.deletedIds, [item.id])
        XCTAssertTrue(viewModel.readModel.items.isEmpty)
        XCTAssertFalse(viewModel.readModel.isLoading)
    }

    func testCheerDuringRefreshKeepsConfirmedReaction() async {
        let item = FeedMockData.items[0]
        var updatedItem = item
        updatedItem.viewerHasCheered = true
        let refreshStarted = expectation(description: "Refresh captured the pre-cheer feed")
        let loader = SuspendedFeedLoader(
            initialItems: [item],
            refreshedItems: [updatedItem],
            suspendOnLoad: 2,
            firstLoadStarted: refreshStarted
        )
        let reactionPoster = StubReactionPoster()
        let viewModel = makeViewModel(feedLoader: loader, reactionPoster: reactionPoster)
        await viewModel.load()
        let refresh = Task { await viewModel.load() }
        await fulfillment(of: [refreshStarted], timeout: 3)

        await viewModel.toggleCheer(for: item)
        await loader.resumeInitialLoad()
        await refresh.value

        let loadCount = await loader.loadCount
        XCTAssertEqual(loadCount, 3)
        XCTAssertEqual(reactionPoster.added, [FeedReactionCall(postId: item.id, reactionType: "cheer")])
        XCTAssertEqual(viewModel.readModel.items.first?.viewerHasCheered, true)
        XCTAssertFalse(viewModel.readModel.isLoading)
    }

    func testBookmarkDuringRefreshKeepsConfirmedBookmark() async {
        let item = FeedMockData.items[0]
        var updatedItem = item
        updatedItem.viewerHasSaved = true
        let refreshStarted = expectation(description: "Refresh captured the pre-bookmark feed")
        let loader = SuspendedFeedLoader(
            initialItems: [item],
            refreshedItems: [updatedItem],
            suspendOnLoad: 2,
            firstLoadStarted: refreshStarted
        )
        let bookmarkPoster = StubBookmarkPoster()
        let viewModel = makeViewModel(feedLoader: loader, bookmarkPoster: bookmarkPoster)
        await viewModel.load()
        let refresh = Task { await viewModel.load() }
        await fulfillment(of: [refreshStarted], timeout: 3)

        await viewModel.toggleSave(for: item)
        await loader.resumeInitialLoad()
        await refresh.value

        let loadCount = await loader.loadCount
        XCTAssertEqual(loadCount, 3)
        XCTAssertEqual(bookmarkPoster.addedPostIds, [item.id])
        XCTAssertEqual(viewModel.readModel.items.first?.viewerHasSaved, true)
        XCTAssertFalse(viewModel.readModel.isLoading)
    }

    func testDeletePostRemovesLocalDraftFromDraftStoreNotRemotely() async {
        let draft = FeedItem(
            id: UUID(),
            authorName: "나",
            authorHandle: nil,
            isLocalDraft: true,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            itemType: .workoutSession,
            visibility: .privateOnly,
            cardData: FeedMockData.items[0].cardData,
            caption: nil,
            activityContext: "오늘의 라이딩"
        )
        let draftStore = InMemoryFeedShareDraftStore()
        let postDeleter = StubPostDeleter()
        let viewModel = makeViewModel(items: [draft], postDeleter: postDeleter, draftStore: draftStore)
        await viewModel.load()

        await viewModel.deletePost(draft)

        XCTAssertTrue(postDeleter.deletedIds.isEmpty)
        XCTAssertTrue(viewModel.readModel.items.isEmpty)
    }

    func testCancelledInitialLoadCannotApplyLateResponseAndCanRetry() async {
        let started = expectation(description: "Request started")
        let loader = SuspendedFeedLoader(initialItems: Array(FeedMockData.items.prefix(1)),
            refreshedItems: Array(FeedMockData.items.prefix(2)), firstLoadStarted: started)
        let model = makeViewModel(feedLoader: loader)
        let request = Task { await model.load() }
        await fulfillment(of: [started], timeout: 3)
        request.cancel()
        await loader.resumeInitialLoad()
        await request.value
        XCTAssertTrue(model.readModel.items.isEmpty)
        XCTAssertFalse(model.readModel.isLoading)
        XCTAssertFalse(model.readModel.hasResolvedPage)
        XCTAssertTrue(model.readModel.showsInitialLoading)
        await model.load()
        XCTAssertEqual(model.readModel.items.count, 2)
        XCTAssertTrue(model.readModel.hasResolvedPage)
        XCTAssertFalse(model.readModel.showsInitialLoading)
        let count = await loader.loadCount
        XCTAssertEqual(count, 2)
    }

    func testVisibleBatchKeepsRawPrefixAndUpdatesOnlyChangedMetrics() async {
        let rows = (0..<2).map { _ in AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: UUID(),
            sport: "running", activityAt: "2020-01-01T00:00:00Z", durationSeconds: 600,
            distanceMeters: 1000, revision: 1, readPolicy: .profileOnlyV2) }
        let items = AccountActivityHydratedPage(cards: rows.map { .init(projection: $0, legacyItem: nil) }, nextCursor: nil, hasMore: false).displayItems()
        let loader = StubFeedLoader(items: items)
        loader.projectionRows = rows
        let vm = makeViewModel(feedLoader: loader)
        await vm.selectAudience(.home)
        XCTAssertEqual(vm.loadedProjectionPrefix, rows)
        let changed = AccountActivityFeedRow(cardID: rows[0].cardID, canonicalID: rows[0].canonicalID,
            ownerID: rows[0].ownerID, sport: "running", activityAt: rows[0].activityAt,
            durationSeconds: 900, distanceMeters: 1500, revision: 2, readPolicy: .profileOnlyV2)
        let context = FeedReturnBatchContext(viewerID: UUID(), accountGeneration: 1, safetyRevision: 1, returnEpoch: 1)
        let grant = FeedReturnCardGrant(id: UUID(), row: changed, author: nil, authorRevision: nil,
            avatarObject: nil, photos: [], photoObjects: [:], photosAvailable: false, socialStatus: nil)
        let before = vm.readModel.items.first { $0.id == rows[1].cardID }
        let batch = FeedReturnBatchPresentation(id: UUID(), context: context, phase: .ready, grants: [changed.cardID: grant])
        XCTAssertTrue(vm.applyVisibleBatch(batch))
        XCTAssertEqual(vm.readModel.items.first { $0.id == rows[1].cardID }, before)
        XCTAssertEqual(vm.loadedProjectionPrefix, [changed, rows[1]])
        XCTAssertEqual(loader.listLoadCount, 1)
        var denied = batch; denied.denied.insert(rows[1].cardID)
        XCTAssertFalse(vm.applyVisibleBatch(denied))
        var changedMembership = batch; changedMembership.needsPageReload = true
        XCTAssertFalse(vm.applyVisibleBatch(changedMembership))
        await vm.selectAudience(.all)
        XCTAssertFalse(vm.applyVisibleBatch(batch))
    }

    private func makeViewModel(
        items: [FeedItem] = [],
        feedLoader: (any FeedLoading)? = nil,
        reactionPoster: (any FeedRemoteReactionPosting)? = nil,
        bookmarkPoster: (any FeedRemoteBookmarkPosting)? = nil,
        commentPoster: (any FeedRemoteCommentPosting)? = nil,
        postDeleter: (any FeedRemotePostDeleting)? = nil,
        draftStore: (any FeedShareDraftStoreProtocol)? = nil
    ) -> FeedViewModel {
        FeedViewModel(
            feedLoader: feedLoader ?? StubFeedLoader(items: items),
            weeklyProgressProvider: StubWeeklyProgressProvider(result: .failure(StubError.failed)),
            recoveryPreviewProvider: StubRecoveryPreviewProvider(result: .failure(StubError.failed)),
            streakDatesProvider: StubStreakDatesProvider(result: .failure(StubError.failed)),
            reactionPoster: reactionPoster,
            bookmarkPoster: bookmarkPoster,
            commentPoster: commentPoster,
            postDeleter: postDeleter,
            draftStore: draftStore
        )
    }

    private func makeProgress(workoutCount: Int) -> WeeklyWorkoutProgress {
        WeeklyWorkoutProgress(
            weekStartDate: Date(timeIntervalSince1970: 1_800_000_000),
            workoutCount: workoutCount,
            totalDistanceKm: 42.4,
            totalDurationMinutes: 180,
            averagePaceOrSpeedText: "평균 페이스 5'20\"/km",
            progressSummary: "이번 주도 리듬을 이어가고 있어요.",
            motivationText: "좋은 흐름입니다.",
            trendType: .steady
        )
    }
    func testFeedReentryJoinsRefreshAlreadyInProgress() async {
        let coordinator = SOOMFeedRefreshCoordinator(), gate = FeedRefreshTestSuspension()
        var requests = 0
        let first = Task { await coordinator.refresh(requiresFollowUp: false) { requests += 1; await gate.wait() } }
        while !gate.started { await Task.yield() }
        let second = Task { await coordinator.refresh(requiresFollowUp: false) { requests += 1 } }
        while coordinator.joinedRequests == 0 { await Task.yield() }
        gate.resume()
        await first.value; await second.value
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(coordinator.startedOperations, 1)
        XCTAssertFalse(coordinator.isRefreshing)
    }

    func testManualRetryDuringFailureRetirementRunsExactlyOnce() async {
        let coordinator = SOOMFeedRefreshCoordinator(), gate = FeedRefreshTestSuspension()
        let store = FeedReturnBatchStore()
        let context = FeedReturnBatchContext(viewerID: UUID(), accountGeneration: 1, safetyRevision: 1, returnEpoch: 1)
        let id = store.begin(context: context)
        var requests = 0
        let first = Task { await coordinator.refresh(requiresFollowUp: false) {
            requests += 1
            if requests == 1 { store.fail(expectedID: id); await gate.wait() }
        } }
        while !gate.started { await Task.yield() }
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(store.beginRetry(context: context))
        XCTAssertFalse(store.beginRetry(context: context))
        let retry = Task { await coordinator.refresh(requiresFollowUp: true) { XCTFail("Existing owner executes the queued operation") } }
        while coordinator.joinedRequests == 0 { await Task.yield() }
        gate.resume(); await first.value; await retry.value
        XCTAssertEqual(requests, 2)
        XCTAssertFalse(coordinator.isRefreshing)
    }

    func testFeedDataMutationDuringRefreshQueuesOneFreshFollowUp() async {
        let coordinator = SOOMFeedRefreshCoordinator(), gate = FeedRefreshTestSuspension()
        var requests = 0
        let first = Task { await coordinator.refresh(requiresFollowUp: false) {
            requests += 1
            if requests == 1 { await gate.wait() }
        } }
        while !gate.started { await Task.yield() }
        let second = Task { await coordinator.refresh(requiresFollowUp: true) { XCTFail("Only the original refresh owns the operation") } }
        let third = Task { await coordinator.refresh(requiresFollowUp: true) { XCTFail("Only the original refresh owns the operation") } }
        while coordinator.joinedRequests < 2 { await Task.yield() }
        gate.resume()
        await first.value; await second.value; await third.value
        XCTAssertEqual(requests, 2, "Mutations require fresh data but must coalesce into one follow-up")
        XCTAssertFalse(coordinator.isRefreshing)
    }

    func testFeedRefreshCancellationCannotEraseNextOwner() async {
        let coordinator = SOOMFeedRefreshCoordinator(), oldGate = FeedRefreshTestSuspension(), nextGate = FeedRefreshTestSuspension()
        let old = Task { await coordinator.refresh(requiresFollowUp: false) { await oldGate.wait() } }
        while !oldGate.started { await Task.yield() }
        coordinator.cancel()
        XCTAssertFalse(coordinator.isRefreshing)
        let next = Task { await coordinator.refresh(requiresFollowUp: false) { await nextGate.wait() } }
        while !coordinator.isRefreshing { await Task.yield() }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(nextGate.started, "New load must wait for cancelled model ownership to drain")
        oldGate.resume(); await old.value
        while !nextGate.started { await Task.yield() }
        XCTAssertTrue(coordinator.isRefreshing)
        nextGate.resume(); await next.value
        XCTAssertFalse(coordinator.isRefreshing)
        XCTAssertEqual(coordinator.startedOperations, 2)
    }

}

private final class StubFeedLoader: FeedLoading {
    var items: [FeedItem]
    var postItems: [FeedItem]?
    var projectionRows: [AccountActivityFeedRow]?
    private(set) var listLoadCount = 0
    private(set) var loadedPostIDs: [UUID] = []
    var failure: FeedLoadFailure?
    var transientFailuresRemaining = 0

    init(items: [FeedItem], failure: FeedLoadFailure? = nil) {
        self.items = items
        self.failure = failure
    }

    func loadFeed(limit: Int) async -> FeedLoadResult {
        listLoadCount += 1
        if transientFailuresRemaining > 0 {
            transientFailuresRemaining -= 1
            return FeedLoadResult(items: [], failure: .remoteFailed)
        }
        return FeedLoadResult(items: Array(items.prefix(limit)), failure: failure,
            remoteProjectionRows: projectionRows.map { Array($0.prefix(limit)) })
    }

    func loadPost(id: UUID) async -> FeedItem? {
        loadedPostIDs.append(id)
        return (postItems ?? items).first { $0.id == id }
    }
}

private actor SuspendedFeedLoader: FeedLoading {
    private let initialItems: [FeedItem]
    private let refreshedItems: [FeedItem]
    private let suspendOnLoad: Int
    private let firstLoadStarted: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var loadCount = 0

    init(
        initialItems: [FeedItem],
        refreshedItems: [FeedItem],
        suspendOnLoad: Int = 1,
        firstLoadStarted: XCTestExpectation
    ) {
        self.initialItems = initialItems
        self.refreshedItems = refreshedItems
        self.suspendOnLoad = suspendOnLoad
        self.firstLoadStarted = firstLoadStarted
    }

    func loadFeed(limit: Int) async -> FeedLoadResult {
        loadCount += 1
        if loadCount < suspendOnLoad {
            return FeedLoadResult(items: Array(initialItems.prefix(limit)))
        }
        if loadCount == suspendOnLoad {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                firstLoadStarted.fulfill()
            }
            return FeedLoadResult(items: Array(initialItems.prefix(limit)))
        }
        return FeedLoadResult(items: Array(refreshedItems.prefix(limit)))
    }

    func resumeInitialLoad() {
        continuation?.resume()
        continuation = nil
    }

    func loadPost(id: UUID) async -> FeedItem? {
        refreshedItems.first { $0.id == id }
    }
}

private actor SuspendedWeeklyProgressProvider: FeedWeeklyProgressProviding {
    private var continuation: CheckedContinuation<Void, Never>?
    private var resumePending = false

    func fetchWeeklyProgress(referenceDate: Date) async throws -> WeeklyWorkoutProgress {
        if !resumePending {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        throw StubError.failed
    }

    func resume() {
        if let continuation {
            self.continuation = nil
            continuation.resume()
        } else {
            resumePending = true
        }
    }
}

private struct StubWeeklyProgressProvider: FeedWeeklyProgressProviding {
    let result: Result<WeeklyWorkoutProgress, Error>

    func fetchWeeklyProgress(referenceDate: Date) async throws -> WeeklyWorkoutProgress {
        try result.get()
    }
}

private struct StubRecoveryPreviewProvider: FeedRecoveryPreviewProviding {
    let result: Result<UnifiedWorkoutRecoveryPreviewResult, Error>

    func fetchPreviewSummary() async throws -> UnifiedWorkoutRecoveryPreviewResult {
        try result.get()
    }
}

private struct StubStreakDatesProvider: FeedStreakWorkoutDatesProviding {
    let result: Result<[Date], Error>

    func fetchRecentWorkoutDates(days: Int) async throws -> [Date] {
        try result.get()
    }
}

private enum StubError: Error {
    case failed
}

private struct FeedReactionCall: Equatable {
    let postId: UUID
    let reactionType: String
}

private final class StubReactionPoster: FeedRemoteReactionPosting {
    private(set) var added: [FeedReactionCall] = []
    private(set) var removed: [FeedReactionCall] = []
    let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func addReaction(postId: UUID, reactionType: String) async throws {
        if let error { throw error }
        added.append(FeedReactionCall(postId: postId, reactionType: reactionType))
    }

    func removeReaction(postId: UUID, reactionType: String) async throws {
        if let error { throw error }
        removed.append(FeedReactionCall(postId: postId, reactionType: reactionType))
    }
}

private final class StubBookmarkPoster: FeedRemoteBookmarkPosting {
    private(set) var addedPostIds: [UUID] = []
    private(set) var removedPostIds: [UUID] = []
    let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func addBookmark(postId: UUID) async throws {
        if let error { throw error }
        addedPostIds.append(postId)
    }

    func removeBookmark(postId: UUID) async throws {
        if let error { throw error }
        removedPostIds.append(postId)
    }
}

private struct FeedCommentCall: Equatable {
    let postId: UUID
    let body: String
}

private final class StubCommentPoster: FeedRemoteCommentPosting {
    private(set) var posted: [FeedCommentCall] = []

    func addComment(postId: UUID, body: String) async throws {
        posted.append(FeedCommentCall(postId: postId, body: body))
    }
}

private final class StubPostDeleter: FeedRemotePostDeleting {
    private(set) var deletedIds: [UUID] = []

    func deletePost(id: UUID) async throws {
        deletedIds.append(id)
    }
}

@MainActor
final class FeedSavedPostsViewModelTests: XCTestCase {
    func testFailedUnbookmarkKeepsSavedPostAndOriginalOrder() async {
        let first = savedItem(at: 0)
        let second = savedItem(at: 1)
        let viewModel = FeedSavedPostsViewModel(
            repository: MockFeedRepository(items: [first, second]),
            bookmarkPoster: StubBookmarkPoster(error: StubError.failed),
            safetyStore: CommunitySafetyStore(client: nil, viewerID: first.authorId)
        )
        await viewModel.load()

        await viewModel.toggleSave(for: first)

        XCTAssertEqual(viewModel.items, [first, second])
    }

    func testUnbookmarkDuringCommentReloadDoesNotRestoreRemovedPost() async throws {
        let item = savedItem()
        let refreshStarted = expectation(description: "Saved feed captured the pre-unbookmark state")
        let loader = SuspendedFeedLoader(
            initialItems: [item],
            refreshedItems: [],
            suspendOnLoad: 2,
            firstLoadStarted: refreshStarted
        )
        let bookmarkPoster = StubBookmarkPoster()
        let viewModel = FeedSavedPostsViewModel(
            repository: SavedPostsTestRepository(loader: loader),
            bookmarkPoster: bookmarkPoster,
            commentPoster: StubCommentPoster(),
            safetyStore: CommunitySafetyStore(client: nil, viewerID: item.authorId)
        )
        await viewModel.load()
        let refresh = Task { try await viewModel.postComment("좋은 흐름이에요!", on: item) }
        await fulfillment(of: [refreshStarted], timeout: 3)

        await viewModel.toggleSave(for: item)
        XCTAssertTrue(viewModel.items.isEmpty)
        await loader.resumeInitialLoad()
        try await refresh.value

        let loadCount = await loader.loadCount
        XCTAssertEqual(loadCount, 3)
        XCTAssertEqual(bookmarkPoster.removedPostIds, [item.id])
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testDeleteDuringCommentReloadDoesNotRestoreDeletedPost() async throws {
        let item = savedItem()
        let refreshStarted = expectation(description: "Saved feed captured the pre-deletion state")
        let loader = SuspendedFeedLoader(
            initialItems: [item],
            refreshedItems: [],
            suspendOnLoad: 2,
            firstLoadStarted: refreshStarted
        )
        let postDeleter = StubPostDeleter()
        let viewModel = FeedSavedPostsViewModel(
            repository: SavedPostsTestRepository(loader: loader),
            commentPoster: StubCommentPoster(),
            postDeleter: postDeleter,
            safetyStore: CommunitySafetyStore(client: nil, viewerID: item.authorId)
        )
        await viewModel.load()
        let refresh = Task { try await viewModel.postComment("좋은 흐름이에요!", on: item) }
        await fulfillment(of: [refreshStarted], timeout: 3)

        await viewModel.deletePost(item)
        XCTAssertTrue(viewModel.items.isEmpty)
        await loader.resumeInitialLoad()
        try await refresh.value

        let loadCount = await loader.loadCount
        XCTAssertEqual(loadCount, 3)
        XCTAssertEqual(postDeleter.deletedIds, [item.id])
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testCheerRefreshesSavedCardPeopleWithoutReloadingSavedList() async {
        let item = savedItem()
        let repository = MutableSavedPostsRepository(items: [item])
        let profile = FeedProfileDTO(id: item.authorId, displayName: "응원자", handle: "runner", avatarPath: "avatar.jpg")
        var confirmed = item
        confirmed.viewerHasCheered = true
        confirmed.reactions = [FeedReaction(id: UUID(), symbol: "👏", label: "응원", authorId: item.authorId,
            createdAt: Date(), profile: profile)]
        repository.confirmedPost = confirmed
        let viewModel = FeedSavedPostsViewModel(repository: repository, reactionPoster: StubReactionPoster(),
            safetyStore: CommunitySafetyStore(client: nil, viewerID: item.authorId))
        await viewModel.load()

        await viewModel.toggleCheer(for: item)

        XCTAssertEqual(viewModel.items.first?.viewerHasCheered, true)
        XCTAssertEqual(viewModel.items.first?.orderedCheers.count, 1)
        XCTAssertEqual(viewModel.items.first?.orderedCheers.first?.profile, profile)
        XCTAssertEqual(repository.savedLoadCount, 1)
        XCTAssertEqual(repository.loadedPostIDs, [item.id])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCheerDuringCommentReloadKeepsConfirmedReaction() async throws {
        let item = savedItem()
        var updatedItem = item
        updatedItem.viewerHasCheered = true
        let refreshStarted = expectation(description: "Saved feed captured the pre-cheer state")
        let loader = SuspendedFeedLoader(
            initialItems: [item],
            refreshedItems: [updatedItem],
            suspendOnLoad: 2,
            firstLoadStarted: refreshStarted
        )
        let reactionPoster = StubReactionPoster()
        let viewModel = FeedSavedPostsViewModel(
            repository: SavedPostsTestRepository(loader: loader),
            reactionPoster: reactionPoster,
            commentPoster: StubCommentPoster(),
            safetyStore: CommunitySafetyStore(client: nil, viewerID: item.authorId)
        )
        await viewModel.load()
        let refresh = Task { try await viewModel.postComment("좋은 흐름이에요!", on: item) }
        await fulfillment(of: [refreshStarted], timeout: 3)

        await viewModel.toggleCheer(for: item)
        await loader.resumeInitialLoad()
        try await refresh.value

        let loadCount = await loader.loadCount
        XCTAssertEqual(loadCount, 3)
        XCTAssertEqual(reactionPoster.added, [FeedReactionCall(postId: item.id, reactionType: "cheer")])
        XCTAssertEqual(viewModel.items.first?.viewerHasCheered, true)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadFailureClearsCachedContentAndRetryDistinguishesEmptyList() async {
        let item = savedItem()
        let repository = MutableSavedPostsRepository(items: [item])
        let viewModel = FeedSavedPostsViewModel(repository: repository)
        await viewModel.load()
        XCTAssertEqual(viewModel.items, [item])
        repository.failure = StubError.failed
        await viewModel.load()
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertTrue(viewModel.hasLoadFailure)
        XCTAssertNotNil(viewModel.errorMessage)
        repository.failure = nil
        repository.items = []
        await viewModel.load()
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertFalse(viewModel.hasLoadFailure)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testMissingDeleteAdapterDoesNotClaimSuccessfulRemoval() async {
        let item = savedItem()
        let viewModel = FeedSavedPostsViewModel(repository: MockFeedRepository(items: [item]),
            safetyStore: CommunitySafetyStore(client: nil, viewerID: item.authorId))
        await viewModel.load()
        await viewModel.deletePost(item)
        XCTAssertEqual(viewModel.items, [item])
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testChangedSDKAccountCannotMutateOrRetainSavedItems() async {
        let item = savedItem()
        var sessionID: UUID? = item.authorId
        let poster = StubBookmarkPoster()
        let viewModel = FeedSavedPostsViewModel(repository: MockFeedRepository(items: [item]),
            bookmarkPoster: poster, safetyStore: CommunitySafetyStore(client: nil, viewerID: item.authorId),
            sessionUserID: { sessionID })
        await viewModel.load()
        sessionID = UUID()
        await viewModel.toggleSave(for: item)
        XCTAssertTrue(poster.removedPostIds.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
        await viewModel.load()
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertTrue(viewModel.hasLoadFailure)
    }

    private func savedItem(at index: Int = 0) -> FeedItem {
        var item = FeedMockData.items[index]
        item.viewerHasSaved = true
        return item
    }
}

private final class MutableSavedPostsRepository: FeedRepositoryProtocol {
    var items: [FeedItem]
    var confirmedPost: FeedItem?
    private(set) var savedLoadCount = 0
    private(set) var loadedPostIDs: [UUID] = []
    var failure: Error?
    init(items: [FeedItem]) { self.items = items }
    func fetchFeed(limit: Int) async throws -> [FeedItem] { try await fetchSavedPosts() }
    func fetchSavedPosts() async throws -> [FeedItem] {
        savedLoadCount += 1
        if let failure { throw failure }
        return items
    }
    func fetchPost(id: UUID) async throws -> FeedItem? {
        loadedPostIDs.append(id)
        if let failure { throw failure }
        return confirmedPost ?? items.first { $0.id == id }
    }
}

private struct SavedPostsTestRepository: FeedRepositoryProtocol {
    let loader: any FeedLoading

    func fetchFeed(limit: Int) async throws -> [FeedItem] {
        await loader.loadFeed(limit: limit).items
    }

    func fetchSavedPosts() async throws -> [FeedItem] {
        await loader.loadFeed(limit: 20).items
    }

    func fetchPost(id: UUID) async throws -> FeedItem? {
        await loader.loadPost(id: id)
    }
}

private final class MutableRecoveryPreviewProvider: FeedRecoveryPreviewProviding {
    var result: Result<UnifiedWorkoutRecoveryPreviewResult, Error>
    init(result: Result<UnifiedWorkoutRecoveryPreviewResult, Error>) { self.result = result }
    func fetchPreviewSummary() async throws -> UnifiedWorkoutRecoveryPreviewResult { try result.get() }
}

@MainActor
private final class FeedRefreshTestSuspension {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation; started = true
        }
    }
    func resume() { continuation?.resume(); continuation = nil }
}

@MainActor
final class MutualFeedInvalidationTests: XCTestCase {
    private func item(_ visibility: ShareableWorkoutVisibility) -> FeedItem {
        FeedItem(id: UUID(), authorName: "Synthetic", authorHandle: nil, authorId: UUID(),
            createdAt: Date(), itemType: .workoutSession, visibility: visibility,
            cardData: FeedMockData.items[0].cardData, caption: nil, activityContext: "Synthetic")
    }
    private func model(_ loader: any FeedLoading, safety: CommunitySafetyStore) -> FeedViewModel {
        FeedViewModel(feedLoader: loader,
            weeklyProgressProvider: StubWeeklyProgressProvider(result: .failure(StubError.failed)),
            recoveryPreviewProvider: StubRecoveryPreviewProvider(result: .failure(StubError.failed)),
            streakDatesProvider: StubStreakDatesProvider(result: .failure(StubError.failed)), safetyStore: safety)
    }
    func testRelationshipChangeImmediatelyDropsPublicFollowingMembership() async {
        let viewer = UUID(), safety = CommunitySafetyStore(client: nil, viewerID: viewer)
        let loader = StubFeedLoader(items: [item(.publicFeed)])
        let vm = model(loader, safety: safety)
        await vm.selectAudience(.following)
        XCTAssertFalse(vm.readModel.items.isEmpty)
        safety.invalidateRelationships()
        XCTAssertTrue(vm.readModel.items.isEmpty, "Public access is not proof of following membership")
        XCTAssertFalse(vm.readModel.hasMore)
    }
    func testRelationshipChangeDropsMutualButKeepsPublicInAllFeed() async {
        let safety = CommunitySafetyStore(client: nil, viewerID: UUID())
        let publicPost = item(.publicFeed), mutualPost = item(.mutual)
        let vm = model(StubFeedLoader(items: [publicPost, mutualPost]), safety: safety)
        await vm.load()
        XCTAssertEqual(vm.readModel.items.count, 2)
        safety.invalidateRelationships()
        XCTAssertEqual(vm.readModel.items.map(\.id), [publicPost.id])
    }
    func testLateMutualFetchCannotRestoreRevokedGrant() async {
        let safety = CommunitySafetyStore(client: nil, viewerID: UUID())
        let mutualPost = item(.mutual)
        let started = expectation(description: "Captured old authorized page")
        let loader = SuspendedFeedLoader(initialItems: [mutualPost], refreshedItems: [], firstLoadStarted: started)
        let vm = model(loader, safety: safety)
        let fetch = Task { await vm.load() }
        await fulfillment(of: [started], timeout: 3)
        safety.invalidateRelationships()
        await loader.resumeInitialLoad()
        await fetch.value
        XCTAssertTrue(vm.readModel.items.isEmpty)
    }
}


extension FeedViewModelTests {
    func testAcceptanceFeedInitialPresentationPullAndReturnReadCounts() async {
        let loader = StubFeedLoader(items: Array(FeedMockData.items.prefix(2)))
        let model = makeViewModel(feedLoader: loader)
        await model.load(); XCTAssertEqual(loader.listLoadCount, 1)
        let ids = model.readModel.items.map(\.id)
        for _ in 0..<100 { _ = model.readModel.items; model.recordFirstCardDisplay() }
        XCTAssertEqual(loader.listLoadCount, 1, "Reading/rendering an existing model does not fetch")
        await model.loadMore(); XCTAssertEqual(loader.listLoadCount, 1, "Exhausted pagination is not a reload")
        await model.load(); XCTAssertEqual(loader.listLoadCount, 2, "Explicit pull refresh")
        XCTAssertEqual(model.readModel.items.map(\.id), ids)
        await model.load(); XCTAssertEqual(loader.listLoadCount, 3, "Feed return intentionally revalidates; no completed remote cache")
        XCTAssertEqual(model.readModel.items.map(\.id), ids)
    }
}


@MainActor
private final class PerformanceFeedSummaries: FeedWeeklyProgressProviding, FeedRecoveryPreviewProviding, FeedStreakWorkoutDatesProviding {
    var starts = 0
    func fetchWeeklyProgress(referenceDate: Date) async throws -> WeeklyWorkoutProgress { starts += 1; throw CocoaError(.fileReadUnknown) }
    func fetchPreviewSummary() async throws -> UnifiedWorkoutRecoveryPreviewResult { starts += 1; throw CocoaError(.fileReadUnknown) }
    func fetchRecentWorkoutDates(days: Int) async throws -> [Date] { starts += 1; return [] }
}
extension FeedViewModelTests {
    func testPerformanceFeedSupplementaryWorkStartOrder() async {
        let started = expectation(description: "Feed pending"), summaries = PerformanceFeedSummaries()
        let loader = SuspendedFeedLoader(initialItems: Array(FeedMockData.items.prefix(1)), refreshedItems: [], firstLoadStarted: started)
        let model = FeedViewModel(feedLoader: loader, weeklyProgressProvider: summaries,
            recoveryPreviewProvider: summaries, streakDatesProvider: summaries)
        let task = Task { await model.load() }
        await fulfillment(of: [started], timeout: 3)
        try? await Task.sleep(for: .milliseconds(20))
        print("SOOM_PERF_FEED summaries_started_before_cards=\(summaries.starts) visible_cards=\(model.readModel.items.count)")
        XCTAssertEqual(summaries.starts, 0, "Optional providers wait for primary feed response")
        await loader.resumeInitialLoad(); await task.value
        XCTAssertEqual(model.readModel.items.count, 1); XCTAssertEqual(summaries.starts, 3)
    }
}


extension FeedViewModelTests {
    func testR2ConfirmedEmptyAndFailureHaveDifferentPresentation() async {
        let empty = makeViewModel(items: [])
        XCTAssertTrue(empty.readModel.showsInitialLoading)
        await empty.load()
        XCTAssertTrue(empty.readModel.hasResolvedPage)
        XCTAssertFalse(empty.readModel.showsInitialLoading)
        var failed = FeedReadModel.loading
        failed.isLoading = false; failed.loadFailure = .remoteFailed
        XCTAssertFalse(failed.showsInitialLoading, "Error/retry must not be hidden by an endless skeleton")
        empty.invalidateForSafetyChange()
        XCTAssertFalse(empty.readModel.hasResolvedPage)
        XCTAssertTrue(empty.readModel.showsInitialLoading)
    }
}

@MainActor final class PreviewLegacySummaryMergeTests: XCTestCase {
    private let viewer = UUID(), owner = UUID()
    private func summary(id: UUID = UUID(), at: String = "2026-11-12T00:00:00Z") -> PreviewLegacyPublicSummary {
        .init(post_id: id, owner_id: owner, sport: "running", activity_at: at, duration_seconds: 600, distance_meters: 1000)
    }
    func testNarrowSummaryHasNoSensitiveHydrationAndIsReadOnly() {
        let value = summary().feedItem(context: .init(viewerID: viewer, generation: 1, safetyRevision: 2))
        XCTAssertTrue(value.previewLegacySummary)
        XCTAssertNil(value.caption); XCTAssertNil(value.sharedDetail); XCTAssertNil(value.serverPostSnapshot)
        XCTAssertTrue(value.photos.isEmpty); XCTAssertTrue(value.comments.isEmpty); XCTAssertTrue(value.reactions.isEmpty)
    }
    func testMergePreservesIndependentSourceAndRLSWinsDuplicate() {
        let row = summary(), context = AccountActivityReadContext(viewerID: viewer, generation: 1, safetyRevision: 2)
        let narrow = row.feedItem(context: context)
        var legacy = narrow; legacy.previewLegacySummary = false
        let older = summary(at: "2026-11-11T00:00:00Z").feedItem(context: context)
        let merged = PreviewLegacySummaryMerge.merge(legacy: [legacy], summaries: [narrow, older], limit: 2)
        XCTAssertEqual(merged.map(\.id), [legacy.id, older.id]); XCTAssertFalse(merged[0].previewLegacySummary)
        XCTAssertEqual(PreviewLegacySummaryMerge.merge(legacy: [legacy], summaries: [], limit: 1).map(\.id), [legacy.id])
        XCTAssertEqual(PreviewLegacySummaryMerge.merge(legacy: [], summaries: [narrow], limit: 1).map(\.id), [narrow.id])
    }
    func testReceiptValidationRejectsWrongPostDuplicatesCursorAndBlockedOwner() throws {
        let row = summary(), now = Date(timeIntervalSince1970: 1_800_000_000)
        let request = AccountActivityPageRequest(viewerID: viewer, scope: .home, ownerID: nil, before: nil, limit: 20)
        try PreviewLegacyPublicSummary.validate([row], request: request, postID: nil, now: now, blocked: { _ in false })
        XCTAssertThrowsError(try PreviewLegacyPublicSummary.validate([row], request: request, postID: UUID(), now: now, blocked: { _ in false }))
        XCTAssertThrowsError(try PreviewLegacyPublicSummary.validate([row, row], request: request, postID: nil, now: now, blocked: { _ in false }))
        XCTAssertThrowsError(try PreviewLegacyPublicSummary.validate([row], request: request, postID: nil, now: now, blocked: { _ in true }))
        let cursorRequest = AccountActivityPageRequest(viewerID: viewer, scope: .home, ownerID: nil,
            before: .init(activityAt: row.date!, cardID: row.post_id), limit: 20)
        XCTAssertThrowsError(try PreviewLegacyPublicSummary.validate([row], request: cursorRequest, postID: nil, now: now, blocked: { _ in false }))
    }
}

@MainActor final class FeedRemoteCoveragePagingTests: XCTestCase {
    private final class Repository: FeedRepositoryProtocol {
        var items: [FeedItem] = []
        var offsets: [Int] = []
        var failFrom: Int?
        var onFetch: (() -> Void)?
        var suspension: FeedRefreshTestSuspension?
        func fetchSavedPosts() async throws -> [FeedItem] { [] }
        func fetchPost(id: UUID) async throws -> FeedItem? { items.first { $0.id == id } }
        func fetchFeed(limit: Int) async throws -> [FeedItem] { try await fetchFeedPage(limit: limit, offset: 0, audience: .home) }
        func fetchFeedPage(limit: Int, offset: Int, audience: FeedAudience) async throws -> [FeedItem] {
            offsets.append(offset); onFetch?()
            if let suspension { await suspension.wait() }
            if let failFrom, offset >= failFrom { throw FeedRepositoryError.unconfigured }
            return Array(items.dropFirst(offset).prefix(limit))
        }
    }
    private func item(owner: UUID, local: Bool, date: Double) -> FeedItem {
        FeedItem(id: UUID(), authorName: "Synthetic", authorHandle: nil, authorId: owner,
            isLocalDraft: local, isOwnerLocalWorkout: local, createdAt: Date(timeIntervalSince1970: date),
            itemType: .workoutSession, visibility: local ? .privateOnly : .publicFeed,
            cardData: FeedMockData.items[0].cardData, sourceWorkoutId: local ? UUID() : nil,
            caption: nil, activityContext: "Synthetic", activityDate: Date(timeIntervalSince1970: date))
    }
    private func setup(safety: CommunitySafetyStore? = nil) -> (FeedViewModel, Repository, [FeedItem], UUID) {
        let owner = safety?.viewerID ?? UUID(), following = UUID(), repo = Repository()
        let locals = (0..<119).map { item(owner: owner, local: true, date: 1_800_000_002 - Double($0)) }
        repo.items = (0..<16).map { item(owner: $0 < 8 ? owner : following, local: false, date: 1_800_000_000 - Double($0)) }
        let snapshot = OwnerWorkoutFeedProjection.Snapshot(ownerID: owner, scopeID: "synthetic", entries: locals.map {
            .init(canonicalID: $0.sourceWorkoutId!, sourceIDs: [$0.sourceWorkoutId!], item: $0, localItem: $0, existingServerItems: [])
        })
        let project: ([FeedItem]) -> [FeedItem] = { snapshot.merging(serverItems: $0, currentOwnerID: owner, currentScopeID: "synthetic") }
        let source = FeedDataSource(remoteRepository: repo, ownerProjection: project, homeContractAvailable: true)
        let vm = FeedViewModel(feedLoader: source,
            weeklyProgressProvider: StubWeeklyProgressProvider(result: .failure(StubError.failed)),
            recoveryPreviewProvider: StubRecoveryPreviewProvider(result: .failure(StubError.failed)),
            streakDatesProvider: StubStreakDatesProvider(result: .failure(StubError.failed)),
            safetyStore: safety, initialAudience: .home, normalizeItems: project)
        return (vm, repo, locals, following)
    }
    func test119LocalOwnerCardsDoNotStarveSecondEightServerFollowingCards() async {
        let (vm, repo, originals, following) = setup()
        let ids = originals.map(\.id)
        await vm.load()
        XCTAssertEqual(repo.offsets, [0]); XCTAssertTrue(vm.readModel.hasMore)
        XCTAssertEqual(vm.readModel.items.filter { $0.authorId == following }.count, 0)
        XCTAssertEqual(vm.readModel.items.filter(\.isOwnerLocalWorkout).count, 10)
        XCTAssertEqual(vm.readModel.items.count, 18, "119 local records must not move first server continuation to history end")
        let progress = vm.readModel.paginationRevision
        await vm.loadMore()
        XCTAssertEqual(vm.readModel.paginationRevision, progress + 1)
        XCTAssertEqual(repo.offsets, [0, 8])
        XCTAssertEqual(vm.readModel.items.filter { $0.authorId == following }.count, 8)
        XCTAssertEqual(vm.readModel.items.filter(\.isOwnerLocalWorkout).count, 18)
        await vm.loadMore()
        XCTAssertEqual(repo.offsets, [0, 8, 16]); XCTAssertFalse(vm.readModel.hasMore)
        XCTAssertEqual(vm.readModel.items.filter(\.isOwnerLocalWorkout).count, 119)
        XCTAssertEqual(Set(vm.readModel.items.map(\.id)).count, vm.readModel.items.count)
        XCTAssertEqual(originals.map(\.id), ids, "Display deferral must not mutate original local records")
    }
    func testInitialFailurePreservesAllLocalHistoryAndNextPageFailureKeepsCoverage() async {
        let (vm, repo, originals, _) = setup()
        repo.failFrom = 0; await vm.load()
        XCTAssertEqual(vm.readModel.items.filter(\.isOwnerLocalWorkout).count, 119)
        XCTAssertNotNil(vm.readModel.loadFailure)
        repo.failFrom = nil; await vm.load()
        let visible = vm.readModel.items.map(\.id), boundary = vm.readModel.remoteCoverageStart
        let progress = vm.readModel.paginationRevision, wake = vm.readModel.paginationWakeRevision
        repo.failFrom = 8; await vm.loadMore()
        XCTAssertEqual(vm.readModel.paginationRevision, progress)
        XCTAssertEqual(vm.readModel.paginationWakeRevision, wake, "A real failure requires explicit retry, not an automatic wake loop")
        XCTAssertEqual(vm.readModel.items.map(\.id), visible)
        XCTAssertEqual(vm.readModel.remoteCoverageStart, boundary); XCTAssertNotNil(vm.readModel.loadMoreFailure)
        XCTAssertEqual(originals.count, 119)
        repo.failFrom = nil; await vm.retryLoadMore()
        XCTAssertEqual(vm.readModel.items.filter { !$0.isOwnerLocalWorkout }.count, 16)
    }
    func testAccountSwitchDuringSecondPageCannotAppendOldFollowing() async {
        let owner = UUID(), safety = CommunitySafetyStore(client: nil, viewerID: UUID(), requiresSocialVerification: false)
        safety.setViewerID(owner)
        let (vm, repo, _, following) = setup(safety: safety)
        await vm.load()
        repo.onFetch = { safety.setViewerID(UUID()); vm.invalidateForSafetyChange() }
        await vm.loadMore()
        XCTAssertFalse(vm.readModel.items.contains { $0.authorId == following })
        XCTAssertTrue(vm.readModel.items.isEmpty)
    }
    func testCancelledPageDoesNotAdvanceAndReentryConsumesSameOffset() async {
        let (vm, repo, _, following) = setup()
        await vm.load()
        let progress = vm.readModel.paginationRevision, before = vm.readModel.items.map(\.id)
        let wake = vm.readModel.paginationWakeRevision
        let suspension = FeedRefreshTestSuspension(); repo.suspension = suspension
        let task = Task { await vm.loadMore() }
        while !suspension.started { await Task.yield() }
        task.cancel(); suspension.resume(); await task.value
        XCTAssertEqual(vm.readModel.paginationRevision, progress)
        XCTAssertEqual(vm.readModel.paginationWakeRevision, wake + 1)
        XCTAssertEqual(vm.readModel.items.map(\.id), before)
        XCTAssertFalse(vm.readModel.isLoadingMore)
        repo.suspension = nil; await vm.loadMore()
        XCTAssertEqual(repo.offsets, [0, 8, 8])
        XCTAssertEqual(vm.readModel.paginationRevision, progress + 1)
        XCTAssertEqual(vm.readModel.items.filter { $0.authorId == following }.count, 8)
    }
    func testImmediateReentryBeforeCancelledCleanupIsWokenAndRetriesSameOffset() async {
        let (vm, repo, _, following) = setup()
        await vm.load()
        let progress = vm.readModel.paginationRevision, wake = vm.readModel.paginationWakeRevision
        let suspension = FeedRefreshTestSuspension(); repo.suspension = suspension
        let first = Task { await vm.loadMore() }
        while !suspension.started { await Task.yield() }
        first.cancel()
        // The new footer task races the old request's still-running cleanup.
        await vm.loadMore()
        XCTAssertEqual(repo.offsets, [0, 8])
        XCTAssertTrue(vm.readModel.isLoadingMore)
        XCTAssertEqual(vm.readModel.paginationWakeRevision, wake)
        suspension.resume(); await first.value
        XCTAssertFalse(vm.readModel.isLoadingMore)
        XCTAssertEqual(vm.readModel.paginationRevision, progress)
        XCTAssertEqual(vm.readModel.paginationWakeRevision, wake + 1)
        repo.suspension = nil
        await vm.loadMore()
        XCTAssertEqual(repo.offsets, [0, 8, 8])
        XCTAssertEqual(vm.readModel.paginationRevision, progress + 1)
        XCTAssertEqual(vm.readModel.paginationWakeRevision, wake + 1, "Success advances progress, not cancellation wake")
        XCTAssertEqual(vm.readModel.items.filter { $0.authorId == following }.count, 8)
    }
    func testRefreshFinishesBeforeOldPageCleanupAndWakesBusyFooter() async {
        let (vm, repo, _, following) = setup()
        await vm.load()
        let suspension = FeedRefreshTestSuspension(); repo.suspension = suspension
        let oldPage = Task { await vm.loadMore() }
        while !suspension.started { await Task.yield() }
        repo.suspension = nil
        await vm.load()
        let progress = vm.readModel.paginationRevision, wake = vm.readModel.paginationWakeRevision
        let refreshed = vm.readModel.items.map(\.id)
        await vm.loadMore() // The new footer cannot enter while oldPage still owns the request slot.
        XCTAssertEqual(repo.offsets, [0, 8, 0])
        suspension.resume(); await oldPage.value
        XCTAssertEqual(vm.readModel.items.map(\.id), refreshed)
        XCTAssertEqual(vm.readModel.paginationRevision, progress)
        XCTAssertEqual(vm.readModel.paginationWakeRevision, wake + 1)
        XCTAssertFalse(vm.readModel.isLoadingMore)
        await vm.loadMore()
        XCTAssertEqual(repo.offsets, [0, 8, 0, 8])
        XCTAssertEqual(vm.readModel.items.filter { $0.authorId == following }.count, 8)
        XCTAssertEqual(vm.readModel.paginationRevision, progress + 1)
    }
    func testCoverageNeverDefersRemoteCardsOrUnboundedFallback() {
        let owner = UUID(), local = item(owner: owner, local: true, date: 100), remote = item(owner: UUID(), local: false, date: 90)
        XCTAssertEqual(FeedRemoteCoverage.visible([local, remote], since: Date(timeIntervalSince1970: 110), hasMore: true).map(\.id), [remote.id])
        XCTAssertEqual(FeedRemoteCoverage.visible([local, remote], since: nil, hasMore: true).count, 2)
        XCTAssertEqual(FeedRemoteCoverage.visible([local, remote], since: Date(timeIntervalSince1970: 110), hasMore: false).count, 2)
    }
    func testFullServerPageFilteredToZeroStillAllowsContinuation() async {
        let repo = Repository(), owner = UUID()
        repo.items = (0..<16).map { item(owner: owner, local: false, date: 1_800_000_000 - Double($0)) }
        var hideAll = true
        let source = FeedDataSource(remoteRepository: repo, filterItems: { hideAll ? [] : $0 }, homeContractAvailable: true)
        let vm = FeedViewModel(feedLoader: source,
            weeklyProgressProvider: StubWeeklyProgressProvider(result: .failure(StubError.failed)),
            recoveryPreviewProvider: StubRecoveryPreviewProvider(result: .failure(StubError.failed)),
            streakDatesProvider: StubStreakDatesProvider(result: .failure(StubError.failed)), initialAudience: .home)
        await vm.load()
        XCTAssertTrue(vm.readModel.items.isEmpty); XCTAssertTrue(vm.readModel.hasMore)
        XCTAssertNotNil(vm.readModel.remoteCoverageStart)
        let progress = vm.readModel.paginationRevision
        hideAll = false; await vm.loadMore()
        XCTAssertEqual(repo.offsets, [0, 8]); XCTAssertEqual(vm.readModel.items.count, 8)
        XCTAssertEqual(vm.readModel.paginationRevision, progress + 1)
    }
    func testSecondFullPageWithUnchangedVisibleRowsAdvancesToThirdFollowingPage() async {
        let repo = Repository(), owner = UUID(), hidden = UUID(), following = UUID()
        repo.items = (0..<24).map { index in
            item(owner: index < 8 ? owner : (index < 16 ? hidden : following), local: false, date: 1_800_000_000 - Double(index))
        }
        let source = FeedDataSource(remoteRepository: repo, filterItems: { $0.filter { $0.authorId != hidden } }, homeContractAvailable: true)
        let vm = FeedViewModel(feedLoader: source,
            weeklyProgressProvider: StubWeeklyProgressProvider(result: .failure(StubError.failed)),
            recoveryPreviewProvider: StubRecoveryPreviewProvider(result: .failure(StubError.failed)),
            streakDatesProvider: StubStreakDatesProvider(result: .failure(StubError.failed)), initialAudience: .home)
        await vm.load()
        let firstIDs = vm.readModel.items.map(\.id), progress = vm.readModel.paginationRevision
        XCTAssertEqual(firstIDs.count, 8)
        await vm.loadMore()
        XCTAssertEqual(repo.offsets, [0, 8]); XCTAssertTrue(vm.readModel.hasMore)
        XCTAssertEqual(vm.readModel.items.map(\.id), firstIDs)
        XCTAssertEqual(vm.readModel.paginationRevision, progress + 1)
        await vm.loadMore()
        XCTAssertEqual(repo.offsets, [0, 8, 16])
        XCTAssertEqual(vm.readModel.items.filter { $0.authorId == following }.count, 8)
        XCTAssertEqual(vm.readModel.items.count, 16)
        XCTAssertEqual(vm.readModel.paginationRevision, progress + 2)
    }
    func testPostgRESTSixFractionTimestampParsesAndKeepsNormalDescendingOrder() throws {
        let viewer = UUID(), owner = UUID()
        let first = PreviewLegacyPublicSummary(post_id: UUID(), owner_id: owner, sport: "cycling", activity_at: "2026-11-01T00:00:02.123456+00:00", duration_seconds: 3600, distance_meters: 10000)
        let second = PreviewLegacyPublicSummary(post_id: UUID(), owner_id: owner, sport: "cycling", activity_at: "2026-11-01T00:00:01.654321+00:00", duration_seconds: 3600, distance_meters: 10000)
        XCTAssertNotNil(first.date); XCTAssertGreaterThan(try XCTUnwrap(first.date), try XCTUnwrap(second.date))
        XCTAssertNoThrow(try PreviewLegacyPublicSummary.validate([first, second], request: .init(viewerID: viewer, scope: .home, ownerID: nil, before: nil, limit: 8), postID: nil, now: Date(timeIntervalSince1970: 1_900_000_000), blocked: { _ in false }))
    }
}

private struct Feed66EmptyHomeRepository: FeedRepositoryProtocol {
    func fetchFeed(limit: Int) async throws -> [FeedItem] { [] }
    func fetchFeedPage(limit: Int, offset: Int, audience: FeedAudience) async throws -> [FeedItem] { [] }
    func fetchSavedPosts() async throws -> [FeedItem] { [] }
    func fetchPost(id: UUID) async throws -> FeedItem? { nil }
}

@MainActor private final class Feed66ReadinessHarnessState: ObservableObject {
    @Published var ready = false
    var retry = FeedInitialAuthorizationRetry()
    var consumed = 0
    func recheck() { if retry.consumeIfReady(ready) { consumed += 1 } }
}
private struct Feed66ReadinessHarness: View {
    @ObservedObject var state: Feed66ReadinessHarnessState
    var body: some View {
        Text("Synthetic readiness")
            .modifier(FeedInitialAuthorizationReadinessObserver(ready: state.ready, recheck: state.recheck))
    }
}
