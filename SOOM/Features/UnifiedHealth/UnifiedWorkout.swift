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
            routeMissingReason: reason,
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
            routeMissingReason: routeMissingReason,
            dataQuality: dataQuality,
            isExcludedFromAnalysis: isExcludedFromAnalysis,
            createdAt: createdAt,
            updatedAt: updatedAt,
            companionNames: names
        )
    }
}
