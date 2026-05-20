import Foundation

struct UnifiedWorkoutPersistenceMapper {
    func makeRecord(
        from workout: UnifiedWorkout,
        syncTimestamp: Date? = nil,
        isExcludedFromAnalysis: Bool = false
    ) -> UnifiedWorkoutRecord {
        UnifiedWorkoutRecord(
            id: workout.id,
            externalId: workout.externalId,
            sourceRaw: workout.source.rawValue,
            workoutTypeRaw: workout.workoutType.rawValue,
            startDate: workout.startDate,
            endDate: workout.endDate,
            durationSeconds: workout.durationSeconds,
            distanceMeters: workout.distanceMeters,
            activeEnergyKcal: workout.activeEnergyKcal,
            averageHeartRate: workout.averageHeartRate,
            maxHeartRate: workout.maxHeartRate,
            averageSpeedMetersPerSecond: workout.averageSpeedMetersPerSecond,
            elevationGainMeters: workout.elevationGainMeters,
            dataQualityRaw: workout.dataQuality.rawValue,
            createdAt: workout.createdAt,
            updatedAt: workout.updatedAt,
            syncTimestamp: syncTimestamp,
            isExcludedFromAnalysis: isExcludedFromAnalysis
        )
    }

    func makeWorkout(from record: UnifiedWorkoutRecord) -> UnifiedWorkout {
        UnifiedWorkout(
            id: record.id,
            externalId: record.externalId,
            source: UnifiedDataSource(rawValue: record.sourceRaw) ?? .unknown,
            workoutType: UnifiedWorkoutType(rawValue: record.workoutTypeRaw) ?? .other,
            startDate: record.startDate,
            endDate: record.endDate,
            durationSeconds: record.durationSeconds,
            distanceMeters: record.distanceMeters,
            activeEnergyKcal: record.activeEnergyKcal,
            averageHeartRate: record.averageHeartRate,
            maxHeartRate: record.maxHeartRate,
            averageSpeedMetersPerSecond: record.averageSpeedMetersPerSecond,
            elevationGainMeters: record.elevationGainMeters,
            dataQuality: UnifiedDataQuality(rawValue: record.dataQualityRaw) ?? .unknown,
            isExcludedFromAnalysis: record.isExcludedFromAnalysis,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    func update(
        _ record: UnifiedWorkoutRecord,
        with workout: UnifiedWorkout,
        syncTimestamp: Date? = nil
    ) {
        record.id = workout.id
        record.externalId = workout.externalId
        record.sourceRaw = workout.source.rawValue
        record.workoutTypeRaw = workout.workoutType.rawValue
        record.startDate = workout.startDate
        record.endDate = workout.endDate
        record.durationSeconds = max(workout.durationSeconds, 0)
        record.distanceMeters = workout.distanceMeters
        record.activeEnergyKcal = workout.activeEnergyKcal
        record.averageHeartRate = workout.averageHeartRate
        record.maxHeartRate = workout.maxHeartRate
        record.averageSpeedMetersPerSecond = workout.averageSpeedMetersPerSecond
        record.elevationGainMeters = workout.elevationGainMeters
        record.dataQualityRaw = workout.dataQuality.rawValue
        record.updatedAt = workout.updatedAt
        record.syncTimestamp = syncTimestamp
    }
}
