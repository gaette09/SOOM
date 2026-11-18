import Combine
import SwiftData
import SwiftUI

/// Memory-only aggregate diagnostics. No IDs, paths, contents, timestamps, or sink.
/// Lifetime follows the account-scoped FeedViewContainer, bounded to 64 returns.
struct SOOMFeedReturnPerformance {
    enum Path: Int { case batch, failedBatch, fullMutation, fullFallback, fullMembership, fullUnsupported, cancelled }
    struct Sample {
        let path: Path
        let milliseconds: Int
        let hits: Int
        let misses: Int
        let evictions: Int
        let residentKiB: Int
    }
    private(set) var samples: [Sample] = []
    mutating func record(path: Path, seconds: Double, hits: Int, misses: Int, evictions: Int, bytes: Int) {
        guard seconds.isFinite, seconds >= 0 else { return }
        if samples.count == 64 { samples.removeFirst() }
        samples.append(.init(path: path, milliseconds: Int(min(600_000, seconds * 1_000)),
            hits: max(0, hits), misses: max(0, misses), evictions: max(0, evictions), residentKiB: max(0, bytes) / 1024))
    }
}

/// Keep one refresh owner. Reentry joins it; data mutations request one follow-up.
@MainActor
final class SOOMFeedRefreshCoordinator {
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
    }
    private var flight: Flight?
    private var draining: Flight?
    private var followUpPending = false
    private(set) var startedOperations = 0
    private(set) var joinedRequests = 0
    var isRefreshing: Bool { flight != nil }

    func refresh(requiresFollowUp: Bool, operation: @escaping @MainActor () async -> Void) async {
        if let flight {
            if requiresFollowUp { followUpPending = true }
            joinedRequests += 1
            await flight.task.value
            return
        }
        let id = UUID()
        let retiring = draining
        let task = Task { @MainActor [self] in
            // Cancellation is cooperative. Do not let the new operation enter
            // FeedViewModel.load while its previous load still owns the flag.
            if let retiring {
                let drainTrace = LoadTrace("feed-cancel-drain")
                await retiring.task.value
                drainTrace.mark("prior-owner-finished")
                if draining?.id == retiring.id { draining = nil }
            }
            repeat {
                followUpPending = false
                guard !Task.isCancelled else { break }
                startedOperations += 1
                await operation()
            } while followUpPending && !Task.isCancelled && flight?.id == id
            if flight?.id == id { flight = nil }
        }
        flight = Flight(id: id, task: task)
        await task.value
    }

    func cancel() {
        let current = flight
        flight = nil
        followUpPending = false
        current?.task.cancel()
        if let current {
            let prior = draining
            draining = Flight(id: UUID(), task: Task { @MainActor in
                await prior?.task.value
                await current.task.value
            })
        }
    }
}

/// Scheduling state only. This never creates or retains an authorization grant.
struct FeedInitialAuthorizationRetry {
    private(set) var pending = false
    mutating func deferUntilReady() { pending = true }
    mutating func authorizeNowOrDefer(ready: Bool) -> Bool {
        pending = !ready
        return ready
    }
    mutating func invalidate() { pending = false }
    mutating func consumeIfReady(_ ready: Bool) -> Bool {
        guard pending, ready else { return false }
        pending = false
        return true
    }
}

/// Shared by production and the lifecycle delivery regression harness.
struct FeedInitialAuthorizationReadinessObserver: ViewModifier {
    let ready: Bool
    let recheck: () -> Void
    func body(content: Content) -> some View {
        content
            .onChange(of: ready) { _, _ in recheck() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                recheck()
            }
    }
}

private struct SOOMFeedActiveKey: EnvironmentKey {
    static let defaultValue = true
}
private struct SOOMFeedPhotoPresentationKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}
private struct SOOMFeedBatchCurrentKey: EnvironmentKey {
    static let defaultValue: ((UUID) -> Bool)? = nil
}
private struct SOOMFeedRevalidationKey: EnvironmentKey {
    static let defaultValue = 0
}
extension EnvironmentValues {
    var soomFeedBatchIsCurrent: ((UUID) -> Bool)? {
        get { self[SOOMFeedBatchCurrentKey.self] }
        set { self[SOOMFeedBatchCurrentKey.self] = newValue }
    }
    var soomFeedPhotoPresentationID: UUID? {
        get { self[SOOMFeedPhotoPresentationKey.self] }
        set { self[SOOMFeedPhotoPresentationKey.self] = newValue }
    }
    var soomFeedIsActive: Bool {
        get { self[SOOMFeedActiveKey.self] }
        set { self[SOOMFeedActiveKey.self] = newValue }
    }
    var soomFeedRevalidationRevision: Int {
        get { self[SOOMFeedRevalidationKey.self] }
        set { self[SOOMFeedRevalidationKey.self] = newValue }
    }
}


#if DEBUG && targetEnvironment(simulator)
/// Isolated test transport injection. Uses the production VM/projection and
/// adapter validation; no production service or authorization bypass is allowed.
@MainActor final class FeedContainerProductionTestDependencies {
    let repository: any FeedRepositoryProtocol
    let readBatch: (FeedReturnBatchParameters, [AccountActivityFeedRow]) async throws -> Data
    var didCreateViewModel: ((FeedViewModel) -> Void)?
    var didPublishBatch: ((FeedReturnBatchPresentation) -> Void)?
    init(repository: any FeedRepositoryProtocol,
         readBatch: @escaping (FeedReturnBatchParameters, [AccountActivityFeedRow]) async throws -> Data) {
        self.repository = repository; self.readBatch = readBatch
    }
    func requireSyntheticHost() {
        precondition(ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1")
        precondition(!AuthEnvironmentLoader().load().isSupabaseConfigured)
    }
}
#endif

struct FeedViewContainer: View {
    #if DEBUG && targetEnvironment(simulator)
    var productionTestDependencies: FeedContainerProductionTestDependencies?
    #endif
    var isActive = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var revalidationRevision = 0
    @State private var photoPresentationID = UUID()
    @State private var routePlaybackHistory = FeedRoutePlaybackHistory()
    @State private var cardGeometry = FeedCardGeometryStore()
    private var cardGeometryScope: FeedCardGeometryScope {
        .init(viewerID: safetyStore.viewerID, generation: safetyStore.accountGeneration, safetyRevision: safetyStore.revision)
    }
    // Content caching and fresh return authorization remain separate. The
    // current presentation is withheld until its new revision is verified.
    @State private var presentationIsActive = false
    @State private var inactiveTransitionCount = 0
    @State private var backgroundTransitionCount = 0
    #if DEBUG && targetEnvironment(simulator)
    @State private var refreshOperationCount = 0
    @State private var qaFeedGeneration = 0
    #endif
    @State private var refreshCoordinator = SOOMFeedRefreshCoordinator()
    @State private var ownerProjectionMemo = FeedOwnerProjectionOperationMemo<FeedOwnerProjectionOperationKey, OwnerWorkoutFeedProjection.Snapshot>()
    @StateObject private var returnBatch = FeedReturnBatchStore()
    @State private var pendingFullRefresh = false
    @State private var fullRefreshInProgress = false
    @State private var pendingResidentRevalidation = false
    @State private var returnPerformance = SOOMFeedReturnPerformance()
    @State private var batchUnsupportedForPage = false
    @State private var visibleBatchTask: Task<Void, Never>?
    @State private var initialAuthorizationRetry = FeedInitialAuthorizationRetry()
    let activitySync: AccountActivitySyncOrchestrator?
    let onNavigateToClubs: () -> Void
    let onNavigateToRouteRecommendation: () -> Void

