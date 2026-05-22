import Foundation

enum WorkoutZoneType: String, Equatable, Codable {
    case heartRate
    case cadence
    case power
}

struct WorkoutZone: Identifiable, Equatable {
    var id: String { "\(zoneType.rawValue)-\(zoneIndex)" }

    let zoneType: WorkoutZoneType
    let zoneIndex: Int
    let durationSeconds: TimeInterval
    let percentage: Double
    let rangeDescription: String?

    init(
        zoneType: WorkoutZoneType,
        zoneIndex: Int,
        durationSeconds: TimeInterval,
        percentage: Double,
        rangeDescription: String? = nil
    ) {
        self.zoneType = zoneType
        self.zoneIndex = zoneIndex
        self.durationSeconds = max(0, durationSeconds)
        self.percentage = min(100, max(0, percentage))
        self.rangeDescription = rangeDescription
    }
}
