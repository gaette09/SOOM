import Combine
import Foundation

protocol FeedLoading {
    func loadFeed(limit: Int) async -> FeedLoadResult
    func loadFeedPage(limit: Int, offset: Int) async -> FeedLoadResult
    func setAudience(_ audience: FeedAudience)
    func loadPost(id: UUID) async -> FeedItem?
}

extension FeedLoading {
    func setAudience(_ audience: FeedAudience) {}
    func loadFeedPage(limit: Int, offset: Int) async -> FeedLoadResult {
        let result = await loadFeed(limit: limit + offset)
        return FeedLoadResult(items: Array(result.items.dropFirst(offset).prefix(limit)),
            failure: result.failure, hasMore: result.items.count >= limit + offset,
            remoteProjectionRows: result.remoteProjectionRows.map { Array($0.dropFirst(offset).prefix(limit)) })
    }
}

extension FeedDataSource: FeedLoading {}

protocol FeedWeeklyProgressProviding {
    func fetchWeeklyProgress(referenceDate: Date) async throws -> WeeklyWorkoutProgress
}

extension UnifiedWorkoutWeeklyProgressProvider: FeedWeeklyProgressProviding {}

protocol FeedRecoveryPreviewProviding {
    func fetchPreviewSummary() async throws -> UnifiedWorkoutRecoveryPreviewResult
}

extension UnifiedWorkoutRecoveryPreviewProvider: FeedRecoveryPreviewProviding {}

protocol FeedStreakWorkoutDatesProviding {
    func fetchRecentWorkoutDates(days: Int) async throws -> [Date]
}

struct UnifiedWorkoutStoreStreakDatesProvider: FeedStreakWorkoutDatesProviding {
    let store: any UnifiedWorkoutStore

    func fetchRecentWorkoutDates(days: Int) async throws -> [Date] {
        try await store.fetchCanonicalRecentWorkouts(days: days).map(\.startDate)
    }
}

@MainActor
final class FeedViewModel: ObservableObject {
    static let pageSize = 8
    private var paginationRevision = 0
    @Published private(set) var audience: FeedAudience = .all
    @Published private(set) var readModel: FeedReadModel
    private(set) var loadedProjectionPrefix: [AccountActivityFeedRow]?

    private let feedLoader: any FeedLoading
    private let weeklyProgressProvider: any FeedWeeklyProgressProviding
    private let recoveryPreviewProvider: any FeedRecoveryPreviewProviding
    private let streakDatesProvider: any FeedStreakWorkoutDatesProviding
    private let reactionPoster: (any FeedRemoteReactionPosting)?
    private let bookmarkPoster: (any FeedRemoteBookmarkPosting)?
    private let commentPoster: (any FeedRemoteCommentPosting)?
    private let postDeleter: (any FeedRemotePostDeleting)?
    private let draftStore: (any FeedShareDraftStoreProtocol)?
    private let safetyStore: CommunitySafetyStore?
    private var safetySubscription: AnyCancellable?
    private var accountGeneration: Int?
    private let normalizeItems: ([FeedItem]) -> [FeedItem]
    private let now: () -> Date
    private var loadInProgress = false
    private var supplementaryTask: Task<Void, Never>?
    private var displayTrace: LoadTrace?
    private var displayedTraceID: UUID?
    private var traceItemsApplied = false
    func recordFirstCardDisplay() {
        guard traceItemsApplied, let displayTrace, displayedTraceID != displayTrace.id else { return }
        displayedTraceID = displayTrace.id
        displayTrace.mark("candidate-view-appear")
    }
    private var reloadPending = false
    private var pageInProgress = false
    private var activeCheerMutations: Set<UUID> = []
    private var nextOffset = 0
    private var loadGeneration = 0

