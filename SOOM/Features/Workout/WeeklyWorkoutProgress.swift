import Foundation

enum WeeklyWorkoutTrendType: String, Equatable {
    case improving
    case steady
    case lighterWeek
    case insufficientData

    var title: String {
        switch self {
        case .improving:
            return "좋아지는 흐름"
        case .steady:
            return "꾸준한 흐름"
        case .lighterWeek:
            return "가벼운 주간"
        case .insufficientData:
            return "기록 준비"
        }
    }

    var icon: String {
        switch self {
        case .improving:
            return SOOMIcon.trendUp
        case .steady:
            return SOOMIcon.trendFlat
        case .lighterWeek:
            return SOOMIcon.moon
        case .insufficientData:
            return SOOMIcon.calendarClock
        }
    }
}

struct WeeklyWorkoutProgress: Equatable {
    let weekStartDate: Date
    let workoutCount: Int
    let totalDistanceKm: Double
    let totalDurationMinutes: Int
    let averagePaceOrSpeedText: String
    let progressSummary: String
    let motivationText: String
    let trendType: WeeklyWorkoutTrendType
}
