import Foundation

extension FeedPhotoTone: Codable {}

enum FeedPostMediaType: String, Codable, Equatable {
    case route
    case photo
}

struct FeedMediaPreviewPayloadDTO: Codable, Equatable {
    let title: String?
    let tone: FeedPhotoTone?
    let routeLabel: String?
    let distanceText: String?

    init(
        title: String? = nil,
        tone: FeedPhotoTone? = nil,
        routeLabel: String? = nil,
        distanceText: String? = nil
    ) {
        self.title = title
        self.tone = tone
        self.routeLabel = routeLabel
        self.distanceText = distanceText
    }
}

struct FeedPostMediaDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let postId: UUID
    let mediaType: FeedPostMediaType
    let storagePath: String?
    let previewPayload: FeedMediaPreviewPayloadDTO?
    let sortOrder: Int

    init(
        id: UUID,
        postId: UUID,
        mediaType: FeedPostMediaType,
        storagePath: String? = nil,
        previewPayload: FeedMediaPreviewPayloadDTO? = nil,
        sortOrder: Int
    ) {
        self.id = id
        self.postId = postId
        self.mediaType = mediaType
        self.storagePath = storagePath
        self.previewPayload = previewPayload
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case mediaType = "media_type"
        case storagePath = "storage_path"
        case previewPayload = "preview_payload"
        case sortOrder = "sort_order"
    }

    var photoPlaceholder: FeedPhotoPlaceholder? {
        guard mediaType == .photo else {
            return nil
        }
        return FeedPhotoPlaceholder(
            title: previewPayload?.title ?? "운동 사진",
            tone: previewPayload?.tone ?? .city
        )
    }

    var photoReference: WorkoutPhotoReference? {
        guard mediaType == .photo, let storagePath, WorkoutPhotoPolicy.validPath(storagePath) else { return nil }
        return WorkoutPhotoReference(id: id, storagePath: storagePath)
    }
    var routeReference: WorkoutPhotoReference? {
        guard mediaType == .route, let storagePath, WorkoutPhotoPolicy.validPath(storagePath) else { return nil }
        return WorkoutPhotoReference(id: id, storagePath: storagePath)
    }
}

struct FeedReactionDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let postId: UUID
    let userId: UUID
    let reactionType: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
        case reactionType = "reaction_type"
        case createdAt = "created_at"
    }

    var feedReaction: FeedReaction {
        let symbol: String
        let label: String

        switch reactionType {
        case "cheer":
            symbol = "👏"
            label = "응원"
        case "steady":
            symbol = "🫶"
            label = "차분한 리듬"
        case "night":
            symbol = "🌙"
            label = "좋은 흐름"
        case "wind":
            symbol = "💨"
            label = "부드러운 흐름"
        default:
            symbol = "👏"
            label = "응원"
        }

        return FeedReaction(id: id, symbol: symbol, label: label, authorId: userId, createdAt: createdAt, reactionType: reactionType)
    }
}

/// Insert-only payload for `feed_reactions` — mirrors `FeedPostInsertDTO`'s
/// reasoning: `id`/`created_at` are server-generated.
struct FeedReactionInsertDTO: Encodable, Equatable {
    let postId: UUID
    let userId: UUID
    let reactionType: String

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case userId = "user_id"
        case reactionType = "reaction_type"
    }
}

struct FeedBookmarkDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let postId: UUID
    let userId: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

/// Insert-only payload for `feed_bookmarks`.
struct FeedBookmarkInsertDTO: Encodable, Equatable {
    let postId: UUID
    let userId: UUID

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case userId = "user_id"
    }
}

struct FeedCommentDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let postId: UUID
    let userId: UUID
    let body: String
    let createdAt: Date
    var parentCommentID: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
        case body
        case createdAt = "created_at"
        case parentCommentID = "parent_comment_id"
    }

    func feedComment(currentUserId: UUID?) -> FeedComment {
        FeedComment(
            id: id,
            authorId: userId,
            body: body,
            createdAt: createdAt,
            isViewerAuthor: userId == currentUserId,
            parentCommentID: parentCommentID
        )
    }
}

/// Insert-only payload for `feed_comments`.
struct FeedCommentInsertDTO: Encodable, Equatable {
    let postId: UUID
    let userId: UUID
    let body: String

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case userId = "user_id"
        case body
    }
}

/// Separate candidate reply projection: tombstones deliberately omit author/body.
/// Do not make the legacy feed DTO nullable or synthesize a public identity.
struct FeedReplyThreadDTO: Decodable {
    let id: UUID
    let parentCommentID: UUID?
    let userID: UUID?
    let body: String?
    let isDeleted: Bool
    let createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id, body
        case parentCommentID = "parent_comment_id", userID = "user_id", isDeleted = "is_deleted", createdAt = "created_at"
    }
    func comment(viewerID: UUID?) -> FeedComment? {
        if isDeleted {
            // Internal placeholder only; deleted rows never render a profile action.
            return FeedComment(id: id, authorId: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                body: "삭제된 댓글입니다", createdAt: createdAt, isViewerAuthor: false,
                parentCommentID: parentCommentID, isDeleted: true)
        }
        guard let userID, let body else { return nil }
        return FeedComment(id: id, authorId: userID, body: body, createdAt: createdAt,
            isViewerAuthor: userID == viewerID, parentCommentID: parentCommentID)
    }
}