    init(
        feedLoader: any FeedLoading,
        weeklyProgressProvider: any FeedWeeklyProgressProviding,
        recoveryPreviewProvider: any FeedRecoveryPreviewProviding,
        streakDatesProvider: any FeedStreakWorkoutDatesProviding,
        reactionPoster: (any FeedRemoteReactionPosting)? = nil,
        bookmarkPoster: (any FeedRemoteBookmarkPosting)? = nil,
        commentPoster: (any FeedRemoteCommentPosting)? = nil,
        postDeleter: (any FeedRemotePostDeleting)? = nil,
        draftStore: (any FeedShareDraftStoreProtocol)? = nil,
        safetyStore: CommunitySafetyStore? = nil,
        now: @escaping () -> Date = Date.init,
        initialAudience: FeedAudience = .all,
        normalizeItems: @escaping ([FeedItem]) -> [FeedItem] = { $0 }
    ) {
        self.normalizeItems = normalizeItems
        self.feedLoader = feedLoader
        self.audience = initialAudience
        feedLoader.setAudience(initialAudience)
        self.weeklyProgressProvider = weeklyProgressProvider
        self.recoveryPreviewProvider = recoveryPreviewProvider
        self.streakDatesProvider = streakDatesProvider
        self.reactionPoster = reactionPoster
        self.bookmarkPoster = bookmarkPoster
        self.commentPoster = commentPoster
        self.postDeleter = postDeleter
        self.draftStore = draftStore
        self.safetyStore = safetyStore
        self.accountGeneration = safetyStore?.accountGeneration
        self.now = now
        self.readModel = .loading
        safetySubscription = safetyStore?.$revision.dropFirst().sink { [weak self] _ in
            self?.invalidateForSafetyChange()
        }
    }

    func selectAudience(_ value: FeedAudience) async {
        guard audience != value else { return }
        audience = value; feedLoader.setAudience(value)
        loadGeneration += 1; nextOffset = 0; readModel.items = []; readModel.hasResolvedPage = false
        loadedProjectionPrefix = nil
        await load()
    }

    func load(awaitSupplementaryContent: Bool = true, onPrimaryContentReady: (@MainActor () async -> Void)? = nil) async {
        guard !Task.isCancelled else { return }
        guard !loadInProgress else {
            // A mutation may finish after the active fetch took its snapshot.
            // Let its owner fetch again before returning the final read model.
            reloadPending = true
            return
        }
        supplementaryTask?.cancel()
        loadInProgress = true
        defer { loadInProgress = false; readModel.isLoading = false }
        loadGeneration += 1
        // Refresh the already-visited range so returning from a detail never
        // discards the older card currently in view.
        let requestedCount = max(Self.pageSize, nextOffset)
        let previousOffset = nextOffset
        let previousHasMore = readModel.hasMore
        let previousCoverageStart = readModel.remoteCoverageStart
        nextOffset = 0
        readModel.isLoading = true
        readModel.hasMore = false
        readModel.loadFailure = nil
        readModel.loadMoreFailure = nil

        repeat {
            reloadPending = false
            let trace = LoadTrace("feed-screen")
            displayTrace = trace
            traceItemsApplied = false
            let permissionRevision = safetyStore?.revision
            let activeAudience = audience
            let generation = safetyStore?.accountGeneration
            let referenceDate = now()
            async let feedResult = fetchPageWithTransientRetry(limit: requestedCount, offset: 0)

            let result = await feedResult
            guard !Task.isCancelled else { trace.mark("cancelled-after-page-result"); return }
            trace.mark("service-response")
            let accountIsCurrent = generation == safetyStore?.accountGeneration && permissionRevision == safetyStore?.revision && activeAudience == audience
            readModel.hasResolvedPage = accountIsCurrent && result.failure == nil
            let canKeepCachedItems = result.failure != nil && accountIsCurrent && !readModel.items.isEmpty
            if accountIsCurrent && result.failure == nil { loadedProjectionPrefix = result.remoteProjectionRows }
            else if !accountIsCurrent { loadedProjectionPrefix = nil }
            if canKeepCachedItems {
                // A temporary network failure must not erase the reader's
                // place or turn a previously loaded page into an empty feed.
                nextOffset = previousOffset
                readModel.items = (safetyStore?.filtered(readModel.items) ?? readModel.items).filter {
                $0.isLocalDraft || $0.authorId == safetyStore?.viewerID || $0.visibility == .publicFeed
            }
            } else {
                nextOffset = requestedCount
                readModel.items = accountIsCurrent
                    ? (safetyStore?.filtered(result.items) ?? result.items) : []
            }
            let coverageStart = canKeepCachedItems ? previousCoverageStart : result.remoteCoverageStart
            let coverageHasMore = canKeepCachedItems ? previousHasMore : result.failure == nil && result.hasMore
            trace.mark("owner-normalize-start")
            readModel.items = FeedRemoteCoverage.visible(normalizeItems(readModel.items), since: coverageStart, hasMore: coverageHasMore)
            trace.mark("owner-normalize-complete")
            readModel.remoteCoverageStart = coverageStart
            if accountIsCurrent && result.failure == nil { paginationRevision += 1 }
            readModel.paginationRevision = paginationRevision
            traceItemsApplied = true
            trace.mark("items-applied")
            let hasMore = canKeepCachedItems ? previousHasMore : result.failure == nil && result.hasMore
            readModel.loadFailure = result.failure
            readModel.hasMore = hasMore
            // Cards can render while local summaries finish.
            readModel.isLoading = true
            // Publish the primary content before starting optional local aggregates.
            // Yield the UI executor; async alone does not move SwiftData work off it.
            await Task.yield()
            guard !Task.isCancelled else { trace.mark("cancelled-before-primary-authorization"); return }
            // The container must finish card authorization before optional local
            // aggregates. Publishing rows alone is not a visible card.
            if accountIsCurrent && result.failure == nil { await onPrimaryContentReady?() }
            guard !Task.isCancelled else { trace.mark("cancelled-after-primary-authorization"); return }
            guard generation == safetyStore?.accountGeneration,
                  permissionRevision == safetyStore?.revision, activeAudience == audience else {
                reloadPending = true; continue
            }
            trace.mark("primary-authorization-complete")
            let expectedLoad = loadGeneration
            if awaitSupplementaryContent {
                await supplementaryTask?.value
                await updateSupplementaryContent(referenceDate: referenceDate, generation: generation,
                    permissionRevision: permissionRevision, activeAudience: activeAudience,
                    expectedLoad: expectedLoad, trace: trace)
                guard generation == safetyStore?.accountGeneration,
                      permissionRevision == safetyStore?.revision, activeAudience == audience else {
                    reloadPending = true; continue
                }
            } else {
                // Optional local summaries have a separate lane. They must not
                // retain the page/authorization owner or block scroll pagination.
                // Drain only on this lane to avoid concurrent SwiftData scans.
                let previous = supplementaryTask
                previous?.cancel()
                supplementaryTask = Task { @MainActor [weak self] in
                    await previous?.value
                    guard !Task.isCancelled, let self else { return }
                    await self.updateSupplementaryContent(referenceDate: referenceDate, generation: generation,
                        permissionRevision: permissionRevision, activeAudience: activeAudience,
                        expectedLoad: expectedLoad, trace: trace)
                }
            }
            readModel.isLoading = reloadPending
        } while reloadPending && !Task.isCancelled
    }

