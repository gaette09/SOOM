import Foundation

enum WorkoutComparisonInsightTone: String, Equatable {
    case improved
    case steady
    case lighter
    case insufficientData
}

enum WorkoutComparisonType: String, Equatable {
    case sameRoute
    case similarDistance
    case recentWorkout
    case insufficientData
}

struct WorkoutComparisonMetricRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let valueText: String
    let detailText: String

    init(
        id: UUID = UUID(),
        title: String,
        valueText: String,
        detailText: String
    ) {
        self.id = id
        self.title = title
        self.valueText = valueText
        self.detailText = detailText
    }
}

struct WorkoutComparisonInsight: Equatable {
    let title: String
    let summary: String
    let metricRows: [WorkoutComparisonMetricRow]
    let tone: WorkoutComparisonInsightTone
    let comparisonType: WorkoutComparisonType

    static let insufficientData = WorkoutComparisonInsight(
        title: "이전 비슷한 운동과 비교",
        summary: "비슷한 기록이 쌓이면 오늘 운동의 변화를 함께 비교해볼게요.",
        metricRows: [],
        tone: .insufficientData,
        comparisonType: .insufficientData
    )
}
