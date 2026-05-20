import Foundation

enum WorkoutWeaknessInsightType: String, Equatable {
    case pacing
    case fatigue
    case consistency
    case recovery
    case heartRate
    case endurance
    case none

    var icon: String {
        switch self {
        case .pacing:
            return SOOMIcon.trendDown
        case .fatigue:
            return SOOMIcon.waveform
        case .consistency:
            return SOOMIcon.calendarClock
        case .recovery:
            return SOOMIcon.recovery
        case .heartRate:
            return SOOMIcon.heart
        case .endurance:
            return SOOMIcon.trend
        case .none:
            return SOOMIcon.checkCircle
        }
    }
}

struct WorkoutWeaknessInsight: Equatable {
    let title: String
    let shortInsight: String
    let suggestion: String
    let insightType: WorkoutWeaknessInsightType
    let icon: String?
}
