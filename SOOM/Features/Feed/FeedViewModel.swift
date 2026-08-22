import Foundation

protocol FeedLoading {
    func loadFeed(limit: Int) async -> [FeedItem]
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
        try await store.fetchRecentWorkouts(days: days).map(\.startDate)
    }
}

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var readModel: FeedReadModel

    private let feedLoader: any FeedLoading
    private let weeklyProgressProvider: any FeedWeeklyProgressProviding
    private let recoveryPreviewProvider: any FeedRecoveryPreviewProviding
    private let streakDatesProvider: any FeedStreakWorkoutDatesProviding
    private let reactionPoster: (any FeedRemoteReactionPosting)?
    private let commentPoster: (any FeedRemoteCommentPosting)?
    private let postDeleter: (any FeedRemotePostDeleting)?
    private let draftStore: (any FeedShareDraftStoreProtocol)?
    private let now: () -> Date

    init(
        feedLoader: any FeedLoading,
        weeklyProgressProvider: any FeedWeeklyProgressProviding,
        recoveryPreviewProvider: any FeedRecoveryPreviewProviding,
        streakDatesProvider: any FeedStreakWorkoutDatesProviding,
        reactionPoster: (any FeedRemoteReactionPosting)? = nil,
        commentPoster: (any FeedRemoteCommentPosting)? = nil,
        postDeleter: (any FeedRemotePostDeleting)? = nil,
        draftStore: (any FeedShareDraftStoreProtocol)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.feedLoader = feedLoader
        self.weeklyProgressProvider = weeklyProgressProvider
        self.recoveryPreviewProvider = recoveryPreviewProvider
        self.streakDatesProvider = streakDatesProvider
        self.reactionPoster = reactionPoster
        self.commentPoster = commentPoster
        self.postDeleter = postDeleter
        self.draftStore = draftStore
        self.now = now
        self.readModel = .loading
    }

    func load() async {
        let referenceDate = now()
        readModel.isLoading = true
        async let feedItems = feedLoader.loadFeed(limit: 20)
        async let weeklyProgress = weeklyProgressProvider.fetchWeeklyProgress(referenceDate: referenceDate)
        async let recoveryPreview = recoveryPreviewProvider.fetchPreviewSummary()
        async let streakDates = streakDatesProvider.fetchRecentWorkoutDates(days: 180)

        let items = await feedItems
        let progress = try? await weeklyProgress
        let recovery = try? await recoveryPreview
        let workoutDates = (try? await streakDates) ?? []

        readModel = FeedReadModel(
            items: items,
            weeklySnapshot: progress.map {
                FeedWeeklySnapshot(progress: $0, sportSummary: sportSummary(for: $0))
            },
            recoveryInsight: recovery.map { FeedRecoveryInsight(summary: $0.summary) },
            streak: WeeklyStreakCalculator.calculate(workoutDates: workoutDates, referenceDate: referenceDate),
            isLoading: false
        )
    }

    /// Toggles the viewer's own "cheer" reaction on `item`. A local draft
    /// has no `feed_posts` row to react against, so this is a no-op for one
    /// (the UI already disables the button in that case; this is the second
    /// line of defense). Updates `readModel` optimistically and reverts it
    /// if the remote call fails, so a flaky network never leaves the UI
    /// showing a reaction that didn't actually save.
    func toggleCheer(for item: FeedItem) async {
        guard !item.isLocalDraft, let reactionPoster else {
            return
        }

        let wasCheered = item.viewerHasCheered
        setViewerHasCheered(!wasCheered, forItemId: item.id)

        do {
            if wasCheered {
                try await reactionPoster.removeReaction(postId: item.id, reactionType: "cheer")
            } else {
                try await reactionPoster.addReaction(postId: item.id, reactionType: "cheer")
            }
        } catch {
            setViewerHasCheered(wasCheered, forItemId: item.id)
        }
    }

    /// Posts a comment on `item`. Local drafts can't be commented on (no
    /// `feed_posts` row) — the UI already disables the control for one.
    /// Reloads the feed afterward rather than splicing the new comment in
    /// locally, since a comment isn't a hot-path action.
    func postComment(_ body: String, on item: FeedItem) async throws {
        guard !item.isLocalDraft, let commentPoster else {
            return
        }

        try await commentPoster.addComment(postId: item.id, body: body)
        await load()
    }

    /// Deletes `item` — a local draft is removed from `draftStore`, a real
    /// post is deleted remotely (RLS scopes this to the post's own owner).
    /// Removes it from `readModel` locally either way rather than
    /// reloading, since deletion needs no server round-trip to reflect.
    func deletePost(_ item: FeedItem) async {
        do {
            if item.isLocalDraft {
                try await draftStore?.deleteDraft(id: item.id)
            } else {
                try await postDeleter?.deletePost(id: item.id)
            }
            readModel.items.removeAll { $0.id == item.id }
        } catch {
            // Deletion failed (network, RLS, etc.) — leave the item in
            // place rather than hiding something that's still really there.
        }
    }

    private func setViewerHasCheered(_ value: Bool, forItemId id: UUID) {
        guard let index = readModel.items.firstIndex(where: { $0.id == id }) else {
            return
        }
        readModel.items[index].viewerHasCheered = value
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

    static let loading = FeedReadModel(
        items: [],
        weeklySnapshot: nil,
        recoveryInsight: nil,
        streak: FeedStreakSnapshot(weekCount: 0, activityCount: 0),
        isLoading: true
    )
}
