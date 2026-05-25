import Foundation
import SwiftData

@Model
final class PersistedWorkoutRoute {
    var id: UUID
    var workoutId: UUID
    var sourceRaw: String
    var encodedCoordinates: String?
    var coordinateCount: Int
    var totalDistanceMeters: Double
    var totalElevationGain: Double?
    var createdAt: Date
    var updatedAt: Date
    var courseIdentity: String?

    init(
        id: UUID = UUID(),
        workoutId: UUID,
        sourceRaw: String,
        encodedCoordinates: String? = nil,
        coordinateCount: Int = 0,
        totalDistanceMeters: Double,
        totalElevationGain: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        courseIdentity: String? = nil
    ) {
        self.id = id
        self.workoutId = workoutId
        self.sourceRaw = sourceRaw
        self.encodedCoordinates = encodedCoordinates
        self.coordinateCount = max(coordinateCount, 0)
        self.totalDistanceMeters = max(totalDistanceMeters, 0)
        self.totalElevationGain = totalElevationGain
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.courseIdentity = courseIdentity
    }
}
