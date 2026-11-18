import Foundation
import Supabase

struct SupabaseFeedRemoteClient: FeedRemotePostFetching, FeedRemoteProfileFetching, FeedRemotePostPosting, FeedRemoteReactionPosting, FeedRemoteCommentPosting, FeedRemoteBookmarkPosting, FeedRemotePostDeleting {
    private let client: SupabaseClient
    private let expectedPostingUserID: UUID?
    private let pages = FeedKeysetPages()

    init(client: SupabaseClient) {
        self.client = client
        self.expectedPostingUserID = nil
    }

    init(client: SupabaseClient, expectedPostingUserID: UUID) {
        self.client = client
        self.expectedPostingUserID = expectedPostingUserID
    }

    private func validatePostingAccount(_ expectedUserID: UUID) async throws {
        try await MainActor.run { try CommunitySafetyStore.shared.requireSocialAccess(viewerID: expectedUserID) }
        guard client.auth.currentSession?.user.id == expectedUserID else {
            throw CommunitySafetyError.accountChanged
        }
    }

    /// The server applies the current owner/public/mutual policy before paging.
    /// A fresh RLS check after hydration prevents stale grants reaching the UI.
    func fetchFeedPosts(limit: Int) async throws -> [FeedPostBundleDTO] {
        try await fetchFeedPosts(limit: limit, offset: 0)
    }

    func fetchFeedPosts(limit: Int, offset: Int) async throws -> [FeedPostBundleDTO] {
        try await fetchFeedPosts(limit: limit, offset: offset, audience: .all)
    }

    func fetchFeedPosts(limit: Int, offset: Int, audience: FeedAudience) async throws -> [FeedPostBundleDTO] {
        guard audience != .home else { throw FeedRepositoryError.remoteFetchNotImplemented }
        return try await authorizedPage(scope: audience.rawValue, authorID: nil, limit: limit, offset: offset)
    }

    private func authorizedPage(scope: String, authorID: UUID?, limit: Int, offset: Int) async throws -> [FeedPostBundleDTO] {
        guard limit > 0, limit <= 500, offset >= 0 else { return [] }
        let session = try await client.auth.session
        let viewer = session.user.id
        try await validatePostingAccount(viewer)
        let revision = await MainActor.run { CommunitySafetyStore.shared.revision }
        let token = try await pages.begin(scope: scope, authorID: authorID, offset: offset, viewer: viewer, revision: revision)
        struct Params: Encodable {
            let p_scope: String; let p_author: UUID?; let p_before: Date?; let p_before_id: UUID?; let p_limit: Int
        }
        let posts: [FeedPostDTO] = try await client.rpc("soom_feed_page", params: Params(p_scope: scope, p_author: authorID,
            p_before: token.date, p_before_id: token.postID, p_limit: limit)).execute().value
        let bundles = try await hydrateFeedPosts(posts, viewerID: viewer)
        try await validatePostingAccount(viewer)
        guard revision == (await MainActor.run { CommunitySafetyStore.shared.revision }), !Task.isCancelled else { throw CancellationError() }
        // Recheck RLS after media hydration. A revoked row never reaches the UI.
        let confirmed: [FeedPostDTO] = posts.isEmpty ? [] : try await client.from("feed_posts").select()
            .in("id", values: posts.map(\.id)).limit(posts.count).execute().value
        try await validatePostingAccount(viewer)
        guard revision == (await MainActor.run { CommunitySafetyStore.shared.revision }), !Task.isCancelled else { throw CancellationError() }
        let byID = Dictionary(uniqueKeysWithValues: confirmed.map { ($0.id,$0) })
        // Reject the whole page if access or content changed while hydrating.
        // Returning a shortened page would corrupt its cursor/page boundary.
        guard bundles.allSatisfy({ byID[$0.post.id] == $0.post }) else { throw CancellationError() }
        try await pages.finish(token: token, rows: posts, offset: offset)
        return bundles
    }

