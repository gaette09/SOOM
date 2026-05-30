import Foundation

extension StaticRouteFallbackStyle: Codable {}

enum FeedPostVisibility: String, Codable, Equatable {
    case privatePost = "private"
    case followers
    case publicPost = "public"

    var shareableVisibility: ShareableWorkoutVisibility {
        switch self {
        case .privatePost:
            return .privateOnly
        case .followers:
            return .followers
        case .publicPost:
            return .publicFeed
        }
    }
}

struct FeedRouteSummaryDTO: Codable, Equatable {
    let title: String?
    let distanceText: String?
    let fallbackStyle: StaticRouteFallbackStyle?
    let routeExists: Bool

    init(
        title: String? = nil,
        distanceText: String? = nil,
        fallbackStyle: StaticRouteFallbackStyle? = nil,
        routeExists: Bool = false
    ) {
        self.title = title
        self.distanceText = distanceText
        self.fallbackStyle = fallbackStyle
        self.routeExists = routeExists
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
    }
}

struct FeedPostBundleDTO: Equatable {
    let post: FeedPostDTO
    let media: [FeedPostMediaDTO]
    let reactions: [FeedReactionDTO]
    let comments: [FeedCommentDTO]

    init(
        post: FeedPostDTO,
        media: [FeedPostMediaDTO] = [],
        reactions: [FeedReactionDTO] = [],
        comments: [FeedCommentDTO] = []
    ) {
        self.post = post
        self.media = media.sorted { $0.sortOrder < $1.sortOrder }
        self.reactions = reactions
        self.comments = comments
    }

    func makeFeedItem(authorName: String = "SOOM 사용자", authorHandle: String? = nil) -> FeedItem {
        let visibility = post.visibility.shareableVisibility
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
            distanceText: Self.distanceText(from: post.distanceMeters, routeSummary: post.routeSummary),
            durationText: Self.durationText(from: post.durationSeconds),
            primaryMessage: post.body ?? post.title,
            growthMessage: "자세한 흐름은 운동 상세에서 확인할 수 있어요.",
            recoveryMessage: "개인 회복 코칭은 피드에 공개하지 않아요.",
            footerText: "SOOM Feed",
            visibility: visibility,
            staticRoutePreview: routePreview
        )

        return FeedItem(
            id: post.id,
            authorName: authorName,
            authorHandle: authorHandle,
            createdAt: post.createdAt,
            itemType: .workoutSession,
            visibility: visibility,
            cardData: .workoutSession(workoutCard),
            caption: post.body,
            photoPlaceholders: media.compactMap(\.photoPlaceholder),
            activityContext: post.title,
            emotionalContext: post.body,
            movementMood: nil,
            optionalShortStory: post.body,
            routeMood: post.routeSummary?.title,
            recoveryCue: nil,
            locationHint: nil,
            clubContext: nil,
            contextLabels: [FeedContextLabel(title: visibility.title)],
            reactions: reactions.map(\.feedReaction),
            microComment: comments.first?.body
        )
    }

    private static func distanceText(from meters: Double?, routeSummary: FeedRouteSummaryDTO?) -> String {
        if let routeDistanceText = routeSummary?.distanceText, routeDistanceText.isEmpty == false {
            return routeDistanceText
        }
        guard let meters, meters > 0 else {
            return "거리 기록"
        }
        let kilometers = meters / 1_000
        return String(format: "%.2f km", kilometers)
    }

    private static func durationText(from seconds: Int?) -> String {
        guard let seconds, seconds > 0 else {
            return "시간 기록"
        }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 {
            return "\(hours)시간 \(minutes)분"
        }
        return "\(minutes)분"
    }
}
