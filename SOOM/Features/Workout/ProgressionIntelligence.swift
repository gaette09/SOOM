import Foundation

struct ProgressionIntelligenceMetricRow: Identifiable, Equatable {
    let title: String
    let valueText: String
    let comparisonText: String

    var id: String { "\(title)-\(valueText)-\(comparisonText)" }
}

struct ProgressionIntelligence: Equatable {
    let period: ProgressionPeriod
    let trend: ProgressionTrend
    let metricRows: [ProgressionIntelligenceMetricRow]
    let insightSummary: String

    static func insufficientData(period: ProgressionPeriod) -> ProgressionIntelligence {
        ProgressionIntelligence(
            period: period,
            trend: ProgressionTrend(
                trendType: .insufficientData,
                summary: "기록이 더 쌓이면 장기 운동 흐름을 함께 정리해드릴게요.",
                confidence: nil
            ),
            metricRows: [],
            insightSummary: "최근 운동 기록이 아직 부족해요. 몇 번의 운동이 더 쌓이면 페이스, 속도, 리듬 변화를 차분히 보여드릴게요."
        )
    }
}
