import Foundation

extension StaticRouteFallbackStyle: Codable {}

enum FeedPostVisibility: String, Codable, Equatable {
    case privatePost = "private"
    case followers
    case mutual
    case publicPost = "public"

    var shareableVisibility: ShareableWorkoutVisibility {
        switch self {
        case .privatePost:
            return .privateOnly
        case .followers:
            return .followers
        case .mutual:
            return .mutual
        case .publicPost:
            return .publicFeed
        }
    }
}

extension ShareableWorkoutVisibility {
    /// New followers writes require the approved-v1 server contract. Existing
    /// legacy followers remain owner-only until an explicit visibility change.
    var feedPostVisibility: FeedPostVisibility {
        switch self {
        case .privateOnly:
            return .privatePost
        case .followers:
            return .followers
        case .mutual:
            return .mutual
        case .publicFeed:
            return .publicPost
        }
    }
}

struct FeedRouteSummaryDTO: Codable, Equatable {
    let title: String?
    let distanceText: String?
    let fallbackStyle: StaticRouteFallbackStyle?
    let routeExists: Bool
    var startedAt: Date? = nil
    var deviceName: String? = nil
    var locationName: String? = nil

    init(
        title: String? = nil,
        distanceText: String? = nil,
        fallbackStyle: StaticRouteFallbackStyle? = nil,
        routeExists: Bool = false,
        startedAt: Date? = nil,
        deviceName: String? = nil,
        locationName: String? = nil
    ) {
        self.title = title
        self.distanceText = distanceText
        self.fallbackStyle = fallbackStyle
        self.routeExists = routeExists
        self.startedAt = startedAt
        self.deviceName = deviceName
        self.locationName = locationName
    }
}

struct FeedPostDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let userId: UUID
    let sourceWorkoutId: UUID?
    let sport: UnifiedWorkoutType
    let title: String
    let body: String?
    let distanceMeters: Double?
    let durationSeconds: Int?
    let averagePaceSecondsPerKm: Int?
    let averageHeartRate: Int?
    let routeSummary: FeedRouteSummaryDTO?
    let visibility: FeedPostVisibility
    let createdAt: Date
    let updatedAt: Date?
    var activityAt: Date? = nil
    var audienceContract: Int? = nil
    var sharedDetailRevision: Int64? = nil

    init(
        id: UUID,
        userId: UUID,
        sourceWorkoutId: UUID? = nil,
        sport: UnifiedWorkoutType,
        title: String,
        body: String? = nil,
        distanceMeters: Double? = nil,
        durationSeconds: Int? = nil,
        averagePaceSecondsPerKm: Int? = nil,
        averageHeartRate: Int? = nil,
        routeSummary: FeedRouteSummaryDTO? = nil,
        visibility: FeedPostVisibility = .privatePost,
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.sourceWorkoutId = sourceWorkoutId
        self.sport = sport
        self.title = title
        self.body = body
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.averagePaceSecondsPerKm = averagePaceSecondsPerKm
        self.averageHeartRate = averageHeartRate
        self.routeSummary = routeSummary
        self.visibility = visibility
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sourceWorkoutId = "source_workout_id"
        case sport
        case title
        case body
        case distanceMeters = "distance_meters"
        case durationSeconds = "duration_seconds"
        case averagePaceSecondsPerKm = "average_pace_seconds_per_km"
        case averageHeartRate = "average_heart_rate"
        case routeSummary = "route_summary"
        case visibility
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case activityAt = "activity_at"
        case audienceContract = "audience_contract"
        case sharedDetailRevision = "shared_detail_revision"
    }
}

/// Write payload. A stable ID makes workout sharing safe to retry;
/// timestamps remain server managed.
struct FeedPostInsertDTO: Encodable, Equatable {
    var id: UUID? = nil
    let userId: UUID
    let sourceWorkoutId: UUID?
    let sport: UnifiedWorkoutType
    let title: String
    let body: String?
    let distanceMeters: Double?
    let durationSeconds: Int?
    let averagePaceSecondsPerKm: Int?
    let visibility: FeedPostVisibility
    var routeSummary: FeedRouteSummaryDTO? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sourceWorkoutId = "source_workout_id"
        case sport
        case title
        case body
        case distanceMeters = "distance_meters"
        case durationSeconds = "duration_seconds"
        case averagePaceSecondsPerKm = "average_pace_seconds_per_km"
        case visibility
        case routeSummary = "route_summary"
    }
}

struct FeedPostVisibilityUpdateDTO: Encodable, Equatable {
    let visibility: FeedPostVisibility
}

struct FeedPostBundleDTO: Equatable {
    let post: FeedPostDTO
    let media: [FeedPostMediaDTO]
    let reactions: [FeedReactionDTO]
    let comments: [FeedCommentDTO]
    let bookmarks: [FeedBookmarkDTO]
    let sharedDetail: WorkoutSharedDetailSnapshot?
    let sharedDetailContractEnabled: Bool

