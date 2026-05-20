import Foundation

enum PersonalRecordMetricType: String, Equatable {
    case longestDistance
    case longestDuration
    case bestPace
    case bestAverageSpeed
    case mostElevation
    case weeklyConsistency

    var title: String {
        switch self {
        case .longestDistance:
            return "가장 멀리 움직인 날"
        case .longestDuration:
            return "가장 오래 움직인 날"
        case .bestPace:
            return "가장 안정적인 페이스"
        case .bestAverageSpeed:
            return "가장 빠른 평균 속도"
        case .mostElevation:
            return "가장 많은 상승 고도"
        case .weeklyConsistency:
            return "가장 꾸준한 주간 리듬"
        }
    }

    var icon: String {
        switch self {
        case .longestDistance:
            return SOOMIcon.routeStart
        case .longestDuration:
            return SOOMIcon.calendarClock
        case .bestPace, .bestAverageSpeed:
            return SOOMIcon.bolt
        case .mostElevation:
            return SOOMIcon.trendUp
        case .weeklyConsistency:
            return SOOMIcon.checkCircle
        }
    }
}

struct PersonalRecord: Identifiable, Equatable {
    var id: String {
        "\(workoutType.rawValue)-\(metricType.rawValue)-\(achievedAt.timeIntervalSince1970)"
    }

    let workoutType: UnifiedWorkoutType
    let metricType: PersonalRecordMetricType
    let value: String
    let achievedAt: Date
    let comparisonText: String
    let motivationText: String
}
