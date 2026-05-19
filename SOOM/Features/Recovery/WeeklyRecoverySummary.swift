import Foundation

struct WeeklyRecoverySummary {
    let weekStartDate: Date
    let averageScore: Int
    let bestDayScore: Int
    let lowestDayScore: Int
    let trendDirection: WeeklyRecoveryTrendDirection
    let shortSummary: String
    let coachInsight: String
    let recommendation: String
}

enum WeeklyRecoveryTrendDirection: Equatable {
    case improving
    case declining
    case stable

    var label: String {
        switch self {
        case .improving:
            return "회복 상승"
        case .declining:
            return "피로 누적"
        case .stable:
            return "안정"
        }
    }

    var icon: String {
        switch self {
        case .improving:
            return SOOMIcon.trendUp
        case .declining:
            return SOOMIcon.trendDown
        case .stable:
            return SOOMIcon.trendFlat
        }
    }
}

extension WeeklyRecoverySummary {
    static let mockStable = WeeklyRecoverySummary(
        weekStartDate: Date(timeIntervalSince1970: 1_800_000_000 - 6 * 86_400),
        averageScore: 82,
        bestDayScore: 88,
        lowestDayScore: 76,
        trendDirection: .stable,
        shortSummary: "이번 주는 회복 흐름이 안정적이었어요.",
        coachInsight: "휴식과 가벼운 훈련이 함께 이어지며 컨디션 리듬이 크게 흔들리지 않았습니다.",
        recommendation: "다음 주도 고강도보다 회복 리듬을 먼저 확인하며 시작해보세요."
    )
}
