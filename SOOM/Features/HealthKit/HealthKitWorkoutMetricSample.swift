import Foundation

enum HealthKitWorkoutMetricSampleType: String, Equatable, Codable {
    case heartRate
    case cyclingCadence
    case cyclingPower
}

struct HealthKitWorkoutMetricSample: Identifiable, Equatable {
    let id: UUID
    let sampleType: HealthKitWorkoutMetricSampleType
    let value: Double
    let unit: String
    let startDate: Date
    let endDate: Date

    var durationSeconds: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }

    init(
        id: UUID = UUID(),
        sampleType: HealthKitWorkoutMetricSampleType,
        value: Double,
        unit: String,
        startDate: Date,
        endDate: Date
    ) {
        self.id = id
        self.sampleType = sampleType
        self.value = value
        self.unit = unit
        self.startDate = startDate
        self.endDate = endDate
    }
}
