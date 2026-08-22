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
    /// From FIT session-summary import only (batch 11) — HealthKit import doesn't
    /// populate `UnifiedWorkout.averagePowerWatts` yet. See feed-detail-migration-plan.md.
    let averagePowerWatts: Double?
    let averageCadence: Double?
    let route: ProcessedWorkoutRoute?
    let routeMissingReason: WorkoutRouteMissingReason
    let metricAvailability: [ProcessedWorkoutMetric: ProcessedWorkoutMetricState]
    let display: WorkoutDisplaySnapshot

    var hasRoute: Bool {
        route?.hasRenderableRoute == true
    }

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
    /// Distinct from `.speed` — `.speed` tracks whether a single average-speed
    /// figure exists (measured or derived from total distance/duration), while
    /// this tracks whether a per-point route timestamp series exists to plot a
    /// distance-axis speed chart. The two can disagree (e.g. manually entered
    /// distance/duration with no route → `.speed` measured, `.speedSeries` missing).
    case speedSeries
    /// Distinct from `.elevation` — `.elevation` tracks the aggregate elevation
    /// gain figure (barometer-based, present even for `.soomLocal`), while this
    /// tracks whether route points carry per-point altitude to plot a chart.
    /// `.soomLocal` never has this (Record doesn't capture GPS altitude);
    /// HealthKit/GPX/FIT/TCX imports do. See feed-detail-migration-plan.md batch 3.
    case elevationSeries
    /// Distinct from `.averageHeartRate` for the same reason as `.speedSeries` vs
    /// `.speed`. Unlike speed/elevation, this can't be judged from `route` alone —
    /// the per-timestamp HR stream is fetched asynchronously from HealthKit, outside
    /// `ProcessedWorkoutBuilder`'s synchronous scope — so callers resolve the stream
    /// first and pass `hasHeartRateSeries` into `ProcessedWorkoutBuilder.make(...)`.
    /// See feed-detail-migration-plan.md batch 4.
    case heartRateSeries
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
    let averagePowerText: String?
    let averageCadenceText: String?
    let dataQualityLabel: String
    let routeBadgeLabel: String?
}
