import Foundation

enum FeedShareDraftVisibility: String, Codable, Equatable {
    case draft
    case privateOnly

    var shareableVisibility: ShareableWorkoutVisibility {
        .privateOnly
    }
}

struct FeedShareDraftRoutePreviewPayload: Codable, Equatable {
    let routeExists: Bool
    let distanceText: String?
    let fallbackStyleRawValue: String

    var fallbackStyle: StaticRouteFallbackStyle {
        StaticRouteFallbackStyle(rawValue: fallbackStyleRawValue) ?? .generic
    }
}

struct FeedShareDraft: Identifiable, Codable, Equatable {
    let id: UUID
    let sourceWorkoutId: UUID
    let sport: UnifiedWorkoutType
    let title: String
    let body: String
    let distanceMeters: Double?
    let durationSeconds: TimeInterval
    let averagePaceSecondsPerKm: Int?
    let routePreviewPayload: FeedShareDraftRoutePreviewPayload?
    let photoPlaceholders: [FeedPhotoPlaceholder]
    let tags: [String]
    let visibility: FeedShareDraftVisibility
    let createdAt: Date

    func makeFeedItem(
        authorName: String = "나",
        authorHandle: String? = "@draft"
    ) -> FeedItem {
        let routePreview = StaticRoutePreview(
            imageURL: nil,
            bounds: nil,
            routeExists: routePreviewPayload?.routeExists ?? false,
            fallbackStyle: routePreviewPayload?.fallbackStyle ?? StaticRouteFallbackStyle(workoutType: sport)
        )
        let card = ShareableWorkoutCardModel(
            id: sourceWorkoutId,
            workoutType: sport,
            title: title,
            distanceText: Self.distanceText(distanceMeters),
            durationText: Self.durationText(durationSeconds),
            primaryMessage: body,
            growthMessage: "공개 전 초안으로 보관 중이에요.",
            recoveryMessage: "개인 회복 코칭은 피드 초안에 포함하지 않아요.",
            footerText: "SOOM Feed Draft",
            visibility: visibility.shareableVisibility,
            staticRoutePreview: routePreview
        )
        let labels = [FeedContextLabel(title: "초안", icon: SOOMIcon.edit)]
            + tags.prefix(1).map { FeedContextLabel(title: $0, icon: nil) }

        return FeedItem(
            id: id,
            authorName: authorName,
            authorHandle: authorHandle,
            createdAt: createdAt,
            itemType: .workoutSession,
            visibility: visibility.shareableVisibility,
            cardData: .workoutSession(card),
            caption: body,
            photoPlaceholders: photoPlaceholders,
            activityContext: title,
            emotionalContext: body,
            movementMood: tags.first,
            optionalShortStory: body,
            routeMood: routePreviewPayload?.distanceText,
            recoveryCue: nil,
            locationHint: nil,
            clubContext: nil,
            contextLabels: labels,
            reactions: [],
            microComment: nil
        )
    }

    private static func distanceText(_ meters: Double?) -> String {
        guard let meters, meters > 0 else {
            return "거리 준비 중"
        }

        return String(format: "%.1f km", meters / 1_000)
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(Int(seconds.rounded()) / 60, 1)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)시간 \(minutes)분"
        }

        return "\(minutes)분"
    }
}
