import Foundation

enum FeedPhotoTone: String, Equatable {
    case morning
    case city
    case trail
    case water
}

struct FeedPhotoPlaceholder: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let tone: FeedPhotoTone

    init(
        id: UUID = UUID(),
        title: String,
        tone: FeedPhotoTone
    ) {
        self.id = id
        self.title = title
        self.tone = tone
    }
}

struct FeedReaction: Identifiable, Equatable {
    let id: UUID
    let symbol: String
    let label: String

    init(
        id: UUID = UUID(),
        symbol: String,
        label: String
    ) {
        self.id = id
        self.symbol = symbol
        self.label = label
    }
}

struct FeedContextLabel: Identifiable, Equatable {
    let id: UUID
    let title: String
    let icon: String?

    init(
        id: UUID = UUID(),
        title: String,
        icon: String? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
    }
}

enum FeedItemType: String, Equatable {
    case workoutSession
    case weeklyProgress
    case recoveryFriendly
    case consistency

    var title: String {
        switch self {
        case .workoutSession:
            return "운동 기록"
        case .weeklyProgress:
            return "주간 성장"
        case .recoveryFriendly:
            return "회복 친화 운동"
        case .consistency:
            return "꾸준함"
        }
    }
}

enum FeedCardData: Equatable {
    case workoutSession(ShareableWorkoutCardModel)
    case weeklyProgress(ShareableWeeklyProgressCardModel)
}

struct FeedItem: Identifiable, Equatable {
    let id: UUID
    let authorName: String
    let authorHandle: String?
    let createdAt: Date
    let itemType: FeedItemType
    let visibility: ShareableWorkoutVisibility
    let cardData: FeedCardData
    let caption: String?
    let photoPlaceholders: [FeedPhotoPlaceholder]
    let activityContext: String
    let emotionalContext: String?
    let movementMood: String?
    let optionalShortStory: String?
    let routeMood: String?
    let recoveryCue: String?
    let locationHint: String?
    let clubContext: String?
    let contextLabels: [FeedContextLabel]
    let reactions: [FeedReaction]
    let microComment: String?

    init(
        id: UUID,
        authorName: String,
        authorHandle: String?,
        createdAt: Date,
        itemType: FeedItemType,
        visibility: ShareableWorkoutVisibility,
        cardData: FeedCardData,
        caption: String?,
        photoPlaceholders: [FeedPhotoPlaceholder] = [],
        activityContext: String,
        emotionalContext: String? = nil,
        movementMood: String? = nil,
        optionalShortStory: String? = nil,
        routeMood: String? = nil,
        recoveryCue: String? = nil,
        locationHint: String? = nil,
        clubContext: String? = nil,
        contextLabels: [FeedContextLabel] = [],
        reactions: [FeedReaction] = [],
        microComment: String? = nil
    ) {
        self.id = id
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.createdAt = createdAt
        self.itemType = itemType
        self.visibility = visibility
        self.cardData = cardData
        self.caption = caption
        self.photoPlaceholders = photoPlaceholders
        self.activityContext = activityContext
        self.emotionalContext = emotionalContext
        self.movementMood = movementMood
        self.optionalShortStory = optionalShortStory
        self.routeMood = routeMood
        self.recoveryCue = recoveryCue
        self.locationHint = locationHint
        self.clubContext = clubContext
        self.contextLabels = contextLabels
        self.reactions = reactions
        self.microComment = microComment
    }
}
