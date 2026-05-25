import Foundation

struct ClimbInsight: Equatable {
    let title: String
    let summary: String
    let climbType: ClimbInsightType
    let metricRows: [ClimbInsightMetricRow]
    let trend: ClimbInsightTrend

    var isVisible: Bool {
        climbType != .insufficientData
    }

    static let insufficientData = ClimbInsight(
        title: "오르막 흐름을 더 모아볼게요",
        summary: "상승고도나 경로 데이터가 충분한 운동에서 지형 리듬을 함께 살펴볼 수 있어요.",
        climbType: .insufficientData,
        metricRows: [],
        trend: .insufficientData
    )
}

enum ClimbInsightType: Equatable {
    case steadyClimb
    case strongFinish
    case elevationFatigue
    case rollingTerrain
    case insufficientData
}

enum ClimbInsightTrend: Equatable {
    case improving
    case stable
    case lighter
    case insufficientData
}

struct ClimbInsightMetricRow: Identifiable, Equatable {
    let title: String
    let valueText: String
    let detailText: String

    var id: String {
        "\(title)-\(valueText)-\(detailText)"
    }
}
