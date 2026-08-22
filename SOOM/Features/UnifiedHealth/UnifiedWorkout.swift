import Foundation

struct UnifiedWorkout: Identifiable, Equatable, Codable {
    let id: UUID
    let externalId: String?
    let source: UnifiedDataSource
    let workoutType: UnifiedWorkoutType
    let startDate: Date
    let endDate: Date
    let durationSeconds: TimeInterval
    let distanceMeters: Double?
    let activeEnergyKcal: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let averageSpeedMetersPerSecond: Double?
    let elevationGainMeters: Double?
    /// From FIT session-summary import only today (batch 11) — HealthKit import
    /// doesn't populate this yet. See feed-detail-migration-plan.md.
    let averagePowerWatts: Double?
    let averageCadence: Double?
    let routeMissingReason: WorkoutRouteMissingReason
    let dataQuality: UnifiedDataQuality
    let isExcludedFromAnalysis: Bool
    let createdAt: Date
    let updatedAt: Date
    /// Free-text names only (batch 8) — no `profiles`/`follows` lookup.
    let companionNames: [String]

    init(
        id: UUID,
        externalId: String?,
        source: UnifiedDataSource,
        workoutType: UnifiedWorkoutType,
        startDate: Date,
        endDate: Date,
        durationSeconds: TimeInterval,
        distanceMeters: Double?,
        activeEnergyKcal: Double?,
        averageHeartRate: Double?,
        maxHeartRate: Double?,
        averageSpeedMetersPerSecond: Double?,
        elevationGainMeters: Double?,
        averagePowerWatts: Double? = nil,
        averageCadence: Double? = nil,
        routeMissingReason: WorkoutRouteMissingReason = .none,
        dataQuality: UnifiedDataQuality,
        isExcludedFromAnalysis: Bool = false,
        createdAt: Date,
        updatedAt: Date,
        companionNames: [String] = []
    ) {
        self.id = id
        self.externalId = externalId
        self.source = source
        self.workoutType = workoutType
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.activeEnergyKcal = activeEnergyKcal
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.averageSpeedMetersPerSecond = averageSpeedMetersPerSecond
        self.elevationGainMeters = elevationGainMeters
        self.averagePowerWatts = averagePowerWatts
        self.averageCadence = averageCadence
        self.routeMissingReason = routeMissingReason
        self.dataQuality = dataQuality
        self.isExcludedFromAnalysis = isExcludedFromAnalysis
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.companionNames = companionNames
    }
}

enum WorkoutRouteMissingReason: String, Codable, Equatable {
    case none
    case notApplicable
    case healthKitRouteUnavailable
    case routeFetchFailed
    case routePersistenceFailed
    case externalSourceRouteNotShared
    case userSkippedRouteAttachment
    case unknown

    var isActionableForRouteAttachment: Bool {
        switch self {
        case .healthKitRouteUnavailable, .externalSourceRouteNotShared, .routeFetchFailed, .routePersistenceFailed:
            return true
        case .none, .notApplicable, .userSkippedRouteAttachment, .unknown:
            return false
        }
    }
}

extension UnifiedWorkout {
    func withRouteMissingReason(_ reason: WorkoutRouteMissingReason, updatedAt: Date) -> UnifiedWorkout {
        UnifiedWorkout(
            id: id,
            externalId: externalId,
            source: source,
            workoutType: workoutType,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKcal: activeEnergyKcal,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            averageSpeedMetersPerSecond: averageSpeedMetersPerSecond,
            elevationGainMeters: elevationGainMeters,
            averagePowerWatts: averagePowerWatts,
            averageCadence: averageCadence,
            routeMissingReason: reason,
            dataQuality: dataQuality,
            isExcludedFromAnalysis: isExcludedFromAnalysis,
            createdAt: createdAt,
            updatedAt: updatedAt,
            companionNames: companionNames
        )
    }

    /// Merges a parsed FIT file's session summary onto this workout. Distance/speed
    /// follow "measured > derived" — only backfilled when this workout doesn't
    /// already have a value, since a HealthKit-sourced workout's own measured
    /// distance/speed is not necessarily less accurate than what a re-parsed FIT
    /// file recomputes. Power/cadence have no other producer today (HealthKit
    /// import doesn't populate them), so they're always taken from the FIT summary
    /// when present. Previously `FITRouteAttachmentService` computed this summary
    /// and then discarded it entirely — found while investigating Power Curve
    /// feasibility (feed-detail-migration-plan.md).
    func withFITSummaryMerged(_ summary: FITWorkoutSummary, updatedAt: Date) -> UnifiedWorkout {
        UnifiedWorkout(
            id: id,
            externalId: externalId,
            source: source,
            workoutType: workoutType,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters ?? summary.distanceMeters,
            activeEnergyKcal: activeEnergyKcal,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            averageSpeedMetersPerSecond: averageSpeedMetersPerSecond ?? summary.averageSpeedMetersPerSecond,
            elevationGainMeters: elevationGainMeters,
            averagePowerWatts: summary.averagePower ?? averagePowerWatts,
            averageCadence: summary.averageCadence ?? averageCadence,
            routeMissingReason: routeMissingReason,
            dataQuality: dataQuality,
            isExcludedFromAnalysis: isExcludedFromAnalysis,
            createdAt: createdAt,
            updatedAt: updatedAt,
            companionNames: companionNames
        )
    }

    func withCompanionNames(_ names: [String], updatedAt: Date) -> UnifiedWorkout {
        UnifiedWorkout(
            id: id,
            externalId: externalId,
            source: source,
            workoutType: workoutType,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKcal: activeEnergyKcal,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            averageSpeedMetersPerSecond: averageSpeedMetersPerSecond,
            elevationGainMeters: elevationGainMeters,
            averagePowerWatts: averagePowerWatts,
            averageCadence: averageCadence,
            routeMissingReason: routeMissingReason,
            dataQuality: dataQuality,
            isExcludedFromAnalysis: isExcludedFromAnalysis,
            createdAt: createdAt,
            updatedAt: updatedAt,
            companionNames: names
        )
    }
}
