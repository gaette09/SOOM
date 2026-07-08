import Foundation

struct ProcessedWorkout: Identifiable, Equatable {
    let id: UUID
    let externalId: String?
    let source: UnifiedDataSource
    let workoutType: UnifiedWorkoutType
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: TimeInterval
    let isExcludedFromAnalysis: Bool
    let dataQuality: UnifiedDataQuality
    let distanceMeters: Double?
    let averageSpeedMetersPerSecond: Double?
    let averagePaceSecondsPerKilometer: Double?
    let activeEnergyKcal: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let elevationGainMeters: Double?
    let route: ProcessedWorkoutRoute?
    let metricAvailability: [ProcessedWorkoutMetric: ProcessedWorkoutMetricState]
    let display: WorkoutDisplaySnapshot

    var durationMinutes: Int {
        max(Int((durationSeconds / 60).rounded()), 0)
    }

    var distanceKilometers: Double? {
        distanceMeters.map { $0 / 1_000 }
    }
}

struct ProcessedWorkoutRoute: Equatable {
    let workoutId: UUID
    let source: UnifiedDataSource
    let coordinates: [WorkoutRouteCoordinate]
    let coordinateCount: Int
    let totalDistanceMeters: Double
    let totalElevationGainMeters: Double?
    let bounds: WorkoutRouteBounds?
    let hasRenderableRoute: Bool
    let courseIdentity: String?
}

enum ProcessedWorkoutMetric: String, Hashable {
    case distance
    case duration
    case pace
    case speed
    case elevation
    case calories
    case averageHeartRate
    case maxHeartRate
    case power
    case cadence
    case route
    case splits
    case zones
}

enum ProcessedWorkoutMetricState: String, Equatable {
    case measured
    case derived
    case estimated
    case missing
    case unsupported
}

struct WorkoutDisplaySnapshot: Equatable {
    let sportTitle: String
    let sportIconName: String
    let sourceTitle: String
    let dateText: String
    let timeText: String
    let durationText: String
    let distanceText: String
    let primaryMetricLabel: String
    let primaryMetricValue: String
    let speedText: String
    let paceText: String
    let elevationText: String
    let caloriesText: String
    let averageHeartRateText: String
    let maxHeartRateText: String
    let dataQualityLabel: String
    let routeBadgeLabel: String?
}