    /// A club lists only its members' public posts, including for the owner.
    /// Chunking keeps the PostgREST URL bounded without dropping members.
    func fetchPublicMemberPosts(authorIDs: [UUID], viewerID: UUID, limit: Int) async throws -> [FeedPostBundleDTO] {
        try await validatePostingAccount(viewerID)
        let boundedLimit = min(max(limit, 1), 50)
        let members = Array(Set(authorIDs)).sorted { $0.uuidString < $1.uuidString }
        var candidates: [FeedPostDTO] = []
        for offset in stride(from: 0, to: members.count, by: 100) {
            try await validatePostingAccount(viewerID)
            let ids = Array(members[offset..<min(offset + 100, members.count)])
            let rows: [FeedPostDTO] = try await client.from("feed_posts").select()
                .eq("visibility", value: "public").in("user_id", values: ids)
                .order("activity_at", ascending: false).order("id", ascending: false)
                .limit(boundedLimit).execute().value
            try await validatePostingAccount(viewerID)
            candidates.append(contentsOf: rows.filter { $0.visibility == .publicPost && ids.contains($0.userId) })
        }
        let posts = Array(candidates.sorted {
            ($0.routeSummary?.startedAt ?? $0.createdAt) == ($1.routeSummary?.startedAt ?? $1.createdAt) ? $0.id.uuidString > $1.id.uuidString : ($0.routeSummary?.startedAt ?? $0.createdAt) > ($1.routeSummary?.startedAt ?? $1.createdAt)
        }.prefix(boundedLimit))
        let bundles = try await hydrateFeedPosts(posts, viewerID: viewerID)
        try await validatePostingAccount(viewerID)
        guard !posts.isEmpty else { return [] }
        // Hydrating photos/comments can cross a visibility change. Resolve the
        // public rows again before exposing a completed club snapshot.
        let confirmed: [FeedPostDTO] = try await client.from("feed_posts").select()
            .eq("visibility", value: "public").in("id", values: posts.map(\.id))
            .limit(boundedLimit).execute().value
        try await validatePostingAccount(viewerID)
        return bundles.compactMap { bundle in
            guard let current = confirmed.first(where: { $0.id == bundle.post.id }),
                  current == bundle.post, current.visibility == .publicPost, current.userId == bundle.post.userId else { return nil }
            return FeedPostBundleDTO(post: current, media: bundle.media, reactions: bundle.reactions,
                comments: bundle.comments, bookmarks: bundle.bookmarks,
                sharedDetail: bundle.sharedDetail, sharedDetailContractEnabled: bundle.sharedDetailContractEnabled)
        }
    }

    /// Preview-only read path. Uses the signed-in client's existing RLS, never
    /// changes the social write gate or includes a non-followed public account.
    @MainActor
    func previewLegacyHome(_ request: AccountActivityPageRequest, postID: UUID? = nil) async throws -> [FeedItem] {
        try request.validate()
        let safety = CommunitySafetyStore.shared
        let context = AccountActivityReadContext(viewerID: request.viewerID, generation: safety.accountGeneration, safetyRevision: safety.revision)
        func check() throws {
            guard !Task.isCancelled, safety.viewerID == context.viewerID,
                  safety.accountGeneration == context.generation, safety.revision == context.safetyRevision,
                  safety.canUseSocial || safety.canUseActivityPreview,
                  client.auth.currentSession?.user.id == context.viewerID,
                  !AccountDeletionWriteFence.shared.isRetired(context.viewerID) else { throw CommunitySafetyError.accountChanged }
        }
        try check()
        var legacy: [FeedItem] = [], summary: [FeedItem] = []
        var legacySucceeded = false, summarySucceeded = false
        var firstError: Error?
        do { legacy = try await previewLegacyRLSHome(request, postID: postID); legacySucceeded = true }
        catch { firstError = error }
        try check()
        do { summary = try await previewLegacyPublicSummary(request, postID: postID, context: context); summarySucceeded = true }
        catch { if firstError == nil { firstError = error } }
        try check()
        guard legacySucceeded || summarySucceeded else { throw firstError ?? CommunitySafetyError.unavailable }
        return PreviewLegacySummaryMerge.merge(legacy: legacy, summaries: summary, limit: postID == nil ? request.limit : 1)
    }

    @MainActor
    func previewLegacySummaryCard(postID: UUID, context: AccountActivityReadContext) async throws -> FeedItem? {
        try await previewLegacyPublicSummary(.init(viewerID: context.viewerID, scope: .home, ownerID: nil, before: nil, limit: 1),
            postID: postID, context: context, notification: false).first
    }

    @MainActor
    private func previewLegacyPublicSummary(_ request: AccountActivityPageRequest, postID: UUID?, context: AccountActivityReadContext, notification: Bool = true) async throws -> [FeedItem] {
        let safety = CommunitySafetyStore.shared
        func check() throws {
            guard safety.canUseActivityPreview, safety.viewerID == context.viewerID,
                  safety.accountGeneration == context.generation, safety.revision == context.safetyRevision,
                  client.auth.currentSession?.user.id == context.viewerID, !Task.isCancelled,
                  !AccountDeletionWriteFence.shared.isRetired(context.viewerID) else { throw CommunitySafetyError.accountChanged }
        }
        try check()
        guard try await AccountActivityPreviewService(client: client, owner: context.viewerID).capability().enabled else { throw CommunitySafetyError.unavailable }
        try check()
        struct Params: Encodable {
            let p_scope: String; let p_post_id: UUID?; let p_before_at: Date?; let p_before_id: UUID?; let p_limit: Int
        }
        let params = Params(p_scope: postID == nil || !notification ? "home" : "notification", p_post_id: postID,
            p_before_at: postID == nil ? request.before?.activityAt : nil,
            p_before_id: postID == nil ? request.before?.cardID : nil, p_limit: postID == nil ? request.limit : 1)
        let rows: [PreviewLegacyPublicSummary] = try await client.rpc("soom_legacy_public_summary_preview_v1", params: params).execute().value
        try check()
        try PreviewLegacyPublicSummary.validate(rows, request: request, postID: postID, now: Date(), blocked: safety.isBlocked)
        // Do not hydrate photos, routes, heart rate, prose or identities from a
        // summary permission. Re-read the same narrowed receipt before display.
        let confirmed: [PreviewLegacyPublicSummary] = try await client.rpc("soom_legacy_public_summary_preview_v1", params: params).execute().value
        try check()
        guard confirmed == rows else { throw AccountActivityAdapterError.changedDuringRead }
        return rows.map { $0.feedItem(context: context) }
    }

