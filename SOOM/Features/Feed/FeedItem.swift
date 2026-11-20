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
    let authorId: UUID?
    let createdAt: Date?
    let reactionType: String
    var profile: FeedProfileDTO?

    init(
        id: UUID = UUID(),
        symbol: String,
        label: String,
        authorId: UUID? = nil,
        createdAt: Date? = nil,
        reactionType: String = "cheer",
        profile: FeedProfileDTO? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.label = label
        self.authorId = authorId
        self.createdAt = createdAt
        self.reactionType = reactionType
        self.profile = profile
    }
}

struct FeedComment: Identifiable, Equatable {
    let id: UUID
    let authorId: UUID
    let body: String
    let createdAt: Date
    let isViewerAuthor: Bool
    var profile: FeedProfileDTO? = nil
    var parentCommentID: UUID? = nil
    var isDeleted: Bool = false
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

/// Presentation only. Remote pagination must continue using activityDate/createdAt.
enum FeedDisplayOrder {
    static func date(_ item: FeedItem, localStart: Date? = nil) -> Date {
        item.verifiedOwnerStartDate ?? localStart ?? item.activityDate ?? item.createdAt
    }
    static func newestFirst(_ lhs: FeedItem, _ rhs: FeedItem) -> Bool {
        let a = date(lhs), b = date(rhs)
        return a == b ? lhs.id.uuidString.lowercased() > rhs.id.uuidString.lowercased() : a > b
    }
}

struct FeedItem: Identifiable, Equatable {
    /// Non-Codable, non-persisted, set only by account-scoped canonical projection.
    /// Never replace the remote activityDate used by cursor/receipt validation.
    var verifiedOwnerStartDate: Date? = nil
    var previewLegacyReadContext: AccountActivityReadContext? = nil
    /// Local narrowed-read provenance only; FeedItem is not Decodable/persisted.
    var previewLegacySummary = false
    /// Exact post row behind this list snapshot. It is content provenance,
    /// never permission: display still requires a fresh authenticated RLS read.
    var serverPostSnapshot: FeedPostDTO? = nil
    var sharedDetail: WorkoutSharedDetailSnapshot? = nil
    var sharedDetailContractEnabled = false
    let id: UUID
    let authorName: String
    let authorHandle: String?
    /// The `auth.users` id of the post's author. Only used to decide "is
    /// this my post" for the card's more-menu (delete) — never displayed.
    /// A local-only draft's `authorId` is meaningless (see `isLocalDraft`);
    /// ownership for a draft is decided by `isLocalDraft` alone.
    let authorId: UUID
    let avatarPath: String?
    /// True for a post that only exists as a local `FeedShareDraft` and was
    /// never posted to `feed_posts` — it has no server row, so reactions/
    /// comments/remote delete cannot target it (no `post_id` to reference).
    let activityProjection: AccountActivityFeedRow?
    let isOwnerLocalWorkout: Bool
    let isLocalDraft: Bool
    let createdAt: Date
    let itemType: FeedItemType
    var activityDate: Date? = nil
    var deviceName: String? = nil
    var workoutDistanceMeters: Double? = nil
    var workoutDurationSeconds: Double? = nil
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
    let photos: [WorkoutPhotoReference]
    let routePhoto: WorkoutPhotoReference?
    let activityContext: String
    let emotionalContext: String?
    let movementMood: String?
    let optionalShortStory: String?
    let routeMood: String?
    let recoveryCue: String?
    let locationHint: String?
    let clubContext: String?
    let contextLabels: [FeedContextLabel]
    var reactions: [FeedReaction]
    /// Whether the viewer has their own "cheer" reaction on this post —
    /// drives the action bar's toggle state. Always false for a local draft.
    var viewerHasCheered: Bool
    var viewerHasSaved: Bool
    var comments: [FeedComment]
    let microComment: String?

