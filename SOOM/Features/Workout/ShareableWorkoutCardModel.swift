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
}
