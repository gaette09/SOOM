import Foundation

enum WorkoutGrowthImprovementType: String, Equatable {
    case consistency
    case endurance
    case pace
    case recovery
    case effort
    case streak
    case none

    var title: String {
        switch self {
        case .consistency:
            return "꾸준함"
        case .endurance:
            return "지구력"
        case .pace:
            return "페이스"
        case .recovery:
            return "회복 리듬"
        case .effort:
            return "운동 집중도"
        case .streak:
            return "연속성"
        case .none:
            return "기록 확인"
        }
    }

    var icon: String {
        switch self {
        case .consistency:
            return SOOMIcon.calendarClock
        case .endurance:
            return SOOMIcon.trendUp
        case .pace:
            return SOOMIcon.bolt
        case .recovery:
            return SOOMIcon.recovery
        case .effort:
            return SOOMIcon.chartBar
        case .streak:
            return SOOMIcon.sparkles
        case .none:
            return SOOMIcon.checkCircle
        }
    }
}

struct WorkoutGrowthSummary: Equatable {
    let workoutId: UUID
    let title: String
    let shortSummary: String
    let improvementType: WorkoutGrowthImprovementType
    let comparisonText: String
    let motivationText: String
    let insight: String?
}
