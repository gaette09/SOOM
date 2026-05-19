import Foundation
import SwiftData

@MainActor
final class SwiftDataCheckInStore: RecoveryCheckInEditableStore {
    private let modelContext: ModelContext
    private let mapper: RecoveryCheckInPersistenceMapper
    private let referenceDate: () -> Date

    init(
        modelContext: ModelContext,
        mapper: RecoveryCheckInPersistenceMapper = RecoveryCheckInPersistenceMapper(),
        referenceDate: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.mapper = mapper
        self.referenceDate = referenceDate
    }

    func fetchRecentCheckIns(days: Int) async throws -> [RecoveryCheckIn] {
        guard days > 0 else { return [] }

        let threshold = Calendar.current.date(
            byAdding: .day,
            value: -days,
            to: referenceDate()
        ) ?? referenceDate()

        let descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { record in
                record.date >= threshold
            },
            sortBy: [
                SortDescriptor(\CheckInRecord.date, order: .reverse)
            ]
        )

        let records = try modelContext.fetch(descriptor)
        return records.map(mapper.makeCheckIn)
    }

    func saveCheckIn(_ checkIn: RecoveryCheckIn) async throws {
        let now = referenceDate()
        let record = mapper.makeRecord(
            from: checkIn,
            createdAt: now,
            updatedAt: now
        )

        modelContext.insert(record)
        try modelContext.save()
    }

    func updateCheckIn(_ checkIn: RecoveryCheckIn) async throws {
        guard let record = try fetchRecord(id: checkIn.id) else {
            return
        }

        record.date = checkIn.date
        record.fatigueLevel = checkIn.fatigueLevel
        record.sleepQuality = checkIn.sleepQuality
        record.muscleSoreness = checkIn.muscleSoreness
        record.moodLevel = checkIn.moodLevel
        record.note = checkIn.note
        record.updatedAt = referenceDate()

        try modelContext.save()
    }

    func deleteCheckIn(id: UUID) async throws {
        guard let record = try fetchRecord(id: id) else {
            return
        }

        modelContext.delete(record)
        try modelContext.save()
    }

    func deleteAllCheckIns() async throws {
        let records = try modelContext.fetch(FetchDescriptor<CheckInRecord>())

        for record in records {
            modelContext.delete(record)
        }

        try modelContext.save()
    }

    private func fetchRecord(id: UUID) throws -> CheckInRecord? {
        let recordID = id
        var descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { record in
                record.id == recordID
            }
        )
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).first
    }
}