    @MainActor
    private func previewLegacyRLSHome(_ request: AccountActivityPageRequest, postID: UUID? = nil) async throws -> [FeedItem] {
        try request.validate()
        let safety = CommunitySafetyStore.shared
        guard (safety.canUseSocial || safety.canUseActivityPreview), safety.viewerID == request.viewerID,
              client.auth.currentSession?.user.id == request.viewerID else { throw CommunitySafetyError.accountChanged }
        let generation = safety.accountGeneration, revision = safety.revision
        func check() throws {
            guard !Task.isCancelled, (safety.canUseSocial || safety.canUseActivityPreview), safety.viewerID == request.viewerID,
                  safety.accountGeneration == generation, safety.revision == revision,
                  client.auth.currentSession?.user.id == request.viewerID else { throw CommunitySafetyError.accountChanged }
        }
        struct Follow: Decodable { let followed_id: UUID }
        func follows() async throws -> Set<UUID> {
            let rows: [Follow] = try await client.from("user_follows").select("followed_id")
                .eq("follower_id", value: request.viewerID).limit(501).execute().value
            guard rows.count <= 500 else { throw AccountActivityContractError.invalidRequest }
            try check(); return Set(rows.map(\.followed_id))
        }
        let following = postID == nil ? try await follows() : Set<UUID>()
        let authors = Array(following.union([request.viewerID])).map { $0.uuidString.lowercased() }.sorted()
        var query = client.from("feed_posts").select()
        if postID == nil { query = query.in("user_id", values: authors) }
        let visibility = "visibility.eq.public,visibility.eq.followers,user_id.eq.\(request.viewerID.uuidString.lowercased())"
        if let postID { query = query.eq("id", value: postID) }
        if let before = request.before {
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = formatter.string(from: before.activityAt)
            query = query.or("and(or(\(visibility)),or(activity_at.lt.\(date),and(activity_at.eq.\(date),id.lt.\(before.cardID.uuidString.lowercased()))))")
        } else if postID == nil { query = query.or(visibility) }
        let posts: [FeedPostDTO] = try await query.order("activity_at", ascending: false).order("id", ascending: false)
            .limit(postID == nil ? request.limit : 1).execute().value
        try check()
        guard posts.allSatisfy({ postID != nil ? !safety.isBlocked($0.userId) : PreviewLegacyReadPolicy.permits(owner: $0.userId, isPublic: $0.visibility == .publicPost, isFollowers: $0.visibility == .followers && $0.audienceContract == 1, viewer: request.viewerID, following: following, blocked: safety.isBlocked($0.userId)) }) else { throw AccountActivityContractError.invalidRow }
        let bundles = try await hydrateFeedPosts(posts, viewerID: request.viewerID, includeSharedDetail: false)
        let profiles: [FeedProfileDTO] = posts.isEmpty ? [] : try await client.from("profiles").select().in("id", values: Array(Set(posts.map(\.userId)))).limit(100).execute().value
        try check()
        let confirmed: [FeedPostDTO] = posts.isEmpty ? [] : try await client.from("feed_posts").select()
            .in("id", values: posts.map(\.id)).limit(posts.count).execute().value
        let finalFollows = postID == nil ? try await follows() : Set<UUID>(); try check()
        let byID = Dictionary(uniqueKeysWithValues: confirmed.map { ($0.id, $0) })
        guard finalFollows == following, posts.allSatisfy({ byID[$0.id] == $0 }) else { throw AccountActivityAdapterError.changedDuringRead }
        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        return bundles.map { bundle in
            let profile = profileMap[bundle.post.userId]
            var item = bundle.makeFeedItem(authorName: profile?.displayName ?? "SOOM 사용자", authorHandle: profile?.handle,
                avatarPath: profile?.avatarPath, currentUserId: request.viewerID, profilesByID: profileMap)
            item.previewLegacyReadContext = .init(viewerID: request.viewerID, generation: generation, safetyRevision: revision)
            return item
        }
    }