    private func updateSupplementaryContent(referenceDate: Date, generation: Int?, permissionRevision: Int?,
        activeAudience: FeedAudience, expectedLoad: Int, trace: LoadTrace) async {
        guard !Task.isCancelled, expectedLoad == loadGeneration,
              generation == safetyStore?.accountGeneration, permissionRevision == safetyStore?.revision,
              activeAudience == audience else { return }
        trace.mark("optional-aggregates-start")
        async let weeklyProgress = weeklyProgressProvider.fetchWeeklyProgress(referenceDate: referenceDate)
        async let recoveryPreview = recoveryPreviewProvider.fetchPreviewSummary()
        async let streakDates = streakDatesProvider.fetchRecentWorkoutDates(days: 180)
        let progress = try? await weeklyProgress
        let recovery = try? await recoveryPreview
        let workoutDates = (try? await streakDates) ?? []
        guard !Task.isCancelled, expectedLoad == loadGeneration,
              generation == safetyStore?.accountGeneration, permissionRevision == safetyStore?.revision,
              activeAudience == audience else { return }
        // Never write items, pagination state, failures or loading flags here.
        readModel.weeklySnapshot = progress.map { FeedWeeklySnapshot(progress: $0, sportSummary: sportSummary(for: $0)) }
        readModel.recoveryInsight = recovery.map { FeedRecoveryInsight(preview: $0) }
        readModel.streak = WeeklyStreakCalculator.calculate(workoutDates: workoutDates, referenceDate: referenceDate)
        trace.mark("optional-aggregates-complete")
    }

