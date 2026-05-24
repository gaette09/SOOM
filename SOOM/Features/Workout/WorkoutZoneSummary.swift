import Foundation

struct WorkoutZoneSummary: Equatable {
    let type: WorkoutZoneType
    let zones: [WorkoutZone]
    let dominantZone: WorkoutZone?
    let insightText: String?
    let dataSource: WorkoutZoneDataSource

    init(
        type: WorkoutZoneType,
        zones: [WorkoutZone],
        dominantZone: WorkoutZone?,
        insightText: String?,
        dataSource: WorkoutZoneDataSource = .fallbackEstimate
    ) {
        self.type = type
        self.zones = zones
        self.dominantZone = dominantZone
        self.insightText = insightText
        self.dataSource = dataSource
    }

    var isAvailable: Bool {
        !zones.isEmpty
    }
}

struct WorkoutZoneDurationInput: Equatable {
    let zoneIndex: Int
    let durationSeconds: TimeInterval
    let rangeDescription: String?

    init(
        zoneIndex: Int,
        durationSeconds: TimeInterval,
        rangeDescription: String? = nil
    ) {
        self.zoneIndex = zoneIndex
        self.durationSeconds = durationSeconds
        self.rangeDescription = rangeDescription
    }
}