    private func hydrateFeedPosts(_ posts: [FeedPostDTO], viewerID: UUID, includeSharedDetail: Bool = true) async throws -> [FeedPostBundleDTO] {
        guard !posts.isEmpty else { return [] }
        let postIDs = posts.map(\.id)
        let shared: (enabled: Bool, snapshots: [WorkoutSharedDetailSnapshot]) = includeSharedDetail ? try await SupabaseWorkoutSharedDetailService(client: client).fetch(posts: posts) : (false, [])

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
            .order("created_at").order("id")
            .execute()
            .value

        async let comments: [FeedCommentDTO] = client
            .from("feed_comments")
            .select()
            .in("post_id", values: postIDs)
            .order("created_at", ascending: false).order("id", ascending: false)
            .execute()
            .value

        async let bookmarks: [FeedBookmarkDTO] = client
            .from("feed_bookmarks")
            .select()
            .eq("user_id", value: viewerID)
            .in("post_id", values: postIDs)
            .execute()
            .value

        let (mediaRows, reactionRows, commentRows, bookmarkRows) = try await (media, reactions, comments, bookmarks)

        let mediaByPost = Dictionary(grouping: mediaRows, by: \.postId)
        let reactionsByPost = Dictionary(grouping: reactionRows, by: \.postId)
        let commentsByPost = Dictionary(grouping: commentRows, by: \.postId)
        let bookmarksByPost = Dictionary(grouping: bookmarkRows, by: \.postId)

        return posts.map { post in
            FeedPostBundleDTO(
                post: post,
                media: mediaByPost[post.id] ?? [],
                reactions: reactionsByPost[post.id] ?? [],
                comments: commentsByPost[post.id] ?? [],
                bookmarks: bookmarksByPost[post.id] ?? [],
                sharedDetail: shared.snapshots.first { $0.postID == post.id },
                sharedDetailContractEnabled: shared.enabled
            )
        }
    }

    func fetchSavedFeedPosts() async throws -> [FeedPostBundleDTO] {
        let session = try await client.auth.session
        let savedBookmarkRows: [FeedBookmarkDTO] = try await client
            .from("feed_bookmarks")
            .select()
            .eq("user_id", value: session.user.id)
            .order("created_at", ascending: false)
            .execute()
            .value

        guard !savedBookmarkRows.isEmpty else {
            return []
        }

        let savedPostIDs = savedBookmarkRows.map(\.postId)
        let posts: [FeedPostDTO] = try await client
            .from("feed_posts")
            .select()
            .in("id", values: savedPostIDs)
            .execute()
            .value

        guard !posts.isEmpty else {
            return []
        }

        let bundles = try await hydrateFeedPosts(posts, viewerID: session.user.id)
        let confirmed: [FeedPostDTO] = try await client.from("feed_posts").select().in("id", values: posts.map(\.id)).execute().value
        try await validatePostingAccount(session.user.id)
        let current = Dictionary(uniqueKeysWithValues: confirmed.map { ($0.id,$0) })
        let byID = Dictionary(uniqueKeysWithValues: bundles.filter { current[$0.post.id] == $0.post }.map { ($0.post.id,$0) })
        return savedBookmarkRows.compactMap { byID[$0.postId] }
    }

    /// Same shape as fetchFeedPosts, scoped to a single id via `.eq`
    /// instead of `.limit` — this is the exact same `client` (same
    /// authenticated session, same RLS) as every other method here, not a
    /// separate elevated path. A private post the caller doesn't own
    /// simply isn't in the returned rows.
    func fetchFeedPost(id: UUID) async throws -> FeedPostBundleDTO? {
        try await fetchFeedPost(id: id, loadAllComments: false)
    }

    func fetchFeedPost(id: UUID, loadAllComments: Bool, loadAllReactions: Bool = false) async throws -> FeedPostBundleDTO? {
        let session = try await client.auth.session
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

        async let reactions = fetchReactions(postID: id, viewerID: session.user.id, loadAllPages: loadAllReactions)

        async let comments = fetchComments(postID: id, viewerID: session.user.id, loadAllPages: loadAllComments)

        async let bookmarks: [FeedBookmarkDTO] = client
            .from("feed_bookmarks")
            .select()
            .eq("user_id", value: session.user.id)
            .eq("post_id", value: id)
            .execute()
            .value

        let (mediaRows, reactionRows, commentRows, bookmarkRows) = try await (media, reactions, comments, bookmarks)

        let shared = try await SupabaseWorkoutSharedDetailService(client: client).fetch(posts: [post])
        let confirmed: [FeedPostDTO] = try await client.from("feed_posts").select().eq("id", value: post.id).limit(1).execute().value
        try await validatePostingAccount(session.user.id)
        guard confirmed.first == post else { throw FeedPostManagementError.contentUnavailable }
        return FeedPostBundleDTO(
            post: post,
            media: mediaRows,
            reactions: reactionRows,
            comments: commentRows,
            bookmarks: bookmarkRows,
            sharedDetail: shared.snapshots.first, sharedDetailContractEnabled: shared.enabled
        )
    }

