import Foundation

enum ProgressionTrendType: String, Equatable {
    case improving
    case stable
    case fluctuating
    case rebuilding
    case insufficientData

    var title: String {
        switch self {
        case .improving:
            return "조금씩 좋아지는 흐름"
        case .stable:
            return "안정적으로 이어지는 흐름"
        case .fluctuating:
            return "변화가 있는 흐름"
        case .rebuilding:
            return "다시 리듬을 쌓는 흐름"
        case .insufficientData:
            return "기록이 더 필요해요"
        }
    }

    var icon: String {
        switch self {
        case .improving:
            return SOOMIcon.trendUp
        case .stable:
            return SOOMIcon.trendFlat
        case .fluctuating:
            return SOOMIcon.waveform
        case .rebuilding:
            return SOOMIcon.sync
        case .insufficientData:
            return SOOMIcon.chartLine
        }
    }
}

struct ProgressionTrend: Equatable {
    let trendType: ProgressionTrendType
    let summary: String
    let confidence: Double?
}