    @ObservedObject private var safetyStore = CommunitySafetyStore.shared
    #if DEBUG && targetEnvironment(simulator)
    @ObservedObject private var staleCacheDiagnostics = FeedStaleSummaryCache.shared
    #endif
    @EnvironmentObject private var healthStorage: HealthAccountStorageController
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var previewEnabled = false
    @State private var viewModel: FeedViewModel?
    @State private var lastLoadedDataRevision: Int?
    @State private var readModelObservation: AnyCancellable?
    @State private var readModel = FeedReadModel.loading
    @State private var notificationFetcher: (any NotificationInboxFetching)?
    @State private var profileFetcher: (any FeedRemoteProfileFetching)?

    init(
        isActive: Bool = true,
        activitySync: AccountActivitySyncOrchestrator? = nil,
        onNavigateToClubs: @escaping () -> Void = {},
        onNavigateToRouteRecommendation: @escaping () -> Void = {}
    ) {
        self.isActive = isActive
        self.activitySync = activitySync
        self.onNavigateToClubs = onNavigateToClubs
        self.onNavigateToRouteRecommendation = onNavigateToRouteRecommendation
    }

    var body: some View {
        FeedView(
            audience: viewModel?.audience ?? .home,
            onSelectAudience: { value in await viewModel?.selectAudience(value); readModel = viewModel?.readModel ?? .loading },
            items: readModel.items,
            weeklySnapshot: readModel.weeklySnapshot,
            recoveryInsight: readModel.recoveryInsight,
            streak: readModel.streak,
            isLoading: readModel.showsInitialLoading,
            loadFailure: readModel.loadFailure,
            hasMore: readModel.hasMore,
            paginationRevision: readModel.paginationRevision,
            paginationWakeRevision: readModel.paginationWakeRevision,
            paginationIsReady: !usesVisibleBatch || returnBatch.presentation?.phase == .ready,
            isLoadingMore: readModel.isLoadingMore,
            loadMoreFailure: readModel.loadMoreFailure,
            onRefresh: { revalidationRevision += 1; await refreshFeed() },
            onLoadMore: loadMoreFeed,
            onRetryLoadMore: retryLoadMoreFeed,
            notificationFetcher: notificationFetcher,
            profileFetcher: profileFetcher,
            resolveNotificationPost: { id in await viewModel?.resolveFeedItem(postId: id) },
            onRevealNotificationPost: { item in
                viewModel?.includeNotificationItem(item)
                readModel = viewModel?.readModel ?? readModel
            },
            onToggleCheer: { item in
                Task {
                    await viewModel?.toggleCheer(for: item)
                    readModel = viewModel?.readModel ?? readModel
                }
            },
            onToggleSave: { item in
                Task {
                    await viewModel?.toggleSave(for: item)
                    readModel = viewModel?.readModel ?? readModel
                }
            },
            onSubmitComment: { item, body in
                guard let viewModel else { throw CommunitySafetyError.unavailable }
                try await viewModel.postComment(body, on: item)
                readModel = viewModel.readModel
            },
            onDeletePost: { item in
                Task {
                    await viewModel?.deletePost(item)
                    readModel = viewModel?.readModel ?? readModel
                }
            },
            onNavigateToClubs: onNavigateToClubs,
            onNavigateToRouteRecommendation: onNavigateToRouteRecommendation,
            onFirstCardDisplay: { viewModel?.recordFirstCardDisplay() }
        )
        #if DEBUG && targetEnvironment(simulator)
        .modifier(Feed60DebugRecreationModifier(generation: qaFeedGeneration))
        #endif
        .environment(\.soomFeedIsActive, isActive && scenePhase == .active && presentationIsActive)
        .environment(\.soomFeedRevalidationRevision, revalidationRevision)
        .environment(\.soomFeedReturnBatch, usesVisibleBatch ? returnBatch.presentation : nil)
        .environment(\.soomFeedBatchIsCurrent, usesVisibleBatch ? { id in
            // Reference-store read, not a captured Environment receipt. This
            // rejects old closures synchronously before SwiftUI propagates state.
            return returnBatch.isCurrent(id: id, context: returnBatchContext)
        } : nil)
        .environment(\.soomFeedCardGrantIsCurrent, usesVisibleBatch ? { authority in
            returnBatch.isCurrent(authority: authority, context: returnBatchContext)
        } : nil)
        .environment(\.soomFeedReturnRetry, usesVisibleBatch ? { cardID in retryVisibleBatch(cardID: cardID) } : nil)
        .environment(\.soomFeedViewportCards, usesVisibleBatch ? { ids in
            guard isActive, scenePhase == .active else { return }
            returnBatch.setViewport(ids)
        } : nil)
        .environment(\.soomFeedVisibleCardRegistration, usesVisibleBatch ? { id, visible in
            returnBatch.register(cardID: id, visible: visible)
        } : nil)
        .modifier(FeedInitialAuthorizationReadinessObserver(ready: returnBatchContext != nil,
            recheck: retryInitialAuthorizationIfReady))
        .onChange(of: returnBatch.visibleRevision) { _, _ in scheduleVisibleBatch() }
        .onChange(of: returnBatch.commitRevision) { _, _ in scheduleVisibleBatch() }
        .environment(\.soomFeedCardGeometryStore, cardGeometry)
        .onChange(of: cardGeometryScope, initial: true) { _, scope in cardGeometry.reset(to: scope) }
        .environment(\.soomFeedPhotoPresentationID, photoPresentationID)
        .environment(\.soomFeedRoutePlaybackHistory, routePlaybackHistory)
        .environment(\.soomFeedLinkedCardStore, usesVisibleBatch ? returnBatch.linkedCards : nil)
        .environment(\.soomFeedSocialPresentationStore, usesVisibleBatch ? returnBatch.socialPresentations : nil)
        .environment(\.soomFeedSocialPresentationRevision, returnBatch.socialPresentations.revision)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            returnBatch.linkedCards.clear()
            returnBatch.socialPresentations.purgeForMemoryPressure()
        }
        .onChange(of: isActive) { _, active in
            if active { revalidateOnReturn(isTabReturn: true) }
            else { visibleBatchTask?.cancel() } // A foreground tab change is not an authority boundary.
        }
        .environment(\.soomActivityPreview, AccountActivityReadPolicy.deployed == .approvedFollowersV1 && previewEnabled)
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive { inactiveTransitionCount += 1 }
            if phase == .background { backgroundTransitionCount += 1 }
            if phase == .active { if isActive { revalidateOnReturn() } }
            else { suspendPresentation() }
        }
        .onReceive(WorkoutPhotoImageCache.shared.resourceVersionChanges) { change in
            guard isActive, scenePhase == .active, presentationIsActive else { return }
            if usesVisibleBatch {
                // A changed object closes only its owning card grant. Other
                // cards retain their exact existing authorization and layout.
                if returnBatch.invalidateResource(change.resource) { scheduleVisibleBatch() }
            } else {
                revalidationRevision += 1
                Task { await refreshFeed(fullReload: true, requiresFollowUp: true) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            ownerProjectionMemo.invalidate()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // Also observed while a navigation destination covers the feed.
            suspendPresentation()
        }
        .onAppear { if isActive { revalidateOnReturn() } }
        .onDisappear { suspendPresentation() }
        #if DEBUG && targetEnvironment(simulator)
        .overlay(alignment: .topLeading) {
            if ProcessInfo.processInfo.environment["SOOM_FEED_LIFECYCLE_QA"] == "1" {
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    VStack(alignment: .leading) {
                        Text(verbatim: "liveHeight=\(FeedStaleSummaryCache.shared.firstVerifiedHeight);cachedHeight=\(FeedStaleSummaryCache.shared.firstPresentedHeight);cacheLayouts=\(FeedStaleSummaryCache.shared.layoutCount);disk=\(FeedStaleSummaryCache.shared.diskDiagnostic);restoreAllowed=\(staleRestoreScope != nil ? 1 : 0);cacheGen=\(safetyStore.accountGeneration);cacheSafety=\(safetyStore.revision);staleCount=\(FeedStaleSummaryCache.shared.count);staleBytes=\(FeedStaleSummaryCache.shared.totalBytes);batchTrace=\(FeedReturnBatchDemo.requestTargets.joined(separator: "|"));summaryHeld=\(Feed64SummaryGate.isHeld ? 1 : 0);inactiveEvents=\(inactiveTransitionCount);backgroundEvents=\(backgroundTransitionCount);ownPlaceholder=\(Feed61CardLifecycleProbe.ownPlaceholderBranchAppearances);foreignPlaceholder=\(Feed61CardLifecycleProbe.foreignPlaceholderBranchAppearances);ownLifetimes=\(Feed61CardLifecycleProbe.ownLifetimeCount);foreignLifetimes=\(Feed61CardLifecycleProbe.foreignLifetimeCount);ownImmediate=\(Feed61CardLifecycleProbe.ownImmediateReadyAppearances);mapReplays=\(Feed61RoutePlaybackProbe.mapReplays);mixedRequests=\(Feed61MixedReuseDemo.pageRequests);granted=\(returnBatch.presentation?.grants.count ?? 0);requested=\(returnBatch.presentation?.requested.count ?? 0);pageRequests=\(Feed60PaginationDemo.pageRequests);pageHeld=\(Feed60PaginationDemo.heldCount);pageOffset=\(Feed60PaginationDemo.lastOffset);pageRows=\(viewModel?.loadedProjectionPrefix?.count ?? 0);pageUnique=\(Set((viewModel?.loadedProjectionPrefix ?? []).map(\.cardID)).count);pageMore=\(readModel.hasMore ? 1 : 0);pageFailure=\(readModel.loadMoreFailure != nil ? 1 : 0);linkedReads=\(returnBatch.linkedCards.startedReads);linkedHits=\(returnBatch.linkedCards.hits);linkedEntries=\(returnBatch.linkedCards.count);loads=\(refreshOperationCount);batch=\(returnBatch.requestCount);epoch=\(revalidationRevision);pixels=\(WorkoutPhotoImageCache.shared.pixels.statistics.misses);hits=\(WorkoutPhotoImageCache.shared.pixels.statistics.hits);cost=\(WorkoutPhotoImageCache.shared.pixels.totalCost);entries=\(WorkoutPhotoImageCache.shared.pixels.entryCount);evictions=\(WorkoutPhotoImageCache.shared.pixels.statistics.evictions);invalidations=\(WorkoutPhotoImageCache.shared.pixels.statistics.invalidations);inflight=\(WorkoutPhotoImageCache.shared.pixels.inFlightCount);avatarVisible=\(FeedAvatarImageCache.shared.syntheticPresentedOwners.count);avatarMiss=\(FeedAvatarImageCache.shared.pixels.statistics.misses);avatarHit=\(FeedAvatarImageCache.shared.pixels.statistics.hits);held=\(FeedReturnBatchDemo.heldRequests.count);returnMs=\(returnPerformance.samples.last?.milliseconds ?? -1);returnPath=\(returnPerformance.samples.last?.path.rawValue ?? -1);phase=\(String(describing: returnBatch.presentation?.phase))")
                            .font(.system(size: 8)).lineLimit(1).frame(width: 1, height: 1).opacity(0.01)
                            .accessibilityIdentifier("feed.lifecycle.probe")
                        if Feed64SummaryGate.isHeld {
                            Button("합성 보조 집계 진행") { Feed64SummaryGate.release() }
                                .accessibilityIdentifier("feed.summary.release")
                        }
                        if FeedMemoryPurgeDiagnostic.enabled {
                            Button("합성 메모리 경고 1회") { FeedMemoryPurgeDiagnostic.postOnce() }
                                .accessibilityIdentifier("feed.memoryPurge.once")
                                .accessibilityValue(FeedMemoryPurgeDiagnostic.status)
                        }
                        if ProcessInfo.processInfo.environment["SOOM_FEED_ENRICHMENT_QA"] == "1" {
                            Button("합성 카드 다시 만들기") { qaFeedGeneration += 1 }
                                .accessibilityIdentifier("feed.lifecycle.recreate")
                        }
                        if ProcessInfo.processInfo.environment["SOOM_FEED_PAGINATION_QA"] == "1", Feed60PaginationDemo.heldCount > 0 {
                            Button("합성 다음 페이지 진행") { Feed60PaginationDemo.releaseSecondPage() }
                                .accessibilityIdentifier("feed.pagination.release")
                        }
                        if ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_HOLD_FIRST"] == "1" {
                            Button("합성 초기 요청 합류") { Task { await refreshFeed(fullReload: true, requiresFollowUp: false) } }
                                .accessibilityIdentifier("feed.lifecycle.joinInitial")
                        }
                        if ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_HOLD_RETURN"] == "1", !FeedReturnBatchDemo.heldRequests.isEmpty {
                            Button("합성 응답 진행") { FeedReturnBatchDemo.releaseHeldRequests() }
                                .accessibilityIdentifier("feed.lifecycle.release")
                        }
                    }
                }
            }
        }
        #endif
        .navigationDestination(for: NativeNotificationRouteTarget.self) { target in
            NotificationInboxView(fetcher:notificationFetcher,profileFetcher:profileFetcher,
                onSelectPost:{_,_ in},onMarkedAllRead:{},incomingNativePush:target.payload,
                standaloneNavigation:false,
                postDestination:{ request in
                    AnyView(FeedNotificationCardLoader(request:request,
                        resolve:{ await viewModel?.resolveFeedItem(postId:$0) },
                        onSubmitComment:{ item,body in
                            guard let viewModel else { throw CommunitySafetyError.unavailable }
                            try await viewModel.postComment(body,on:item)
                        }, onToggleCheer:{ item in Task { await viewModel?.toggleCheer(for:item) } },
                        onToggleSave:{ item in Task { await viewModel?.toggleSave(for:item) } },
                        onDeletePost:{ _ in
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["SOOM_PROJECTION_DEEP_QA"] == "1" { ProjectionVerificationProbe.trace("global-didChange revision=\(revalidationRevision)->\(revalidationRevision + 1)") }
            #endif
            revalidationRevision += 1; Task { await refreshFeed() }
        }))
                })
        }
        .navigationDestination(for: FeedPostRouteTarget.self) { target in
            FeedNotificationDetailLoader(
                postId: target.postId,
                resolve: { postId in
                    await viewModel?.resolveFeedItem(postId: postId) ?? nil
                },
                onSubmitComment: { item, body in
                    guard let viewModel else { throw CommunitySafetyError.unavailable }
                    try await viewModel.postComment(body, on: item)
                    readModel = viewModel.readModel
                }
            )
        }
        .onChange(of: safetyStore.revision) { _, _ in
            ownerProjectionMemo.invalidate()
            suspendPresentation()
            viewModel?.invalidateForSafetyChange()
            readModel = viewModel?.readModel ?? .loading
            readModel.isLoading = true
            if isActive { revalidateOnReturn() }
        }
        .onReceive(NotificationCenter.default.publisher(for: WorkoutRecordManagement.didChange)) { notification in
            ownerProjectionMemo.invalidate()
            if isPassiveOwnReadback(notification) { return }
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["SOOM_PROJECTION_DEEP_QA"] == "1" { ProjectionVerificationProbe.trace("global-didChange revision=\(revalidationRevision)->\(revalidationRevision + 1)") }
            #endif
            revalidationRevision += 1; Task { await refreshFeed() }
        }
        .onReceive(NotificationCenter.default.publisher(for: FeedPostManagement.didChange)) { _ in
            ownerProjectionMemo.invalidate()
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["SOOM_PROJECTION_DEEP_QA"] == "1" { ProjectionVerificationProbe.trace("global-didChange revision=\(revalidationRevision)->\(revalidationRevision + 1)") }
            #endif
            revalidationRevision += 1; Task { await refreshFeed() }
        }
        .task(id: staleRestoreScope) {
            guard let scope = staleRestoreScope else { return }
            let trace = LoadTrace("feed-cache-restore")
            await FeedStaleSummaryCache.shared.restore(viewerID: scope.viewerID,
                generation: scope.generation, safetyRevision: scope.safetyRevision)
            trace.mark("restore-returned")
        }
        .task(id: healthStorage.dataRevision) {
            let entryTrace = LoadTrace("feed-storage-entry")
            let revision = healthStorage.dataRevision
            if viewModel == nil {
                #if DEBUG && targetEnvironment(simulator)
                // Exercise the actual production selector with an old capability.
                // No fake grants, counters, RPC responses, or permission bypass.
                if ReviewDemoMode.isActive,
                   ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
                   ProcessInfo.processInfo.environment["SOOM_FEED_LEGACY_PREVIEW_CAPABILITY_QA"] == "1" {
                    previewEnabled = true
                }
                #endif
                if Feed61ActivationPolicy.needsLegacyPreviewCapability(readPolicy: AccountActivityReadPolicy.deployed),
                   !ReviewDemoMode.isActive, let owner = healthStorage.userID,
                   let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() {
                    previewEnabled = (try? await AccountActivityPreviewService(client: client, owner: owner).capability().enabled) == true
                    guard !Task.isCancelled, owner == healthStorage.userID else { return }
                }
                let (vm, remoteClient) = makeProductionViewModel()
                viewModel = vm
                readModelObservation = vm.$readModel.sink { [weak vm] updated in
                    Task { @MainActor in
                        guard let vm, viewModel === vm, vm.readModel == updated else { return }
                        readModel = updated
                    }
                }
                notificationFetcher = ReviewDemoMode.isActive ? ReviewDemoCommunityStore.shared : remoteClient
                profileFetcher = ReviewDemoMode.isActive ? ReviewDemoCommunityStore.shared : remoteClient
            }
            guard lastLoadedDataRevision != revision else { return }
            let isInitialLoad = lastLoadedDataRevision == nil
            lastLoadedDataRevision = revision
            // Appearance and the first storage task describe one load. A real
            // subsequent storage mutation must still queue a fresh follow-up.
            entryTrace.mark("view-model-ready")
            await refreshFeed(requiresFollowUp: !isInitialLoad)
            entryTrace.mark("refresh-returned")
        }
    }

    private var staleRestoreScope: FeedStaleSummaryScope? {
        guard FeedStaleSummaryCache.shared.enabled, safetyStore.canUseSocial,
              let viewer = authViewModel.session.currentUser?.id, viewer == safetyStore.viewerID,
              healthStorage.userID == viewer else { return nil }
        return .init(viewerID: viewer, generation: safetyStore.accountGeneration,
            safetyRevision: safetyStore.revision, policyVersion: 1)
    }

    private func isPassiveOwnReadback(_ notification: Notification) -> Bool {
        guard let owner = healthStorage.userID, owner == safetyStore.viewerID,
              HealthCloudJournal.accountID(for: modelContext) == owner,
              modelContext.container === healthStorage.container, !HealthCloudJournal.isRetired(modelContext),
              let id = WorkoutRecordChange.passiveReadbackWorkoutID(notification, viewerID: safetyStore.viewerID,
                  authOwnerID: authViewModel.session.currentUser?.id, generation: safetyStore.accountGeneration) else { return false }
        var query = FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 1
        guard (try? modelContext.fetch(query).first?.id) == id else { return false }
        // The owning Host's existing @Query/adopt has the local change. No
        // server permissions or other people's rows changed during readback.
        #if DEBUG && targetEnvironment(simulator)
        ProjectionVerificationProbe.trace("passive-local-only workout=\(id) globalRevision=\(revalidationRevision)")
        #endif
        return true
    }

    private func revalidateOnReturn(isTabReturn: Bool = false) {
        // onAppear, scene activation and tab selection may describe one return.
        // Publish active + revision in one synchronous state transition. A row
        // must never validate the old revision just before the new one arrives.
        guard isActive, scenePhase == .active else { return }
        if presentationIsActive {
            guard isTabReturn else { return }
            // Keep already-authorized content in this foreground account scope.
            // Recheck in place; denial, version changes and membership changes
            // still revoke through the existing batch publication path.
            pendingResidentRevalidation = true
            Task { await refreshFeed(fullReload: false, requiresFollowUp: true) }
            return
        }
        revalidationRevision += 1
        if let scope = staleRestoreScope {
            FeedStaleSummaryCache.shared.beginDisplayWindow(scope: scope, returnEpoch: revalidationRevision)
        }
        presentationIsActive = true
        if usesVisibleBatch, let context = returnBatchContext { returnBatch.begin(context: context) }
        Task { await refreshFeed(fullReload: false, requiresFollowUp: false) }
    }

    private func retryInitialAuthorizationIfReady() {
        guard usesVisibleBatch,
              initialAuthorizationRetry.consumeIfReady(returnBatchContext != nil) else { return }
        // Re-enter the existing serialized, fail-closed authorization pipeline.
        // A ready transition schedules once; failed/denied reads do not poll.
        Task { await refreshFeed(fullReload: false, requiresFollowUp: true) }
    }

    private func suspendPresentation() {
        initialAuthorizationRetry.invalidate()
        ownerProjectionMemo.invalidate()
        presentationIsActive = false
        pendingResidentRevalidation = false
        readModel.isLoading = true
        visibleBatchTask?.cancel()
        returnBatch.invalidate()
        refreshCoordinator.cancel()
    }

    private var usesVisibleBatch: Bool {
        Feed61ActivationPolicy.usesVisibleBatch(releaseEnabled: FeedReturnBatchReleaseGate.enabled,
            readPolicy: AccountActivityReadPolicy.deployed, legacyPreviewEnabled: previewEnabled,
            audience: viewModel?.audience ?? .home, pageUnsupported: batchUnsupportedForPage)
    }
    private var returnBatchContext: FeedReturnBatchContext? {
        guard isActive, scenePhase == .active, presentationIsActive, safetyStore.canUseSocial,
              let viewer = safetyStore.viewerID, healthStorage.userID == viewer,
              (ReviewDemoMode.isActive ? ReviewDemoMode.userID : authViewModel.session.currentUser?.id) == viewer,
              UIApplication.shared.applicationState == .active,
              !AccountDeletionWriteFence.shared.isRetired(viewer) else { return nil }
        return .init(viewerID: viewer, accountGeneration: safetyStore.accountGeneration,
                     safetyRevision: safetyStore.revision, returnEpoch: revalidationRevision)
    }
    private func retryVisibleBatch(cardID: UUID) {
        guard usesVisibleBatch, let context = returnBatchContext,
              viewModel?.loadedProjectionPrefix?.contains(where: { $0.cardID == cardID }) == true,
              returnBatch.beginRetry(context: context) else { return }
        readModel.isLoading = true; readModel.loadFailure = nil; readModel.hasMore = false
        // If a failed operation is still unwinding, explicitly enqueue exactly
        // one follow-up. Joining alone would swallow this user-authorized retry.
        Task { await refreshFeed(fullReload: false, requiresFollowUp: true) }
    }
    private func failVisibleBatch(expectedID: UUID) {
        guard returnBatch.presentation?.id == expectedID else { return }
        returnBatch.fail(expectedID: expectedID)
        readModel.isLoading = false; readModel.isLoadingMore = false
        readModel.loadFailure = .remoteFailed; readModel.hasMore = false
    }
    private func scheduleVisibleBatch() {
        guard usesVisibleBatch, returnBatch.presentation?.phase == .ready,
              let rows = viewModel?.loadedProjectionPrefix,
              !returnBatch.targets(loadedRows: rows, missingOnly: true).isEmpty else { return }
        visibleBatchTask?.cancel()
        visibleBatchTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
            guard !Task.isCancelled, returnBatchContext != nil else { return }
            await refreshFeed(fullReload: false, requiresFollowUp: true)
        }
    }
    private enum BatchOutcome { case applied, pageReload, failed, unsupported }
    private func verifyVisibleBatch(_ vm: FeedViewModel, revalidateResident: Bool = false) async -> BatchOutcome {
        let trace = LoadTrace("feed-visible-batch")
        guard usesVisibleBatch else { trace.mark("unsupported-contract-or-page"); return .unsupported }
        guard let context = returnBatchContext else { trace.mark("unsupported-no-current-context"); return .unsupported }
        guard let rows = vm.loadedProjectionPrefix, rows.count <= 500 else {
            trace.mark("unsupported-prefix"); return .unsupported
        }
        initialAuthorizationRetry.invalidate()
        let id: UUID
        if let old = returnBatch.presentation, old.context == context { id = old.id }
        else { id = returnBatch.begin(context: context) }
        let merging = returnBatch.presentation?.phase == .ready
        let targets = returnBatch.targets(loadedRows: rows, missingOnly: merging && !revalidateResident)
        trace.mark("prefix-\(rows.count)-targets-\(targets.count)")
        if merging && targets.isEmpty { return .applied }
        do {
            let reader: FeedReturnBatchAdapter
            #if DEBUG && targetEnvironment(simulator)
            if let productionTestDependencies {
                productionTestDependencies.requireSyntheticHost()
                reader = FeedReturnBatchAdapter(read: { parameters in
                    try await productionTestDependencies.readBatch(parameters, rows)
                }, current: { returnBatchContext }, expectedVersion: 3)
            } else if ReviewDemoMode.isActive {
                reader = FeedReturnBatchAdapter(read: { parameters in
                    try await FeedReturnBatchDemo.read(parameters, rows: rows)
                }, current: { returnBatchContext }, expectedVersion: ProcessInfo.processInfo.environment["SOOM_FEED_CARD_PREVIEW_V3_QA"] == "1" ? 3 : 2)
            } else {
                guard let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
                      client.auth.currentSession?.user.id == context.viewerID else { throw FeedReturnBatchError.changed }
                reader = .init(client: client, current: { returnBatchContext })
            }
            #else
            guard let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
                  client.auth.currentSession?.user.id == context.viewerID else { throw FeedReturnBatchError.changed }
            reader = .init(client: client, current: { returnBatchContext })
            #endif
            returnBatch.countRequest()
            let value = try await reader.load(cardIDs: targets, loadedRows: rows, context: context, id: id)
            trace.mark("response")
            guard !Task.isCancelled, viewModel === vm, returnBatchContext == context,
                  returnBatch.presentation?.id == id else { return .failed }
            if value.needsPageReload || !vm.applyVisibleBatch(value) {
                returnBatch.invalidateForMembershipChange(value)
                return .pageReload
            }
            guard returnBatch.publish(value, expectedID: id, merging: merging) else { return .failed }
            trace.mark("grants-published")
            #if DEBUG && targetEnvironment(simulator)
            productionTestDependencies?.didPublishBatch?(value)
            #endif
            readModel = vm.readModel
            return .applied
        } catch {
            if !Task.isCancelled, returnBatchContext == context { failVisibleBatch(expectedID: id) }
            return .failed
        }
    }
    private func refreshFeed(fullReload: Bool = true, requiresFollowUp: Bool = true) async {
        guard safetyStore.canUseSocial || (previewEnabled && safetyStore.canUseActivityPreview), let viewModel else { return }
        // Retained offscreen views must not create a refresh owner whose View
        // value permanently captures isActive=false. Keep mutations pending;
        // activation will start the serialized operation with the current View.
        guard isActive, scenePhase == .active, presentationIsActive else {
            if fullReload { pendingFullRefresh = true }
            return
        }
        let joinsFullOwner = refreshCoordinator.isRefreshing && fullRefreshInProgress
        if fullReload && (!joinsFullOwner || requiresFollowUp) { pendingFullRefresh = true }
        // Only the operation owner may replace the presentation receipt. A
        // joining initial callback must not orphan the pending batch ID.
        let needsFollowUp = requiresFollowUp || (fullReload && refreshCoordinator.isRefreshing && !fullRefreshInProgress)
        await refreshCoordinator.refresh(requiresFollowUp: needsFollowUp) {
            guard !Task.isCancelled, self.viewModel === viewModel,
                  modelContext.container === healthStorage.container else { return }
            let projectionOperation = ownerProjectionMemo.begin()
            defer { ownerProjectionMemo.end(projectionOperation) }
            let started = ContinuousClock.now
            let initialStatistics = WorkoutPhotoImageCache.shared.pixels.statistics
            var performancePath: SOOMFeedReturnPerformance.Path = .cancelled
            defer {
                let duration = started.duration(to: .now).components
                let latest = WorkoutPhotoImageCache.shared.pixels.statistics
                returnPerformance.record(path: performancePath,
                    seconds: Double(duration.seconds) + Double(duration.attoseconds) / 1e18,
                    hits: latest.hits - initialStatistics.hits, misses: latest.misses - initialStatistics.misses,
                    evictions: latest.evictions - initialStatistics.evictions,
                    bytes: WorkoutPhotoImageCache.shared.pixels.totalCost)
            }
            let full = pendingFullRefresh || !usesVisibleBatch
            fullRefreshInProgress = full
            defer { fullRefreshInProgress = false }
            if full { performancePath = pendingFullRefresh ? .fullMutation : .fullFallback }
            pendingFullRefresh = false
            let revalidateResident = pendingResidentRevalidation
            pendingResidentRevalidation = false
            if !full {
                switch await verifyVisibleBatch(viewModel, revalidateResident: revalidateResident) {
                case .applied: performancePath = .batch; return
                case .failed: performancePath = Task.isCancelled ? .cancelled : .failedBatch; return
                case .pageReload: performancePath = .fullMembership
                case .unsupported: performancePath = .fullUnsupported
                }
            }
            #if DEBUG && targetEnvironment(simulator)
            refreshOperationCount += 1
            #endif
            let pipelineTrace = LoadTrace("feed-load-pipeline")
            readModel.isLoading = true
            if healthStorage.userID != nil { try? await safetyStore.refreshBlockedUsers() }
            pipelineTrace.mark("blocked-users-complete")
            guard !Task.isCancelled, self.viewModel === viewModel,
                  modelContext.container === healthStorage.container else { return }
            await reconcileOwnerActivityCandidate()
            pipelineTrace.mark("owner-reconcile-complete")
            guard !Task.isCancelled, self.viewModel === viewModel,
                  modelContext.container === healthStorage.container else { return }
            var primaryBatchHandled = false
            await viewModel.load(awaitSupplementaryContent: false, onPrimaryContentReady: {
                guard !Task.isCancelled, self.viewModel === viewModel else { return }
                pipelineTrace.mark("page-ready")
                readModel = viewModel.readModel
                batchUnsupportedForPage = viewModel.loadedProjectionPrefix == nil || (viewModel.loadedProjectionPrefix?.count ?? 0) > 500
                let authorizeNow = usesVisibleBatch && initialAuthorizationRetry.authorizeNowOrDefer(ready: returnBatchContext != nil)
                if usesVisibleBatch && !authorizeNow { pipelineTrace.mark("primary-authorization-deferred-context") }
                if authorizeNow, let context = returnBatchContext {
                    primaryBatchHandled = true
                    returnBatch.begin(context: context)
                    if await verifyVisibleBatch(viewModel) == .pageReload,
                       let current = returnBatch.presentation { failVisibleBatch(expectedID: current.id) }
                    pipelineTrace.mark("card-authorization-complete")
                }
            })
            pipelineTrace.mark("primary-owner-released")
            guard !Task.isCancelled, self.viewModel === viewModel else { return }
            readModel = viewModel.readModel
            batchUnsupportedForPage = viewModel.loadedProjectionPrefix == nil || (viewModel.loadedProjectionPrefix?.count ?? 0) > 500
            let authorizeFallback = !primaryBatchHandled && usesVisibleBatch && initialAuthorizationRetry.authorizeNowOrDefer(ready: returnBatchContext != nil)
            if !primaryBatchHandled && usesVisibleBatch && !authorizeFallback { pipelineTrace.mark("final-authorization-deferred-context") }
            if authorizeFallback, let context = returnBatchContext {
                returnBatch.begin(context: context)
                // A failed page load still requires fresh authority for old rows.
                if await verifyVisibleBatch(viewModel) == .pageReload,
                   let current = returnBatch.presentation { failVisibleBatch(expectedID: current.id) }
            }
        }
    }

    /// Future reviewed staging hook. No producer is installed until an explicit
    /// staging authorization provider exists; account-public is not that grant.
    @MainActor private func reconcileOwnerActivityCandidate() async {
        if previewEnabled, let owner = healthStorage.userID, owner == safetyStore.viewerID,
           modelContext.container === healthStorage.container, !HealthCloudJournal.isRetired(modelContext),
           let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() {
            let service = AccountActivityPreviewService(client: client, owner: owner)
            if (try? await service.capability().owner_rules_accepted) == true {
                do {
                    let records = try modelContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>())
                    let inputs = try AccountActivityStageInput.canonicalInputs(records.map { UnifiedWorkoutPersistenceMapper().makeWorkout(from: $0) })
                    _ = try await service.syncAuthorized(inputs)
                } catch { /* Never auto-accept or retry an ambiguous write. Read refresh remains independent. */ }
            }
            return
        }
        guard AccountActivitySyncReleaseGate.productionReady, let activitySync,
              let owner = healthStorage.userID, owner == safetyStore.viewerID,
              modelContext.container === healthStorage.container, !HealthCloudJournal.isRetired(modelContext) else { return }
        let generation = safetyStore.accountGeneration, scope = healthStorage.scopeID
        do {
            let records = try modelContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>())
            let workouts = records.map { UnifiedWorkoutPersistenceMapper().makeWorkout(from: $0) }
            let inputs = try AccountActivityStageInput.canonicalInputs(workouts)
            guard generation == safetyStore.accountGeneration, scope == healthStorage.scopeID,
                  owner == healthStorage.userID, !Task.isCancelled else { return }
            _ = try await activitySync.reconcile(inputs)
        } catch {
            // Durable engine retains uncertain intents. Never turn a staging
            // failure into a second public post or change existing visibility.
        }
    }

    private func loadMoreFeed() async {
        guard !usesVisibleBatch || returnBatch.presentation?.phase == .ready else { return }
        guard let viewModel, !readModel.isLoadingMore, !readModel.isLoading else { return }
        let trace = LoadTrace("feed-pagination")
        readModel.isLoadingMore = true
        await viewModel.loadMore()
        trace.mark("page-result")
        readModel = viewModel.readModel
        scheduleVisibleBatch()
        trace.mark("batch-scheduled")
    }

    private func retryLoadMoreFeed() async {
        guard !usesVisibleBatch || returnBatch.presentation?.phase == .ready else { return }
        guard let viewModel, !readModel.isLoadingMore else { return }
        readModel.isLoadingMore = true
        readModel.loadMoreFailure = nil
        await viewModel.retryLoadMore()
        readModel = viewModel.readModel
        scheduleVisibleBatch()
    }

    @MainActor private func filterSecondaryCards(_ items: [FeedItem]) -> [FeedItem] {
        guard modelContext.container === healthStorage.container else { return [] }
        let records = (try? modelContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>())) ?? []
        let secondary = Set(records.filter { $0.preferredWorkoutID != nil && $0.preferredWorkoutID != $0.id }.map(\.id))
        return items.filter { item in
            guard item.isLocalDraft || item.authorId == healthStorage.userID,
                  let id = item.sourceWorkoutId else { return true }
            return !secondary.contains(id)
        }
    }

    @MainActor private func projectOwnerItems(_ items: [FeedItem]) -> [FeedItem] {
        let trace = LoadTrace("feed-owner-projection")
        guard !Task.isCancelled, let owner = healthStorage.userID,
              modelContext.container === healthStorage.container,
              !HealthCloudJournal.isRetired(modelContext) else { return [] }
        let scope = healthStorage.scopeID
        let key = FeedOwnerProjectionOperationKey(owner: owner, scope: scope,
            accountGeneration: safetyStore.accountGeneration, dataRevision: healthStorage.dataRevision,
            container: ObjectIdentifier(healthStorage.container), context: ObjectIdentifier(modelContext))
        guard let snapshot = try? ownerProjectionMemo.value(for: key, load: {
            trace.mark("local-scan-start")
            defer { trace.mark("local-scan-complete") }
            // This memo contains local owner data only. No stale remote post or
            // grant can be resurrected by a later merge after revocation.
            return try OwnerWorkoutFeedProjection.read(context: modelContext,
                storage: healthStorage, expectedOwnerID: owner, expectedScopeID: scope)
        }) else { return [] }
        guard !Task.isCancelled, healthStorage.userID == owner, healthStorage.scopeID == scope,
              healthStorage.dataRevision == key.dataRevision,
              safetyStore.accountGeneration == key.accountGeneration,
              modelContext.container === healthStorage.container,
              !HealthCloudJournal.isRetired(modelContext) else { return [] }
        let result = snapshot.merging(serverItems: items, currentOwnerID: healthStorage.userID,
            currentScopeID: healthStorage.scopeID)
        trace.mark("fresh-server-merge-complete")
        return result
    }

    private func makeProductionViewModel() -> (FeedViewModel, SupabaseFeedRemoteClient?) {
        let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        let injectedRepository: (any FeedRepositoryProtocol)?
        #if DEBUG && targetEnvironment(simulator)
        productionTestDependencies?.requireSyntheticHost()
        injectedRepository = productionTestDependencies?.repository
        #else
        injectedRepository = nil
        #endif
        if ReviewDemoMode.isActive && injectedRepository == nil {
            let demo = ReviewDemoCommunityStore.shared
            let weekly: any FeedWeeklyProgressProviding
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["SOOM_FEED_SLOW_SUMMARY_QA"] == "1" {
                weekly = Feed64HeldWeeklyProvider(base: UnifiedWorkoutWeeklyProgressProvider(store: store))
            } else { weekly = UnifiedWorkoutWeeklyProgressProvider(store: store) }
            #else
            weekly = UnifiedWorkoutWeeklyProgressProvider(store: store)
            #endif
            return (FeedViewModel(
                feedLoader: FeedDataSource(remoteRepository: demo, draftStore: FileFeedShareDraftStore.live, filterItems: filterSecondaryCards, homeContractAvailable: true),
                weeklyProgressProvider: weekly,
                recoveryPreviewProvider: UnifiedWorkoutRecoveryPreviewProvider(store: store),
                streakDatesProvider: UnifiedWorkoutStoreStreakDatesProvider(store: store),
                reactionPoster: demo, bookmarkPoster: demo, commentPoster: demo, postDeleter: demo,
                draftStore: FileFeedShareDraftStore.live, safetyStore: safetyStore, initialAudience: .home), nil)
        }
        let clientProvider = SupabaseClientProvider(environment: AuthEnvironmentLoader().load())
        let remoteClient = healthStorage.userID == nil ? nil
            : clientProvider.makeClient().map(SupabaseFeedRemoteClient.init(client:))
        let draftStore = FileFeedShareDraftStore.live
        let legacyRepository = SupabaseFeedRepository(clientProvider: clientProvider, remoteFetcher: remoteClient, profileFetcher: remoteClient)
        let homeRepository: any FeedRepositoryProtocol
        if let injectedRepository {
            homeRepository = injectedRepository
        } else if let client = clientProvider.makeClient(), healthStorage.userID != nil {
            let policy = AccountActivityReadPolicy.deployed
            let legacyPreview = policy == .approvedFollowersV1 && previewEnabled
            homeRepository = AccountActivityHomeRepository(legacy: legacyRepository,
                transport: SupabaseAccountActivityFeedTransport(client: client, legacyRepository: legacyRepository,
                    preview: legacyPreview, readPolicy: policy),
                preview: legacyPreview, legacyFallback: policy == .approvedFollowersV1 && safetyStore.canUseSocial)
        } else { homeRepository = legacyRepository }

        let viewModel = FeedViewModel(
            feedLoader: FeedDataSource(
                remoteRepository: homeRepository,
                draftStore: draftStore,
                strategy: healthStorage.userID == nil ? .localDraftsOnly : .remoteWithLocalDrafts,
                filterItems: filterSecondaryCards,
                ownerProjection: projectOwnerItems,
                homeContractAvailable: safetyStore.canUseSocial || previewEnabled || AccountActivityReadPolicy.deployed.productionReady
            ),
            weeklyProgressProvider: UnifiedWorkoutWeeklyProgressProvider(store: store),
            recoveryPreviewProvider: UnifiedWorkoutRecoveryPreviewProvider(store: store),
            streakDatesProvider: UnifiedWorkoutStoreStreakDatesProvider(store: store),
            reactionPoster: remoteClient,
            bookmarkPoster: remoteClient,
            commentPoster: remoteClient,
            postDeleter: remoteClient,
            draftStore: draftStore,
            safetyStore: safetyStore, initialAudience: .home, normalizeItems: projectOwnerItems
        )
        #if DEBUG && targetEnvironment(simulator)
        productionTestDependencies?.didCreateViewModel?(viewModel)
        #endif
        return (viewModel, remoteClient)
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Force replacement only in the explicit reconstruction fixture. Ordinary
/// feeds and existing deep-scroll fixtures must not acquire this testing-only
/// IDView, even with an unchanged generation value.
private struct Feed60DebugRecreationModifier: ViewModifier {
    let generation: Int
    @ViewBuilder func body(content: Content) -> some View {
        if ProcessInfo.processInfo.environment["SOOM_FEED_ENRICHMENT_QA"] == "1" {
            content.id(generation)
        } else {
            content
        }
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
@MainActor private enum Feed64SummaryGate {
    static var isHeld = false
    private static var continuation: CheckedContinuation<Void, Never>?
    static func wait() async {
        isHeld = true
        await withCheckedContinuation { continuation = $0 }
        isHeld = false
    }
    static func release() { continuation?.resume(); continuation = nil }
}
private struct Feed64HeldWeeklyProvider: FeedWeeklyProgressProviding {
    let base: UnifiedWorkoutWeeklyProgressProvider
    func fetchWeeklyProgress(referenceDate: Date) async throws -> WeeklyWorkoutProgress {
        await Feed64SummaryGate.wait()
        try Task.checkCancellation()
        return try await base.fetchWeeklyProgress(referenceDate: referenceDate)
    }
}
#endif
