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

        return FeedReaction(id: id, symbol: symbol, label: label)
    }
}

struct FeedCommentDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let postId: UUID
    let userId: UUID
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
        case body
        case createdAt = "created_at"
    }
}
