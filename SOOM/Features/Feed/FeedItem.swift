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

struct FeedComment: Identifiable, Equatable {
    let id: UUID
    let authorId: UUID
    let body: String
    let createdAt: Date
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
    /// The `auth.users` id of the post's author. Only used to decide "is
    /// this my post" for the card's more-menu (delete) — never displayed.
    /// A local-only draft's `authorId` is meaningless (see `isLocalDraft`);
    /// ownership for a draft is decided by `isLocalDraft` alone.
    let authorId: UUID
    /// True for a post that only exists as a local `FeedShareDraft` and was
    /// never posted to `feed_posts` — it has no server row, so reactions/
    /// comments/remote delete cannot target it (no `post_id` to reference).
    let isLocalDraft: Bool
    let createdAt: Date
    let itemType: FeedItemType
    let visibility: ShareableWorkoutVisibility
    let cardData: FeedCardData
    /// The local `UnifiedWorkout.id` this post was shared from, if any. Used
    /// only to check whether *this device* still has the full local record —
    /// never trusted as an identity/ownership claim on its own. Feed never
    /// stores other users' raw workouts locally (Q1 invariant), so a hit
    /// here can only ever be the viewer's own workout. See
    /// `FeedItemDetailDestination` in FeedItemDetailView.swift.
    let sourceWorkoutId: UUID?
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
    /// Whether the viewer has their own "cheer" reaction on this post —
    /// drives the action bar's toggle state. Always false for a local draft.
    var viewerHasCheered: Bool
    let comments: [FeedComment]
    let microComment: String?

    init(
        id: UUID,
        authorName: String,
        authorHandle: String?,
        authorId: UUID = UUID(),
        isLocalDraft: Bool = false,
        createdAt: Date,
        itemType: FeedItemType,
        visibility: ShareableWorkoutVisibility,
        cardData: FeedCardData,
        sourceWorkoutId: UUID? = nil,
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
        viewerHasCheered: Bool = false,
        comments: [FeedComment] = [],
        microComment: String? = nil
    ) {
        self.id = id
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.authorId = authorId
        self.isLocalDraft = isLocalDraft
        self.createdAt = createdAt
        self.itemType = itemType
        self.visibility = visibility
        self.cardData = cardData
        self.sourceWorkoutId = sourceWorkoutId
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
        self.viewerHasCheered = viewerHasCheered
        self.comments = comments
        self.microComment = microComment
    }
}