    init(
        id: UUID,
        authorName: String,
        authorHandle: String?,
        authorId: UUID = UUID(),
        avatarPath: String? = nil,
        isLocalDraft: Bool = false,
        isOwnerLocalWorkout: Bool = false,
        activityProjection: AccountActivityFeedRow? = nil,
        createdAt: Date,
        itemType: FeedItemType,
        visibility: ShareableWorkoutVisibility,
        cardData: FeedCardData,
        sourceWorkoutId: UUID? = nil,
        caption: String?,
        photoPlaceholders: [FeedPhotoPlaceholder] = [],
        photos: [WorkoutPhotoReference] = [],
        routePhoto: WorkoutPhotoReference? = nil,
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
        viewerHasSaved: Bool = false,
        comments: [FeedComment] = [],
        microComment: String? = nil,
        activityDate: Date? = nil,
        deviceName: String? = nil,
        workoutDistanceMeters: Double? = nil,
        workoutDurationSeconds: Double? = nil
    ) {
        self.id = id
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.authorId = authorId
        self.avatarPath = avatarPath
        self.isLocalDraft = isLocalDraft
        self.isOwnerLocalWorkout = isOwnerLocalWorkout
        self.activityProjection = activityProjection
        self.createdAt = createdAt
        self.itemType = itemType
        self.visibility = visibility
        self.cardData = cardData
        self.sourceWorkoutId = sourceWorkoutId
        self.caption = caption
        self.photoPlaceholders = photoPlaceholders
        self.photos = photos
        self.routePhoto = routePhoto
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
        self.viewerHasSaved = viewerHasSaved
        self.comments = comments
        self.microComment = microComment
        self.activityDate = activityDate
        self.deviceName = deviceName
        self.workoutDistanceMeters = workoutDistanceMeters
        self.workoutDurationSeconds = workoutDurationSeconds
    }
}


extension FeedItem {
    /// Server timestamps decide recency; neither opening the sheet nor fetching
    /// the feed changes the 12-hour badge window.
    func hasRecentComment(now: Date = Date()) -> Bool {
        comments.contains { $0.createdAt <= now && now.timeIntervalSince($0.createdAt) < 12 * 60 * 60 }
    }

    var orderedCheers: [FeedReaction] {
        var authors = Set<UUID>()
        return reactions.filter { $0.reactionType == "cheer" && $0.authorId != nil }
            .sorted {
                let left = $0.createdAt ?? .distantPast, right = $1.createdAt ?? .distantPast
                return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
            }.filter { reaction in
                guard let authorID = reaction.authorId else { return false }
                return authors.insert(authorID).inserted
            }
    }
}


/// Read-only display input from a freshly authorized feed row. This never
/// resolves sourceWorkoutId in the viewer's personal workout database.
struct WorkoutDetailSharedRecord {
    let item: FeedItem
    /// Only an explicitly injected local evaluation session creates this projection.
    var localMetricsProjection: WorkoutSharedMetricsProjection? = nil
    var nativeTelemetry: WorkoutTelemetry? = nil
    var nativeMaskedRoute: WorkoutRoute? = nil
    var nativeTimelineElapsed: Double? = nil
    var metrics: [WorkoutCardMetric] {
        var values = item.recordMetrics
        if let heartRate = item.serverPostSnapshot?.averageHeartRate, (1...300).contains(heartRate) {
            values.append(WorkoutCardMetric(label: "평균 심박", value: "\(heartRate) bpm"))
        }
        return values
    }
    var hasRouteImage: Bool { (route?.coordinates.count ?? 0) > 1 }
    private var layoutSport: WorkoutSport {
        switch item.recordWorkoutType {
        case .swimming: return .swim
        case .cycling: return .bike
        default: return .run
        }
    }
    /// Identity/tint compatibility for the existing detail renderer. Its zero
    /// fields are NOT measured values: shared rendering uses `metrics` only,
    /// never evaluates private analytics, and never persists this identity.
    var layoutIdentity: Workout {
        Workout(id: item.id, sport: layoutSport,
            title: item.recordTitle, date: item.activityDate ?? item.createdAt,
            distanceMeters: 0, duration: 0, activeCalories: 0, avgHeartRate: 0,
            maxHeartRate: 0, avgPower: nil, elevationGain: 0, cadence: nil, effort: 0,
            source: "", route: [], splits: [], samples: [], zones: [], achievements: [],
            aiSummary: "", originalWorkoutType: item.recordWorkoutType)
    }
}
