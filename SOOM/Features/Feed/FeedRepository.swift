import Foundation

enum FeedRepositoryError: Error, Equatable {
    case unconfigured
    case remoteFetchNotImplemented
    case remoteFailed
}

protocol FeedRepositoryProtocol {
    func fetchFeed(limit: Int) async throws -> [FeedItem]
    func fetchFeedPage(limit: Int, offset: Int) async throws -> [FeedItem]
    func fetchFeedPage(limit: Int, offset: Int, audience: FeedAudience) async throws -> [FeedItem]
    func fetchSavedPosts() async throws -> [FeedItem]
    /// Single-post lookup for notification deep links. Returns nil for
    /// "not found" (deleted, or RLS silently filtered it out because it's
    /// private and the caller isn't the owner) — callers must not
    /// distinguish those cases in UI, since doing so would leak which
    /// posts exist but are private.
    func fetchPost(id: UUID) async throws -> FeedItem?
}

extension FeedRepositoryProtocol {
    func fetchFeedPage(limit: Int, offset: Int, audience: FeedAudience) async throws -> [FeedItem] {
        guard audience == .all else { throw FeedRepositoryError.remoteFetchNotImplemented }
        return try await fetchFeedPage(limit: limit, offset: offset)
    }
    func fetchFeedPage(limit: Int, offset: Int) async throws -> [FeedItem] {
        let items = try await fetchFeed(limit: limit + offset)
        return Array(items.dropFirst(offset).prefix(limit))
    }
}

protocol FeedRemotePostFetching {
    func fetchFeedPosts(limit: Int) async throws -> [FeedPostBundleDTO]
    func fetchFeedPosts(limit: Int, offset: Int) async throws -> [FeedPostBundleDTO]
    func fetchFeedPosts(limit: Int, offset: Int, audience: FeedAudience) async throws -> [FeedPostBundleDTO]
    func fetchSavedFeedPosts() async throws -> [FeedPostBundleDTO]
    /// Goes through the exact same RLS-scoped client as fetchFeedPosts —
    /// deliberately not a separate/elevated path, so a private post stays
    /// invisible to a single-row lookup exactly as it is to the list one.
    func fetchFeedPost(id: UUID) async throws -> FeedPostBundleDTO?
}

extension FeedRemotePostFetching {
    func fetchFeedPosts(limit: Int, offset: Int, audience: FeedAudience) async throws -> [FeedPostBundleDTO] {
        guard audience == .all else { throw FeedRepositoryError.remoteFetchNotImplemented }
        return try await fetchFeedPosts(limit: limit, offset: offset)
    }
    func fetchFeedPosts(limit: Int, offset: Int) async throws -> [FeedPostBundleDTO] {
        let posts = try await fetchFeedPosts(limit: limit + offset)
        return Array(posts.dropFirst(offset).prefix(limit))
    }
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

protocol FeedRemoteBookmarkPosting {
    func addBookmark(postId: UUID) async throws
    func removeBookmark(postId: UUID) async throws
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
        Array(items.sorted {
            let left = $0.activityDate ?? $0.createdAt
            let right = $1.activityDate ?? $1.createdAt
            return left == right ? $0.id.uuidString > $1.id.uuidString : left > right
        }.prefix(limit))
    }

    func fetchFeedPage(limit: Int, offset: Int) async throws -> [FeedItem] {
        Array(items.sorted {
            let left = $0.activityDate ?? $0.createdAt
            let right = $1.activityDate ?? $1.createdAt
            return left == right ? $0.id.uuidString > $1.id.uuidString : left > right
        }.dropFirst(offset).prefix(limit))
    }

    func fetchSavedPosts() async throws -> [FeedItem] {
        items.filter(\.viewerHasSaved)
    }

    func fetchPost(id: UUID) async throws -> FeedItem? {
        items.first { $0.id == id }
    }
}