    func loadMore() async {
        guard !loadInProgress, !pageInProgress, readModel.hasMore else { return }
        pageInProgress = true
        readModel.isLoadingMore = true
        readModel.loadMoreFailure = nil
        var progressed = false
        let generation = loadGeneration
        let account = safetyStore?.accountGeneration
        defer {
            pageInProgress = false; readModel.isLoadingMore = false
            if progressed { paginationRevision += 1; readModel.paginationRevision = paginationRevision }
            else if Task.isCancelled || generation != loadGeneration || account != safetyStore?.accountGeneration { readModel.paginationWakeRevision += 1 }
        }

        let result = await fetchPageWithTransientRetry(limit: Self.pageSize, offset: nextOffset)
        guard !Task.isCancelled, generation == loadGeneration, account == safetyStore?.accountGeneration else { return }
        if let failure = result.failure {
            readModel.loadMoreFailure = failure
            return
        }
        nextOffset += Self.pageSize
        if let prior = loadedProjectionPrefix, let page = result.remoteProjectionRows {
            let merged = prior + page
            loadedProjectionPrefix = Set(merged.map(\.cardID)).count == merged.count ? merged : nil
        } else { loadedProjectionPrefix = nil }
        let additions = safetyStore?.filtered(result.items) ?? result.items
        readModel.remoteCoverageStart = result.remoteCoverageStart
        readModel.items = FeedRemoteCoverage.visible(normalizeItems(FeedDataSource.uniqueWorkoutCards(readModel.items + additions)),
            since: result.remoteCoverageStart, hasMore: result.hasMore).sorted(by: FeedDisplayOrder.newestFirst)
        readModel.hasMore = result.hasMore
        progressed = true
    }

    func retryLoadMore() async {
        await loadMore()
    }