    /// Full participant reads are reserved for the opened cheer list. Ordinary
    /// cards keep one bounded request, ordered so their first-three preview is stable.
    private func fetchReactions(postID: UUID, viewerID: UUID, loadAllPages: Bool) async throws -> [FeedReactionDTO] {
        var result: [FeedReactionDTO] = []
        let pageSize = loadAllPages ? 200 : 1_000
        while true {
            try await validatePostingAccount(viewerID)
            try Task.checkCancellation()
            let page: [FeedReactionDTO] = try await client.from("feed_reactions").select()
                .eq("post_id", value: postID).order("created_at").order("id")
                .range(from: result.count, to: result.count + pageSize - 1).execute().value
            try await validatePostingAccount(viewerID)
            result.append(contentsOf: page)
            if !loadAllPages || page.count < pageSize { return result }
        }
    }

    private func fetchComments(postID: UUID, viewerID: UUID, loadAllPages: Bool) async throws -> [FeedCommentDTO] {
        var result: [FeedCommentDTO] = []
        while true {
            try await validatePostingAccount(viewerID)
            try Task.checkCancellation()
            let page: [FeedCommentDTO] = try await client.from("feed_comments").select()
                .eq("post_id", value: postID).order("created_at", ascending: false).order("id", ascending: false)
                .range(from: result.count, to: result.count + 199).execute().value
            try await validatePostingAccount(viewerID)
            result.append(contentsOf: page)
            if !loadAllPages || page.count < 200 { return result }
        }
    }

    /// Historical name; includes only rows the current viewer's RLS permits.
    func fetchPublicProfilePosts(authorID: UUID, viewerID: UUID, offset: Int, limit: Int) async throws -> [FeedPostBundleDTO] {
        try await validatePostingAccount(viewerID)
        return try await authorizedPage(scope: "profile", authorID: authorID, limit: limit, offset: offset)
    }

    func fetchProfiles(ids: [UUID]) async throws -> [FeedProfileDTO] {
        guard !ids.isEmpty else { return [] }
        let session = try await client.auth.session
        let values = Array(Set(ids))
        var profiles: [FeedProfileDTO] = []
        for offset in stride(from: 0, to: values.count, by: 100) {
            try Task.checkCancellation()
            try await validatePostingAccount(session.user.id)
            let rows: [FeedProfileDTO] = try await client.from("profiles").select()
                .in("id", values: Array(values[offset..<min(offset + 100, values.count)]))
                .execute().value
            try await validatePostingAccount(session.user.id)
            profiles.append(contentsOf: rows)
        }
        return profiles
    }

    /// Re-sharing updates the original posts, including their visibility.
    /// New posts use the same stable ID as the workout management surface.
    func postPublicPost(_ draft: FeedShareDraft, visibility: FeedPostVisibility) async throws {
        guard let authorID = expectedPostingUserID ?? client.auth.currentSession?.user.id else {
            throw CommunitySafetyError.signInRequired
        }
        try await validatePostingAccount(authorID)
        let session = try await client.auth.session
        guard session.user.id == authorID else { throw CommunitySafetyError.accountChanged }
        try await validatePostingAccount(authorID)
        var request = FeedPostInsertDTO(
            // Keep the original owner in the body. If the token switches
            // while INSERT awaits, RLS rejects A's row authenticated as B.
            userId: authorID,
            sourceWorkoutId: draft.sourceWorkoutId,
            sport: draft.sport,
            title: draft.title,
            body: draft.body,
            distanceMeters: draft.distanceMeters,
            durationSeconds: Int(draft.durationSeconds),
            averagePaceSecondsPerKm: draft.averagePaceSecondsPerKm,
            visibility: visibility,
            routeSummary: FeedRouteSummaryDTO(startedAt: draft.activityDate,
                deviceName: draft.deviceName, locationName: draft.locationName)
        )

        do {
            try await validatePostingAccount(authorID)
            let existing: [PostWriteReceipt] = try await client.from("feed_posts").select("id")
                .eq("user_id", value: authorID).eq("source_workout_id", value: draft.sourceWorkoutId)
                .execute().value
            try await validatePostingAccount(authorID)
            let changed: [PostWriteReceipt]
            let expected: Set<UUID>
            if existing.isEmpty {
                let id = SupabaseWorkoutRecordRemote.postID(owner: authorID, workout: draft.sourceWorkoutId)
                request.id = id
                expected = [id]
                changed = try await client.from("feed_posts").upsert(request, onConflict: "id")
                    .select("id").execute().value
            } else {
                expected = Set(existing.map(\.id))
                changed = try await client.from("feed_posts").update(request)
                    .eq("user_id", value: authorID).eq("source_workout_id", value: draft.sourceWorkoutId)
                    .select("id").execute().value
            }
            try await validatePostingAccount(authorID)
            guard expected.isSubset(of: Set(changed.map(\.id))) else {
                throw WorkoutRecordManagementError.unavailable
            }
        } catch {
            try await validatePostingAccount(authorID)
            throw error
        }
    }

