import Foundation

enum ShareableWorkoutVisibility: String, Equatable {
    case privateOnly
    case followers
    case publicFeed

    var title: String {
        switch self {
        case .privateOnly:
            return "나만 보기"
        case .followers:
            return "팔로워"
        case .publicFeed:
            return "공개 피드"
        }
    }
}

struct ShareableWorkoutCardModel: Identifiable, Equatable {
    let id: UUID
    let workoutType: UnifiedWorkoutType
    let title: String
    let distanceText: String
    let durationText: String
    let primaryMessage: String
    let growthMessage: String
    let recoveryMessage: String
    let footerText: String
    let visibility: ShareableWorkoutVisibility
    let staticRoutePreview: StaticRoutePreview?

    init(
        id: UUID,
        workoutType: UnifiedWorkoutType,
        title: String,
        distanceText: String,
        durationText: String,
        primaryMessage: String,
        growthMessage: String,
        recoveryMessage: String,
        footerText: String,
        visibility: ShareableWorkoutVisibility,
        staticRoutePreview: StaticRoutePreview? = nil
    ) {
        self.id = id
        self.workoutType = workoutType
        self.title = title
        self.distanceText = distanceText
        self.durationText = durationText
        self.primaryMessage = primaryMessage
        self.growthMessage = growthMessage
        self.recoveryMessage = recoveryMessage
        self.footerText = footerText
        self.visibility = visibility
        self.staticRoutePreview = staticRoutePreview
    }
}
