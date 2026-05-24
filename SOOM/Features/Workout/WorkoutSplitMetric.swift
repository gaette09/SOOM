import Foundation

struct WorkoutSplitMetric: Identifiable, Equatable {
    let splitIndex: Int
    let startTime: Date
    let endTime: Date
    let averagePace: TimeInterval?
    let averageSpeed: Double?
    let averageCadence: Double?
    let averageHeartRate: Double?
    let averagePower: Double?
    let distanceMeters: Double?

    var id: Int { splitIndex }

    var durationSeconds: TimeInterval {
        max(0, endTime.timeIntervalSince(startTime))
    }

    init(
        splitIndex: Int,
        startTime: Date,
        endTime: Date,
        averagePace: TimeInterval? = nil,
        averageSpeed: Double? = nil,
        averageCadence: Double? = nil,
        averageHeartRate: Double? = nil,
        averagePower: Double? = nil,
        distanceMeters: Double? = nil
    ) {
        self.splitIndex = splitIndex
        self.startTime = startTime
        self.endTime = endTime
        self.averagePace = averagePace
        self.averageSpeed = averageSpeed
        self.averageCadence = averageCadence
        self.averageHeartRate = averageHeartRate
        self.averagePower = averagePower
        self.distanceMeters = distanceMeters
    }
}
