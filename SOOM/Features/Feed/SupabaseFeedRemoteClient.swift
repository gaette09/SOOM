import Foundation
import Supabase

struct SupabaseFeedRemoteClient: FeedRemotePostFetching, FeedRemoteProfileFetching, FeedRemotePostPosting, FeedRemoteReactionPosting, FeedRemoteCommentPosting, FeedRemotePostDeleting {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchFeedPosts(limit: Int) async throws -> [FeedPostBundleDTO] {
        let posts: [FeedPostDTO] = try await client
            .from("feed_posts")
            .select()
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
