import Foundation

enum FourWeekWorkoutTrendType: String, Equatable {
    case improving
    case steady
    case lighter
    case insufficientData

    var title: String {
        switch self {
        case .improving:
            return "좋아지는 4주 흐름"
        case .steady:
            return "안정적인 4주 흐름"
        case .lighter:
            return "가벼워진 4주 흐름"
        case .insufficientData:
            return "흐름 준비 중"
        }
    }

    var icon: String {
        switch self {
        case .improving:
            return SOOMIcon.trendUp
        case .steady:
            return SOOMIcon.trendFlat
        case .lighter:
            return SOOMIcon.moon
        case .insufficientData:
            return SOOMIcon.calendarClock
        }
    }
}

struct WeeklyWorkoutTrendPoint: Identifiable, Equatable {
    var id: Date { weekStartDate }

    let weekStartDate: Date
    let workoutCount: Int
    let totalDistanceKm: Double
    let totalDurationMinutes: Int
}

struct FourWeekWorkoutTrend: Equatable {
    let weeks: [WeeklyWorkoutTrendPoint]
    let trendType: FourWeekWorkoutTrendType
    let summaryText: String
    let motivationText: String
}