    private func fetchPageWithTransientRetry(limit: Int, offset: Int) async -> FeedLoadResult {
        let trace = LoadTrace("feed-page-attempts")
        var attempt = 1
        var result = await feedLoader.loadFeedPage(limit: limit, offset: offset)
        trace.mark(result.failure == nil ? "attempt-1-success" : "attempt-1-failed")
        for delay in [250, 650] where result.failure == .remoteFailed && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { break }
            attempt += 1
            result = await feedLoader.loadFeedPage(limit: limit, offset: offset)
            trace.mark(result.failure == nil ? "attempt-\(attempt)-success" : "attempt-\(attempt)-failed")
        }
        return result
    }

    /// The server compared the exact cached prefix. A changed sort key requires
    /// a normal page reload so pagination cursors cannot silently become stale.
    func applyVisibleBatch(_ batch: FeedReturnBatchPresentation) -> Bool {
        guard audience == .home, batch.phase == .ready, !batch.needsPageReload,
              let prefix = loadedProjectionPrefix, prefix.count <= 500,
              safetyStore == nil || batch.context.matches(viewerID: safetyStore?.viewerID,
                  accountGeneration: safetyStore?.accountGeneration ?? -1,
                  safetyRevision: safetyStore?.revision ?? -1, returnEpoch: batch.context.returnEpoch) else { return false }
        let known = Dictionary(uniqueKeysWithValues: prefix.map { ($0.cardID, $0) })
        guard batch.denied.isEmpty, batch.grants.values.allSatisfy({ grant in
            guard let old = known[grant.row.cardID] else { return false }
            return old.ownerID == grant.row.ownerID && old.canonicalID == grant.row.canonicalID && old.activityAt == grant.row.activityAt
        }) else { return false }
        let changed = batch.grants.values.filter { known[$0.row.cardID] != $0.row }
        if !changed.isEmpty {
            let replacements = Dictionary(uniqueKeysWithValues: AccountActivityHydratedPage(
                cards: changed.map { .init(projection: $0.row, legacyItem: nil) }, nextCursor: nil, hasMore: false)
                .displayItems().map { ($0.id, $0) })
            readModel.items = normalizeItems(readModel.items.map { replacements[$0.id] ?? $0 })
            loadedProjectionPrefix = prefix.map { batch.grants[$0.cardID]?.row ?? $0 }
        }
        readModel.hasMore = batch.hasMore
        readModel.hasResolvedPage = true
        readModel.isLoading = false
        readModel.loadFailure = nil
        return true
    }

    /// Always recheck RLS for notification targets: cached posts can become
    /// blocked, removed, or private after the notification was delivered.
    func resolveFeedItem(postId: UUID) async -> FeedItem? {
        let revision = safetyStore?.revision
        let account = safetyStore?.accountGeneration
        let item = await feedLoader.loadPost(id: postId)
        guard !Task.isCancelled, revision == safetyStore?.revision,
              account == safetyStore?.accountGeneration, let item, item.id == postId else { return nil }
        return safetyStore?.filtered([item]).first ?? (safetyStore == nil ? item : nil)
    }

    /// Include a freshly authorized deep-link card without walking every page
    /// or moving the pagination cursor. Called only after the request wins.
    func includeNotificationItem(_ item: FeedItem) {
        guard audience != .home, !item.isLocalDraft else { return }
        if let safetyStore {
            guard safetyStore.canUseSocial, !safetyStore.filtered([item]).isEmpty else { return }
        }
        readModel.items.removeAll { $0.id == item.id }
        readModel.items.append(item)
        readModel.items.sort(by: FeedDisplayOrder.newestFirst)
    }

    func invalidateForSafetyChange() {
        supplementaryTask?.cancel()
        loadedProjectionPrefix = nil
        readModel.hasResolvedPage = false
        if accountGeneration != safetyStore?.accountGeneration {
            accountGeneration = safetyStore?.accountGeneration
            readModel = .loading
            loadGeneration += 1
            nextOffset = 0
        } else {
            // Public access does not imply membership in the following feed.
            // Clear that scope immediately until the server confirms the graph.
            readModel.items = audience != .all ? [] :
                (safetyStore?.filtered(readModel.items) ?? readModel.items).filter {
                    $0.isLocalDraft || $0.authorId == safetyStore?.viewerID || $0.visibility == .publicFeed
                }
            loadGeneration += 1
            if audience != .all { nextOffset = 0; readModel.hasMore = false }
        }
        queueReloadIfLoading()
    }

    /// Toggles the viewer's own "cheer" reaction on `item`. A local draft
    /// has no `feed_posts` row to react against, so this is a no-op for one
    /// (the UI already disables the button in that case; this is the second
    /// line of defense). Updates `readModel` optimistically and reverts it
    /// if the remote call fails, so a flaky network never leaves the UI
    /// showing a reaction that didn't actually save.
    func toggleCheer(for item: FeedItem) async {
        guard item.activityProjection == nil, item.previewLegacyReadContext == nil, !item.isLocalDraft, let reactionPoster,
              safetyStore == nil || safetyStore?.canUseSocial == true,
              safetyStore?.isBlocked(item.authorId) != true,
              let current = readModel.items.first(where: { $0.id == item.id && $0.authorId == item.authorId && !$0.isLocalDraft }),
              current.previewLegacyReadContext == nil,
              activeCheerMutations.insert(item.id).inserted else { return }
        defer { activeCheerMutations.remove(item.id) }
        let generation = safetyStore?.accountGeneration
        let viewerID = safetyStore?.viewerID
        let revision = safetyStore?.revision
        let wasCheered = current.viewerHasCheered
        let desired = !wasCheered
        setViewerHasCheered(desired, forItemId: item.id)

        do {
            if wasCheered {
                try await reactionPoster.removeReaction(postId: item.id, reactionType: "cheer")
            } else {
                try await reactionPoster.addReaction(postId: item.id, reactionType: "cheer")
            }
            guard generation == safetyStore?.accountGeneration, viewerID == safetyStore?.viewerID,
                  revision == safetyStore?.revision,
                  safetyStore?.isBlocked(item.authorId) != true else { return }
            // Refresh only this card's social state. Pagination, scroll position,
            // and other optimistic actions keep their existing values.
            let refreshed = await feedLoader.loadPost(id: item.id)
            guard generation == safetyStore?.accountGeneration, viewerID == safetyStore?.viewerID,
                  revision == safetyStore?.revision,
                  safetyStore?.isBlocked(item.authorId) != true else { return }
            guard let refreshed, refreshed.id == item.id, refreshed.authorId == item.authorId,
                  !refreshed.isLocalDraft, refreshed.viewerHasCheered == desired else {
                throw FeedPostManagementError.changeNotConfirmed
            }
            if let index = readModel.items.firstIndex(where: { $0.id == item.id && $0.authorId == item.authorId }) {
                readModel.items[index].viewerHasCheered = desired
                readModel.items[index].reactions = refreshed.reactions
            }
            queueReloadIfLoading()
        } catch {
            guard generation == safetyStore?.accountGeneration, viewerID == safetyStore?.viewerID,
                  revision == safetyStore?.revision,
                  readModel.items.contains(where: { $0.id == item.id && $0.authorId == item.authorId }) else { return }
            setViewerHasCheered(wasCheered, forItemId: item.id)
        }
    }

    func toggleSave(for item: FeedItem) async {
        guard item.activityProjection == nil, !item.isLocalDraft, let bookmarkPoster else {
            return
        }

        let wasSaved = item.viewerHasSaved
        setViewerHasSaved(!wasSaved, forItemId: item.id)

        do {
            if wasSaved {
                try await bookmarkPoster.removeBookmark(postId: item.id)
            } else {
                try await bookmarkPoster.addBookmark(postId: item.id)
            }
            setViewerHasSaved(!wasSaved, forItemId: item.id)
            queueReloadIfLoading()
        } catch {
            setViewerHasSaved(wasSaved, forItemId: item.id)
        }
    }

    /// Posts a comment on `item`. Local drafts can't be commented on (no
    /// `feed_posts` row) — the UI already disables the control for one.
    /// Reloads the feed afterward rather than splicing the new comment in
    /// locally, since a comment isn't a hot-path action.
    func postComment(_ body: String, on item: FeedItem) async throws {
        guard item.activityProjection == nil, !item.isLocalDraft else { throw CommunitySafetyError.invalidTarget }
        guard let commentPoster else { throw CommunitySafetyError.unavailable }
        guard safetyStore?.isBlocked(item.authorId) != true else { throw CommunitySafetyError.invalidTarget }

        let generation = safetyStore?.accountGeneration
        try await commentPoster.addComment(postId: item.id, body: body)
        guard generation == safetyStore?.accountGeneration else { throw CommunitySafetyError.accountChanged }
        await load()
    }

    /// Deletes `item` — a local draft is removed from `draftStore`, a real
    /// post is deleted remotely (RLS scopes this to the post's own owner).
    /// Removes it from `readModel` locally either way rather than
    /// reloading, since deletion needs no server round-trip to reflect.
    func deletePost(_ item: FeedItem) async {
        // Owner projections are real saved workouts, not disposable drafts.
        // Their existing record-management destination owns deletion.
        guard !item.isOwnerLocalWorkout, item.activityProjection == nil else { return }
        do {
            if item.isLocalDraft {
                try await draftStore?.deleteDraft(id: item.id)
            } else {
                try await postDeleter?.deletePost(id: item.id)
            }
            readModel.items.removeAll { $0.id == item.id }
            queueReloadIfLoading()
        } catch {
            // Deletion failed (network, RLS, etc.) — leave the item in
            // place rather than hiding something that's still really there.
        }
    }

    private func queueReloadIfLoading() {
        // The active fetch may hold a snapshot from before this mutation saved.
        if loadInProgress {
            reloadPending = true
        }
    }

    private func setViewerHasCheered(_ value: Bool, forItemId id: UUID) {
        guard let index = readModel.items.firstIndex(where: { $0.id == id }) else {
            return
        }
        readModel.items[index].viewerHasCheered = value
    }

    private func setViewerHasSaved(_ value: Bool, forItemId id: UUID) {
        guard let index = readModel.items.firstIndex(where: { $0.id == id }) else {
            return
        }
        readModel.items[index].viewerHasSaved = value
    }

    private func sportSummary(for progress: WeeklyWorkoutProgress) -> String {
        guard progress.workoutCount > 0 else { return "이번 주 운동을 기다리고 있어요" }
        return "이번 주 \(progress.workoutCount)회 움직였어요"
    }
}

struct FeedReadModel: Equatable {
    var items: [FeedItem]
    var weeklySnapshot: FeedWeeklySnapshot?
    var recoveryInsight: FeedRecoveryInsight?
    var streak: FeedStreakSnapshot
    var isLoading: Bool
    var hasResolvedPage = false
    /// A cancelled first read is unknown, not a confirmed empty feed.
    var showsInitialLoading: Bool { isLoading || (items.isEmpty && !hasResolvedPage && loadFailure == nil) }
    var loadFailure: FeedLoadFailure? = nil
    var hasMore: Bool = false
    var isLoadingMore: Bool = false
    var loadMoreFailure: FeedLoadFailure? = nil
    var remoteCoverageStart: Date? = nil
    var paginationRevision = 0
    var paginationWakeRevision = 0

    static let loading = FeedReadModel(
        items: [],
        weeklySnapshot: nil,
        recoveryInsight: nil,
        streak: FeedStreakSnapshot(weekCount: 0, activityCount: 0),
        isLoading: true
    )
}