    private struct PostWriteReceipt: Decodable { let id: UUID }

    func updatePostVisibility(sourceWorkoutId: UUID, visibility: FeedPostVisibility) async throws {
        let session = try await client.auth.session
        try await client
            .from("feed_posts")
            .update(FeedPostVisibilityUpdateDTO(visibility: visibility))
            .eq("source_workout_id", value: sourceWorkoutId)
            .eq("user_id", value: session.user.id)
            .execute()
    }

    // Preview legacy receipts authorize reads only. Capture the original writer
    // before any suspension, and never substitute a newly signed-in account.
    @MainActor private func reactionWriteContext() throws -> AccountActivityReadContext {
        let safety = CommunitySafetyStore.shared
        guard let viewer = safety.viewerID, client.auth.currentSession?.user.id == viewer,
              expectedPostingUserID == nil || expectedPostingUserID == viewer else {
            throw CommunitySafetyError.accountChanged
        }
        try safety.requireSocialAccess(viewerID: viewer)
        return .init(viewerID: viewer, generation: safety.accountGeneration, safetyRevision: safety.revision)
    }

    @MainActor private func validateReactionWrite(_ expected: AccountActivityReadContext) throws {
        guard try reactionWriteContext() == expected else { throw CommunitySafetyError.accountChanged }
    }

    @MainActor func addReaction(postId: UUID, reactionType: String) async throws {
        let context = try reactionWriteContext()
        let session = try await client.auth.session
        try validateReactionWrite(context)
        guard session.user.id == context.viewerID else { throw CommunitySafetyError.accountChanged }
        let request = FeedReactionInsertDTO(postId: postId, userId: context.viewerID, reactionType: reactionType)
        try await client.from("feed_reactions").insert(request).execute()
        try validateReactionWrite(context)
    }

    @MainActor func removeReaction(postId: UUID, reactionType: String) async throws {
        let context = try reactionWriteContext()
        let session = try await client.auth.session
        try validateReactionWrite(context)
        guard session.user.id == context.viewerID else { throw CommunitySafetyError.accountChanged }
        try await client.from("feed_reactions").delete()
            .eq("post_id", value: postId)
            .eq("user_id", value: context.viewerID)
            .eq("reaction_type", value: reactionType).execute()
        try validateReactionWrite(context)
    }

    func addComment(postId: UUID, body: String) async throws {
        let session = try await client.auth.session
        let request = FeedCommentInsertDTO(postId: postId, userId: session.user.id, body: body)

        try await client
            .from("feed_comments")
            .insert(request)
            .execute()
    }

    func addBookmark(postId: UUID) async throws {
        let session = try await client.auth.session
        let request = FeedBookmarkInsertDTO(postId: postId, userId: session.user.id)

        try await client
            .from("feed_bookmarks")
            .insert(request)
            .execute()
    }

