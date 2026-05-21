import Foundation

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
}
