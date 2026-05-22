import Foundation

enum WorkoutGrowthMetricType: String, Equatable {
    case distance
    case duration
    case pace
    case speed
    case consistency
    case elevation
    case heartRateEfficiency
}

enum WorkoutGrowthMetricTrend: String, Equatable {
    case improved
    case steady
    case lighter
    case insufficientData
}

struct WorkoutGrowthMetric: Identifiable, Equatable {
    var id: WorkoutGrowthMetricType { metricType }

    let title: String
    let valueText: String
    let comparisonText: String
    let trend: WorkoutGrowthMetricTrend
    let metricType: WorkoutGrowthMetricType
}
