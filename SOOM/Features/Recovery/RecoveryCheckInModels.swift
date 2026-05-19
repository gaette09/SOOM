import Foundation

struct RecoveryCheckIn: Identifiable {
    let id: UUID
    let date: Date
    let fatigueLevel: Int
    let sleepQuality: Int
    let muscleSoreness: Int
    let moodLevel: Int
    let note: String?

    init(
        id: UUID = UUID(),
        date: Date,
        fatigueLevel: Int,
        sleepQuality: Int,
        muscleSoreness: Int,
        moodLevel: Int,
        note: String? = nil
    ) {
        self.id = id
        self.date = date
        self.fatigueLevel = Self.normalizedScaleValue(fatigueLevel)
        self.sleepQuality = Self.normalizedScaleValue(sleepQuality)
        self.muscleSoreness = Self.normalizedScaleValue(muscleSoreness)
        self.moodLevel = Self.normalizedScaleValue(moodLevel)
        self.note = note
    }

    private static func normalizedScaleValue(_ value: Int) -> Int {
        min(max(value, 1), 5)
    }
}

struct RecoveryCheckInSummary {
    let latestCheckIn: RecoveryCheckIn?
    let weeklyAverageFatigue: Double
    let weeklyAverageSleepQuality: Double
    let weeklyAverageSoreness: Double

    static func make(from checkIns: [RecoveryCheckIn]) -> RecoveryCheckInSummary {
        let sortedCheckIns = checkIns.sorted { $0.date > $1.date }

        return RecoveryCheckInSummary(
            latestCheckIn: sortedCheckIns.first,
            weeklyAverageFatigue: average(checkIns.map(\.fatigueLevel)),
            weeklyAverageSleepQuality: average(checkIns.map(\.sleepQuality)),
            weeklyAverageSoreness: average(checkIns.map(\.muscleSoreness))
        )
    }

    private static func average(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
}

extension RecoveryCheckIn {
    static func mockRecent(referenceDate: Date = Date()) -> [RecoveryCheckIn] {
        [
            RecoveryCheckIn(
                date: Calendar.current.date(byAdding: .day, value: -6, to: referenceDate) ?? referenceDate,
                fatigueLevel: 3,
                sleepQuality: 4,
                muscleSoreness: 2,
                moodLevel: 4,
                note: "가벼운 피로감"
            ),
            RecoveryCheckIn(
                date: Calendar.current.date(byAdding: .day, value: -4, to: referenceDate) ?? referenceDate,
                fatigueLevel: 4,
                sleepQuality: 3,
                muscleSoreness: 3,
                moodLevel: 3,
                note: nil
            ),
            RecoveryCheckIn(
                date: Calendar.current.date(byAdding: .day, value: -2, to: referenceDate) ?? referenceDate,
                fatigueLevel: 2,
                sleepQuality: 4,
                muscleSoreness: 2,
                moodLevel: 4,
                note: "몸이 조금 가벼움"
            ),
            RecoveryCheckIn(
                date: referenceDate,
                fatigueLevel: 3,
                sleepQuality: 5,
                muscleSoreness: 2,
                moodLevel: 4,
                note: "수면감 좋음"
            )
        ]
    }
}
