import Foundation

struct UnifiedWorkoutPersistenceMapper {
    func makeRecord(
        from workout: UnifiedWorkout,
        syncTimestamp: Date? = nil,
        isExcludedFromAnalysis: Bool? = nil
    ) -> UnifiedWorkoutRecord {
        let record = UnifiedWorkoutRecord(
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
            averagePowerWatts: workout.averagePowerWatts,
            averageCadence: workout.averageCadence,
            routeMissingReasonRaw: workout.routeMissingReason.rawValue,
            dataQualityRaw: workout.dataQuality.rawValue,
            createdAt: workout.createdAt,
            updatedAt: workout.updatedAt,
            syncTimestamp: syncTimestamp,
            isExcludedFromAnalysis: isExcludedFromAnalysis ?? workout.isExcludedFromAnalysis,
            companionNames: workout.companionNames
        )
        record.userTitle = workout.userTitle
        record.userDescription = workout.userDescription
        record.sharingVisibilityRaw = workout.sharingVisibilityRaw
        record.isBookmarked = workout.isBookmarked
        record.deviceName = workout.deviceName
        record.locationName = workout.locationName
        record.preferredWorkoutID = workout.preferredWorkoutID
        record.keepSeparate = workout.keepSeparate
        record.resolutionRequestID = workout.resolutionRequestID
        return record
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
            averagePowerWatts: record.averagePowerWatts,
            averageCadence: record.averageCadence,
            routeMissingReason: record.routeMissingReasonRaw.flatMap(WorkoutRouteMissingReason.init(rawValue:)) ?? .none,
            dataQuality: UnifiedDataQuality(rawValue: record.dataQualityRaw) ?? .unknown,
            isExcludedFromAnalysis: record.isExcludedFromAnalysis,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            companionNames: record.companionNames,
            userTitle: record.userTitle, userDescription: record.userDescription,
            sharingVisibilityRaw: record.sharingVisibilityRaw, isBookmarked: record.isBookmarked,
            deviceName: record.deviceName, locationName: record.locationName,
            preferredWorkoutID: record.preferredWorkoutID, keepSeparate: record.keepSeparate, resolutionRequestID: record.resolutionRequestID
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
        record.averagePowerWatts = workout.averagePowerWatts
        record.averageCadence = workout.averageCadence
        record.routeMissingReasonRaw = workout.routeMissingReason.rawValue
        record.dataQualityRaw = workout.dataQuality.rawValue
        record.updatedAt = workout.updatedAt
        record.syncTimestamp = syncTimestamp
        record.deviceName = workout.deviceName ?? record.deviceName
        record.locationName = workout.locationName ?? record.locationName
        record.preferredWorkoutID = workout.preferredWorkoutID ?? record.preferredWorkoutID
        record.keepSeparate = workout.keepSeparate ?? record.keepSeparate
        record.resolutionRequestID = workout.resolutionRequestID ?? record.resolutionRequestID
    }
}
