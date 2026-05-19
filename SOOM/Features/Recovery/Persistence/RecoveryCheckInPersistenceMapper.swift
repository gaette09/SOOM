import Foundation

struct RecoveryCheckInPersistenceMapper {
    func makeRecord(
        from checkIn: RecoveryCheckIn,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> CheckInRecord {
        CheckInRecord(
            id: checkIn.id,
            date: checkIn.date,
            fatigueLevel: checkIn.fatigueLevel,
            sleepQuality: checkIn.sleepQuality,
            muscleSoreness: checkIn.muscleSoreness,
            moodLevel: checkIn.moodLevel,
            note: checkIn.note,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func makeCheckIn(from record: CheckInRecord) -> RecoveryCheckIn {
        RecoveryCheckIn(
            id: record.id,
            date: record.date,
            fatigueLevel: record.fatigueLevel,
            sleepQuality: record.sleepQuality,
            muscleSoreness: record.muscleSoreness,
            moodLevel: record.moodLevel,
            note: record.note
        )
    }
}
