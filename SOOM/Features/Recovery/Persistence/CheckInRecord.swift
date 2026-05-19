import Foundation
import SwiftData

@Model
final class CheckInRecord {
    var id: UUID
    var date: Date
    var fatigueLevel: Int
    var sleepQuality: Int
    var muscleSoreness: Int
    var moodLevel: Int
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        fatigueLevel: Int,
        sleepQuality: Int,
        muscleSoreness: Int,
        moodLevel: Int,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.fatigueLevel = Self.normalizedScaleValue(fatigueLevel)
        self.sleepQuality = Self.normalizedScaleValue(sleepQuality)
        self.muscleSoreness = Self.normalizedScaleValue(muscleSoreness)
        self.moodLevel = Self.normalizedScaleValue(moodLevel)
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private static func normalizedScaleValue(_ value: Int) -> Int {
        min(max(value, 1), 5)
    }
}
