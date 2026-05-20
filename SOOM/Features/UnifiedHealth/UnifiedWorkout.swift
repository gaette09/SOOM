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
    let dataQuality: UnifiedDataQuality
    let isExcludedFromAnalysis: Bool
    let createdAt: Date
    let updatedAt: Date

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
        dataQuality: UnifiedDataQuality,
        isExcludedFromAnalysis: Bool = false,
        createdAt: Date,
        updatedAt: Date
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
        self.dataQuality = dataQuality
        self.isExcludedFromAnalysis = isExcludedFromAnalysis
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
