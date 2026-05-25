import Foundation

enum CourseProgressionComparisonMetric: String, Equatable {
    case pace
    case averageSpeed
    case completionTime
    case distance
    case stableRhythm
}

enum CourseProgressionPointTrend: String, Equatable {
    case improved
    case stable
    case lighter
}

struct CourseProgressionPoint: Identifiable, Equatable {
    let workoutId: UUID
    let recordedAt: Date
    let comparisonMetric: CourseProgressionComparisonMetric
    let metricValue: Double
    let trend: CourseProgressionPointTrend?
    let routeSimilarityScore: Double?

    var id: UUID {
        workoutId
    }
}
