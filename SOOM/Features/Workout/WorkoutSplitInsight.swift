import Foundation

struct WorkoutSplitInsight: Equatable {
    let title: String
    let summary: String
    let splitType: WorkoutSplitType
    let trend: WorkoutSplitTrend
    let metricRows: [WorkoutSplitMetricRow]

    static let insufficientData = WorkoutSplitInsight(
        title: "운동 흐름을 더 모아볼게요",
        summary: "비슷한 기록이 조금 더 쌓이면 전반과 후반의 리듬을 함께 살펴볼 수 있어요.",
        splitType: .insufficientData,
        trend: .insufficientData,
        metricRows: []
    )
}

enum WorkoutSplitType: Equatable {
    case negativeSplit
    case positiveSplit
    case stablePace
    case stableSpeed
    case fatigueDrop
    case insufficientData
}

enum WorkoutSplitTrend: Equatable {
    case improving
    case stable
    case lighter
    case insufficientData
}

struct WorkoutSplitMetricRow: Identifiable, Equatable {
    let title: String
    let valueText: String
    let detailText: String

    var id: String {
        "\(title)-\(valueText)-\(detailText)"
    }
}