    func removeBookmark(postId: UUID) async throws {
        let session = try await client.auth.session
        try await client
            .from("feed_bookmarks")
            .delete()
            .eq("post_id", value: postId)
            .eq("user_id", value: session.user.id)
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
    @MainActor func fetchUnreadNotificationCount() async throws -> Int {
        let session = try await client.auth.session
        let nativeEnabled = AccountActivityNativeInboxGate.productionReady && AccountActivityFeedReleaseGate.productionReady && AccountActivityInteractionReleaseGate.productionReady
        let safety = CommunitySafetyStore.shared
        let currentContext: () -> AccountActivityReadContext? = {
            guard safety.canUseSocial || safety.canUseActivityPreview, let viewer = safety.viewerID,
                  self.client.auth.currentSession?.user.id == viewer,
                  !AccountDeletionWriteFence.shared.isRetired(viewer) else { return nil }
            return .init(viewerID: viewer, generation: safety.accountGeneration, safetyRevision: safety.revision)
        }
        let initialContext = currentContext()
        if ProfileActivitySocialReleaseGate.productionReady, safety.canUseSocial {
            guard let expected = initialContext, expected.viewerID == session.user.id else { throw NotificationInboxError.upgradeRequired }
            // New social inbox owns legacy social event namespaces as well as
            // app-only intents. Count follows separately, never double-count old events.
            let follows = try await client.schema("public").rpc("soom_notifications_v2", head: true, count: .exact)
                .in("type", values: ["follow_request", "follow_approved"]).is("read_at", value: nil).execute().count
            guard currentContext() == expected, let follows, follows >= 0 else { throw NotificationInboxError.upgradeRequired }
            let social = try await ProfileSocialInboxAdapter.live(client: client).load(limit: 1).unread_count
            guard currentContext() == expected else { throw NotificationInboxError.upgradeRequired }
            let native = try await AccountActivityNativeInboxAdapter.makeLive(client: client, context: currentContext,
                preview: false, readPolicy: .profileOnlyV2).unreadCount(context: expected)
            guard currentContext() == expected else { throw NotificationInboxError.upgradeRequired }
            return try AccountActivityUnreadTotal.combine(legacy: AccountActivityUnreadTotal.combine(legacy: follows, native: social), native: native)
        }
        let count: Int?
        if !safety.canUseSocial && safety.canUseActivityPreview {
            count = 0 // Preview-only mode must not unlock legacy notification reads.
        } else { do {
            // Exact server count includes all visible rows beyond the API page
            // limit, with the same hidden/read/moderation rules as the inbox.
            count = try await client.schema("public").rpc("soom_notifications_v2", head: true, count: .exact)
                .is("read_at", value: nil).execute().count
        } catch let error as PostgrestError where error.code == "PGRST202" {
            count = try await client.from("notifications").select("id", head: true, count: .exact)
                .eq("recipient_id", value: session.user.id).is("read_at", value: nil).execute().count
        }
        }
        guard client.auth.currentSession?.user.id == session.user.id,
              let count, count >= 0 else { throw NotificationInboxError.upgradeRequired }
        // Preserve the legacy badge for non-social/non-enrolled accounts. Preview
        // participation is fresh server authority, never a cached global flag.
        guard let expected = initialContext, expected.viewerID == session.user.id else {
            guard !nativeEnabled else { throw NotificationInboxError.upgradeRequired }
            return count
        }
        guard currentContext() == expected else { throw NotificationInboxError.upgradeRequired }
        var preview = false
        if !nativeEnabled {
            let capability: AccountActivityPreviewCapability
            do { capability = try await AccountActivityPreviewService(client: client, owner: expected.viewerID).capability() }
            catch let error as PostgrestError where error.code == "PGRST202" {
                guard currentContext() == expected else { throw NotificationInboxError.upgradeRequired }
                return count // Server predates optional preview capability.
            }
            guard currentContext() == expected else { throw NotificationInboxError.upgradeRequired }
            guard capability.enabled else { return count }
            preview = true
        }
        let native = try await AccountActivityNativeInboxAdapter.makeLive(client: client, context: currentContext, preview: preview).unreadCount(context: expected)
        guard currentContext() == expected else { throw NotificationInboxError.upgradeRequired }
        return try AccountActivityUnreadTotal.combine(legacy: count, native: native)
    }

    func fetchNotifications() async throws -> [NotificationDTO] {
        let session = try await client.auth.session
        if ProfileActivitySocialReleaseGate.productionReady {
            // Do not let NotificationInboxModel's automatic mark-read mutate old
            // social states. The typed social section uses a preserving overlay.
            let rows: [NotificationDTO] = try await client.rpc("soom_notifications_v2")
                .in("type", values: ["follow_request", "follow_approved"]).execute().value
            try await validatePostingAccount(session.user.id)
            guard rows.allSatisfy({ $0.recipientId == session.user.id && ($0.type == .followRequest || $0.type == .followApproved) }) else { throw NotificationInboxError.upgradeRequired }
            return rows
        }
        do { return try await client.rpc("soom_notifications_v2").execute().value }
        catch let error as PostgrestError where error.code == "PGRST202" { /* old server: legacy inbox only */ }
        return try await client
            .from("notifications")
            .select()
            .eq("recipient_id", value: session.user.id)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func markNotificationsAsRead(ids: [UUID]) async throws {
        struct Params: Encodable { let p_ids: [UUID] }
        do { try await client.rpc("soom_mark_notifications_read_v2", params:Params(p_ids:ids)).execute() }
        catch let error as PostgrestError where error.code == "PGRST202" {
            guard !ProfileActivitySocialReleaseGate.productionReady else { throw error }
            try await markAllNotificationsAsRead()
        }
    }
    func hideNotification(id:UUID) async throws {
        struct Params: Encodable { let p_id: UUID }
        try await client.rpc("soom_hide_notification_v2",params:Params(p_id:id)).execute()
    }
    func restoreNotification(id:UUID) async throws {
        struct Params: Encodable { let p_id: UUID }
        try await client.rpc("soom_restore_notification_v2",params:Params(p_id:id)).execute()
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

// Distinct source namespaces; never truncate or wrap an authoritative badge count.
enum AccountActivityUnreadTotal {
    static func combine(legacy: Int, native: Int) throws -> Int {
        let (total, overflow) = legacy.addingReportingOverflow(native)
        guard legacy >= 0, native >= 0, !overflow else { throw NotificationInboxError.upgradeRequired }
        return total
    }
}


enum PreviewLegacyReadPolicy {
    static func permits(owner: UUID, isPublic: Bool, isFollowers: Bool = false, viewer: UUID, following: Set<UUID>, blocked: Bool) -> Bool {
        // Local home membership is an additional filter, never proof of server
        // permission. Only freshly authenticated RLS-returned rows reach here.
        !blocked && (owner == viewer || ((isPublic || isFollowers) && following.contains(owner)))
    }
}

extension SupabaseFeedRemoteClient: LegacyInboxPreviewReading {
    @MainActor func readLegacyInboxPreview(owner: UUID) async throws -> [NotificationDTO] {
        let safety = CommunitySafetyStore.shared
        let generation = safety.accountGeneration, revision = safety.revision
        func check() throws {
            guard safety.canUseActivityPreview, safety.viewerID == owner,
                  safety.accountGeneration == generation, safety.revision == revision,
                  client.auth.currentSession?.user.id == owner,
                  !AccountDeletionWriteFence.shared.isRetired(owner), !Task.isCancelled else {
                throw NotificationInboxError.upgradeRequired
            }
        }
        try check()
        guard try await AccountActivityPreviewService(client: client, owner: owner).capability().enabled else {
            throw NotificationInboxError.upgradeRequired
        }
        try check()
        // Existing RPC keeps recipient, hidden, block, moderation and post access
        // checks. Never fall back to a broader table read if that contract fails.
        let rows: [NotificationDTO] = try await client.rpc("soom_notifications_v2")
            .eq("recipient_id", value: owner).limit(100).execute().value
        try check()
        guard rows.allSatisfy({ $0.recipientId == owner }) else { throw NotificationInboxError.upgradeRequired }
        return rows
    }
}

/// Deliberately has no narrative, media, route, heart-rate or comment fields.
struct PreviewLegacyPublicSummary: Decodable, Equatable {
    let post_id: UUID
    let owner_id: UUID
    let sport: String
    let activity_at: String
    let duration_seconds: Double?
    let distance_meters: Double?
    var date: Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: activity_at) { return date }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: activity_at)
    }
    static func validate(_ rows: [Self], request: AccountActivityPageRequest, postID: UUID?, now: Date, blocked: (UUID) -> Bool) throws {
        guard rows.count <= (postID == nil ? request.limit : 1), Set(rows.map(\.post_id)).count == rows.count else { throw AccountActivityContractError.invalidRow }
        var prior = postID == nil ? request.before : nil
        for row in rows {
            guard postID == nil || row.post_id == postID,
                  !blocked(row.owner_id), UnifiedWorkoutType(rawValue: row.sport) != nil,
                  let date = row.date, date <= now,
                  row.duration_seconds.map({ $0.isFinite && (0...604800).contains($0) }) ?? true,
                  row.distance_meters.map({ $0.isFinite && (0...10_000_000).contains($0) }) ?? true else { throw AccountActivityContractError.invalidRow }
            if let prior {
                guard date < prior.activityAt || (date == prior.activityAt && row.post_id.uuidString.lowercased() < prior.cardID.uuidString.lowercased()) else { throw AccountActivityContractError.invalidOrder }
            }
            prior = .init(activityAt: date, cardID: row.post_id)
        }
    }
    func feedItem(context: AccountActivityReadContext) -> FeedItem {
        let type = UnifiedWorkoutType(rawValue: sport) ?? .other
        let model = ShareableWorkoutCardModel(id: post_id, workoutType: type, title: "공개 운동 요약",
            distanceText: distance_meters.map { String(format: "%.2f km", $0 / 1000) } ?? "거리 없음",
            durationText: duration_seconds.map { "\(Int($0 / 60))분" } ?? "시간 정보 없음", averagePaceText: "—",
            primaryMessage: "공개가 확인된 운동 요약", growthMessage: "읽기 전용", recoveryMessage: "", footerText: "SOOM",
            visibility: .publicFeed, staticRoutePreview: .init(imageURL: nil, bounds: nil, routeExists: false,
                fallbackStyle: .init(workoutType: type)))
        var item = FeedItem(id: post_id, authorName: "SOOM 사용자", authorHandle: nil, authorId: owner_id,
            createdAt: date ?? .distantPast, itemType: .workoutSession, visibility: .publicFeed,
            cardData: .workoutSession(model), caption: nil, activityContext: "공개 운동 요약",
            activityDate: date, workoutDistanceMeters: distance_meters, workoutDurationSeconds: duration_seconds)
        item.previewLegacyReadContext = context
        item.previewLegacySummary = true
        return item
    }
}
enum PreviewLegacySummaryMerge {
    static func merge(legacy: [FeedItem], summaries: [FeedItem], limit: Int) -> [FeedItem] {
        var indexed: [UUID: FeedItem] = [:]
        for item in summaries { indexed[item.id] = item }
        for item in legacy { indexed[item.id] = item } // Independently RLS-authorized richer result wins.
        return Array(indexed.values.sorted {
            let a = $0.activityDate ?? $0.createdAt, b = $1.activityDate ?? $1.createdAt
            return a == b ? $0.id.uuidString.lowercased() > $1.id.uuidString.lowercased() : a > b
        }.prefix(max(0, limit)))
    }
}
