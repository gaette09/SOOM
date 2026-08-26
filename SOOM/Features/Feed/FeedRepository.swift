import Foundation

enum FeedRepositoryError: Error, Equatable {
    case unconfigured
    case remoteFetchNotImplemented
    case remoteFailed
}

protocol FeedRepositoryProtocol {
    func fetchFeed(limit: Int) async throws -> [FeedItem]
    /// Single-post lookup for notification deep links. Returns nil for
    /// "not found" (deleted, or RLS silently filtered it out because it's
    /// private and the caller isn't the owner) — callers must not
    /// distinguish those cases in UI, since doing so would leak which
    /// posts exist but are private.
    func fetchPost(id: UUID) async throws -> FeedItem?
}

protocol FeedRemotePostFetching {
    func fetchFeedPosts(limit: Int) async throws -> [FeedPostBundleDTO]
    /// Goes through the exact same RLS-scoped client as fetchFeedPosts —
    /// deliberately not a separate/elevated path, so a private post stays
    /// invisible to a single-row lookup exactly as it is to the list one.
    func fetchFeedPost(id: UUID) async throws -> FeedPostBundleDTO?
}

protocol FeedRemotePostPosting {
    func postPublicPost(_ draft: FeedShareDraft, visibility: FeedPostVisibility) async throws
    /// Flips an already-posted row's visibility — the "이 운동은 공유
    /// 안 함" opt-out path (2026-08-26: workouts post automatically on
    /// completion now, so opting out means editing the row that already
    /// exists, not skipping a not-yet-made insert). Scoped by
    /// `sourceWorkoutId` rather than the server-generated post id, since
    /// `postPublicPost` deliberately never reads that id back (see its
    /// doc comment) — `source_workout_id` is the one identifier the
    /// caller already has client-side.
    func updatePostVisibility(sourceWorkoutId: UUID, visibility: FeedPostVisibility) async throws
}

protocol FeedRemoteReactionPosting {
    func addReaction(postId: UUID, reactionType: String) async throws
    func removeReaction(postId: UUID, reactionType: String) async throws
}

protocol FeedRemoteCommentPosting {
    func addComment(postId: UUID, body: String) async throws
}

protocol FeedRemotePostDeleting {
    func deletePost(id: UUID) async throws
}

struct MockFeedRepository: FeedRepositoryProtocol {
    let items: [FeedItem]

    init(items: [FeedItem] = FeedMockData.items) {
        self.items = items
    }

    func fetchFeed(limit: Int) async throws -> [FeedItem] {
        Array(items.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    func fetchPost(id: UUID) async throws -> FeedItem? {
        items.first { $0.id == id }
    }
}