    init(
        post: FeedPostDTO,
        media: [FeedPostMediaDTO] = [],
        reactions: [FeedReactionDTO] = [],
        comments: [FeedCommentDTO] = [],
        bookmarks: [FeedBookmarkDTO] = [],
        sharedDetail: WorkoutSharedDetailSnapshot? = nil,
        sharedDetailContractEnabled: Bool = false
    ) {
        self.post = post
        self.media = media.sorted { $0.sortOrder < $1.sortOrder }
        self.reactions = reactions
        // Reads prioritize recent comments for bounded badge hydration; the
        // conversation always displays them in chronological order.
        self.comments = comments.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
        self.bookmarks = bookmarks
        self.sharedDetail = sharedDetail
        self.sharedDetailContractEnabled = sharedDetailContractEnabled
    }

    func makeFeedItem(authorName: String = "SOOM 사용자", authorHandle: String? = nil, avatarPath: String? = nil, currentUserId: UUID? = nil, profilesByID: [UUID: FeedProfileDTO] = [:]) -> FeedItem {
        let visibility = post.visibility == .followers && post.audienceContract != 1 ? .privateOnly : post.visibility.shareableVisibility
        let routePreview = StaticRoutePreview(
            imageURL: nil,
            bounds: nil,
            routeExists: post.routeSummary?.routeExists == true || media.contains { $0.mediaType == .route },
            fallbackStyle: post.routeSummary?.fallbackStyle ?? StaticRouteFallbackStyle(workoutType: post.sport)
        )
        let workoutCard = ShareableWorkoutCardModel(
            id: post.sourceWorkoutId ?? post.id,
            workoutType: post.sport,
            title: post.title,
            distanceText: Self.distanceText(from: post.distanceMeters, sport: post.sport, routeSummary: post.routeSummary),
            durationText: Self.durationText(from: post.durationSeconds),
            averagePaceText: FeedCardFormatting.movement(sport: post.sport, distance: post.distanceMeters, seconds: post.durationSeconds.map(Double.init), pace: post.averagePaceSecondsPerKm),
            primaryMessage: post.body ?? post.title,
            growthMessage: "자세한 흐름은 운동 상세에서 확인할 수 있어요.",
            recoveryMessage: "개인 회복 코칭은 피드에 공개하지 않아요.",
            footerText: "SOOM Feed",
            visibility: visibility,
            staticRoutePreview: routePreview
        )

        var item = FeedItem(
            id: post.id,
            authorName: authorName,
            authorHandle: authorHandle,
            authorId: post.userId,
            avatarPath: avatarPath,
            isLocalDraft: false,
            createdAt: post.createdAt,
            itemType: .workoutSession,
            visibility: visibility,
            cardData: .workoutSession(workoutCard),
            sourceWorkoutId: post.sourceWorkoutId,
            caption: post.body,
            photoPlaceholders: media.compactMap(\.photoPlaceholder),
            photos: media.compactMap(\.photoReference),
            routePhoto: media.compactMap(\.routeReference).first,
            activityContext: post.title,
            emotionalContext: post.body,
            movementMood: nil,
            optionalShortStory: post.body,
            routeMood: post.routeSummary?.title,
            recoveryCue: nil,
            locationHint: post.routeSummary?.locationName,
            clubContext: nil,
            contextLabels: [FeedContextLabel(title: visibility.title)],
            reactions: reactions.map { row in
                var reaction = row.feedReaction
                reaction.profile = profilesByID[row.userId]
                return reaction
            },
            // "cheer" is the only reaction_type the app's own action bar can
            // write today — "steady"/"night"/"wind" only ever come from
            // seeded/mock data (see FeedReactionDTO.feedReaction).
            viewerHasCheered: currentUserId != nil && reactions.contains {
                $0.userId == currentUserId && $0.reactionType == "cheer"
            },
            viewerHasSaved: currentUserId != nil && bookmarks.contains {
                $0.userId == currentUserId
            },
            comments: comments.map { row in
                var comment = row.feedComment(currentUserId: currentUserId)
                comment.profile = profilesByID[row.userId]
                return comment
            },
            microComment: comments.first?.body,
            activityDate: post.activityAt ?? post.routeSummary?.startedAt,
            deviceName: post.routeSummary?.deviceName,
            workoutDistanceMeters: post.distanceMeters,
            workoutDurationSeconds: post.durationSeconds.map(Double.init)
        )
        item.serverPostSnapshot = post
        item.sharedDetail = sharedDetail
        item.sharedDetailContractEnabled = sharedDetailContractEnabled
        return item
    }

    private static func distanceText(from meters: Double?, sport: UnifiedWorkoutType, routeSummary: FeedRouteSummaryDTO?) -> String {
        if let meters, meters.isFinite, meters >= 0 { return FeedCardFormatting.distance(meters, sport: sport) }
        if let routeDistanceText = routeSummary?.distanceText, routeDistanceText.isEmpty == false {
            return routeDistanceText
        }
        return "—"
    }

    private static func durationText(from seconds: Int?) -> String {
        seconds.map { FeedCardFormatting.duration(Double($0)) } ?? "—"
    }
}


extension FeedPostBundleDTO {
    /// Page hydration includes only three cheer previews. Full participant
    /// profiles are fetched on demand when the people sheet opens.
    var previewProfileIDs: [UUID] {
        [post.userId] + reactions.filter { $0.reactionType == "cheer" }
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
            .prefix(3).map(\.userId)
    }
}
