import Foundation
import SwiftData

@Model
final class UnifiedWorkoutRecord {
    var id: UUID
    var externalId: String?
    var sourceRaw: String
    var workoutTypeRaw: String
    var startDate: Date
    var endDate: Date
    var durationSeconds: Double
    var distanceMeters: Double?
    var activeEnergyKcal: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var averageSpeedMetersPerSecond: Double?
    var elevationGainMeters: Double?
    var dataQualityRaw: String
    var createdAt: Date
    var updatedAt: Date
    var syncTimestamp: Date?
    var isExcludedFromAnalysis: Bool

    init(
        id: UUID = UUID(),
        externalId: String? = nil,
        sourceRaw: String,
        workoutTypeRaw: String,
        startDate: Date,
        endDate: Date,
        durationSeconds: Double,
        distanceMeters: Double? = nil,
        activeEnergyKcal: Double? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        averageSpeedMetersPerSecond: Double? = nil,
        elevationGainMeters: Double? = nil,
        dataQualityRaw: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncTimestamp: Date? = nil,
        isExcludedFromAnalysis: Bool = false
    ) {
        self.id = id
        self.externalId = externalId
        self.sourceRaw = sourceRaw
        self.workoutTypeRaw = workoutTypeRaw
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = max(durationSeconds, 0)
        self.distanceMeters = distanceMeters
        self.activeEnergyKcal = activeEnergyKcal
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.averageSpeedMetersPerSecond = averageSpeedMetersPerSecond
        self.elevationGainMeters = elevationGainMeters
        self.dataQualityRaw = dataQualityRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncTimestamp = syncTimestamp
        self.isExcludedFromAnalysis = isExcludedFromAnalysis
    }
}
