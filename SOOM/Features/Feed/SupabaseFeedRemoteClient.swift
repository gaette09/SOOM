import Foundation
import Supabase

struct SupabaseFeedRemoteClient: FeedRemotePostFetching, FeedRemoteProfileFetching, FeedRemotePostPosting, FeedRemoteReactionPosting, FeedRemoteCommentPosting, FeedRemotePostDeleting {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// The explicit `.or(...)` below doesn't change what RLS already
    /// returns — `feed_posts_select_owner_or_public` already scopes every
    /// query on this table to `user_id = auth.uid() or visibility =
    /// 'public'` server-side, so an unfiltered query already mixes the
    /// caller's own private posts in with everyone's public ones, and a
    /// caller can never see another user's private post no matter what
    /// filter this method sends (RLS isn't something a client-side query
    /// can widen). It's here to make that intent visible in the client
    /// code itself, not to open or close anything RLS doesn't already.
    func fetchFeedPosts(limit: Int) async throws -> [FeedPostBundleDTO] {
        let session = try await client.auth.session
        let posts: [FeedPostDTO] = try await client
            .from("feed_posts")
            .select()
            .or("visibility.eq.public,user_id.eq.\(session.user.id)")
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        guard !posts.isEmpty else {
            return []
        }

        let postIDs = posts.map(\.id)

        async let media: [FeedPostMediaDTO] = client
            .from("feed_post_media")
            .select()
            .in("post_id", values: postIDs)
            .execute()
            .value

        async let reactions: [FeedReactionDTO] = client
            .from("feed_reactions")
            .select()
            .in("post_id", values: postIDs)
            .execute()
            .value

        async let comments: [FeedCommentDTO] = client
            .from("feed_comments")
            .select()
            .in("post_id", values: postIDs)
            .execute()
            .value

        let (mediaRows, reactionRows, commentRows) = try await (media, reactions, comments)

        let mediaByPost = Dictionary(grouping: mediaRows, by: \.postId)
        let reactionsByPost = Dictionary(grouping: reactionRows, by: \.postId)
        let commentsByPost = Dictionary(grouping: commentRows, by: \.postId)

        return posts.map { post in
            FeedPostBundleDTO(
                post: post,
                media: mediaByPost[post.id] ?? [],
                reactions: reactionsByPost[post.id] ?? [],
                comments: commentsByPost[post.id] ?? []
            )
        }
    }

    /// Same shape as fetchFeedPosts, scoped to a single id via `.eq`
    /// instead of `.limit` — this is the exact same `client` (same
    /// authenticated session, same RLS) as every other method here, not a
    /// separate elevated path. A private post the caller doesn't own
    /// simply isn't in the returned rows.
    func fetchFeedPost(id: UUID) async throws -> FeedPostBundleDTO? {
        let posts: [FeedPostDTO] = try await client
            .from("feed_posts")
            .select()
            .eq("id", value: id)
            .execute()
            .value

        guard let post = posts.first else {
            return nil
        }

        async let media: [FeedPostMediaDTO] = client
            .from("feed_post_media")
            .select()
            .eq("post_id", value: id)
            .execute()
            .value

        async let reactions: [FeedReactionDTO] = client
            .from("feed_reactions")
            .select()
            .eq("post_id", value: id)
            .execute()
            .value

        async let comments: [FeedCommentDTO] = client
            .from("feed_comments")
            .select()
            .eq("post_id", value: id)
            .execute()
            .value

        let (mediaRows, reactionRows, commentRows) = try await (media, reactions, comments)

        return FeedPostBundleDTO(post: post, media: mediaRows, reactions: reactionRows, comments: commentRows)
    }

    func fetchProfiles(ids: [UUID]) async throws -> [FeedProfileDTO] {
        guard !ids.isEmpty else {
            return []
        }

        return try await client
            .from("profiles")
            .select()
            .in("id", values: ids)
            .execute()
            .value
    }

    /// Deliberately does not `.select()` the inserted row back. Chaining a
    /// decode step after a successful insert would let a decode failure
    /// masquerade as a post failure — the caller would then also save a
    /// local draft, producing a real duplicate (one row on the server, one
    /// draft that never syncs away). The caller only needs to know whether
    /// the insert itself succeeded.
    func postPublicPost(_ draft: FeedShareDraft, visibility: FeedPostVisibility) async throws {
        let session = try await client.auth.session
        let request = FeedPostInsertDTO(
            userId: session.user.id,
            sourceWorkoutId: draft.sourceWorkoutId,
            sport: draft.sport,
            title: draft.title,
            body: draft.body,
            distanceMeters: draft.distanceMeters,
            durationSeconds: Int(draft.durationSeconds),
            averagePaceSecondsPerKm: draft.averagePaceSecondsPerKm,
            visibility: visibility
        )

        try await client
            .from("feed_posts")
            .insert(request)
            .execute()
    }

    func updatePostVisibility(sourceWorkoutId: UUID, visibility: FeedPostVisibility) async throws {
        let session = try await client.auth.session
        try await client
            .from("feed_posts")
            .update(FeedPostVisibilityUpdateDTO(visibility: visibility))
            .eq("source_workout_id", value: sourceWorkoutId)
            .eq("user_id", value: session.user.id)
            .execute()
    }

    func addReaction(postId: UUID, reactionType: String) async throws {
        let session = try await client.auth.session
        let request = FeedReactionInsertDTO(postId: postId, userId: session.user.id, reactionType: reactionType)

        try await client
            .from("feed_reactions")
            .insert(request)
            .execute()
    }

    func removeReaction(postId: UUID, reactionType: String) async throws {
        let session = try await client.auth.session

        try await client
            .from("feed_reactions")
            .delete()
            .eq("post_id", value: postId)
            .eq("user_id", value: session.user.id)
            .eq("reaction_type", value: reactionType)
            .execute()
    }

    func addComment(postId: UUID, body: String) async throws {
        let session = try await client.auth.session
        let request = FeedCommentInsertDTO(postId: postId, userId: session.user.id, body: body)

        try await client
            .from("feed_comments")
            .insert(request)
            .execute()
    }

    func deletePost(id: UUID) async throws {
        try await client
            .from("feed_posts")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}

/// Same `client` instance as the rest of this type — read/mark-read scope
/// to `recipient_id = auth.uid()` per `notifications_v1.sql`'s RLS
/// (`notifications_select_recipient`/`notifications_update_read_at_recipient`),
/// so this can't see or touch another user's notifications regardless of
/// the explicit `.eq` filter below.
extension SupabaseFeedRemoteClient: NotificationInboxFetching {
    func fetchNotifications() async throws -> [NotificationDTO] {
        let session = try await client.auth.session
        return try await client
            .from("notifications")
            .select()
            .eq("recipient_id", value: session.user.id)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Batch-updates every currently-unread row for this recipient in one
    /// call, rather than one row at a time — matches the product decision
    /// (batch 1 of soom-notification-inbox) to mark everything read on
    /// inbox open, not per-row-tap.
    func markAllNotificationsAsRead() async throws {
        let session = try await client.auth.session
        try await client
            .from("notifications")
            .update(NotificationReadUpdateDTO(readAt: Date()))
            .eq("recipient_id", value: session.user.id)
            .is("read_at", value: nil)
            .execute()
    }
}

private struct NotificationReadUpdateDTO: Encodable {
    let readAt: Date

    enum CodingKeys: String, CodingKey {
        case readAt = "read_at"
    }
}
