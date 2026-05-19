import Foundation
import SwiftData

protocol DailyRecoverySnapshotStore {
    func saveSnapshot(_ snapshot: DailyRecoverySnapshot) async throws
    func fetchRecentSnapshots(days: Int) async throws -> [DailyRecoverySnapshot]
    func fetchSnapshot(for date: Date) async throws -> DailyRecoverySnapshot?
    func deleteSnapshot(id: UUID) async throws
}

@MainActor
final class SwiftDataDailyRecoverySnapshotStore: DailyRecoverySnapshotStore {
    private let modelContext: ModelContext
    private let mapper: DailyRecoverySnapshotMapper
    private let calendar: Calendar
    private let referenceDate: () -> Date

    init(
        modelContext: ModelContext,
        mapper: DailyRecoverySnapshotMapper = DailyRecoverySnapshotMapper(),
        calendar: Calendar = .current,
        referenceDate: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.mapper = mapper
        self.calendar = calendar
        self.referenceDate = referenceDate
    }

    func saveSnapshot(_ snapshot: DailyRecoverySnapshot) async throws {
        let normalizedDate = calendar.startOfDay(for: snapshot.date)
        let now = referenceDate()

        if let record = try fetchRecord(for: normalizedDate) {
            update(record, with: snapshot, normalizedDate: normalizedDate, updatedAt: now)
        } else {
            modelContext.insert(
                mapper.makeRecord(
                    from: DailyRecoverySnapshot(
                        id: snapshot.id,
                        date: normalizedDate,
                        score: snapshot.score,
                        status: snapshot.status,
                        recommendation: snapshot.recommendation,
                        coachMessage: snapshot.coachMessage,
                        explanation: snapshot.explanation,
                        dataQuality: snapshot.dataQuality,
                        activityCount: snapshot.activityCount,
                        checkInId: snapshot.checkInId,
                        createdAt: now,
                        updatedAt: now
                    )
                )
            )
        }

        try modelContext.save()
    }

    func fetchRecentSnapshots(days: Int) async throws -> [DailyRecoverySnapshot] {
        guard days > 0 else { return [] }

        let today = calendar.startOfDay(for: referenceDate())
        let threshold = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today

        let descriptor = FetchDescriptor<DailyRecoverySnapshotRecord>(
            predicate: #Predicate { record in
                record.date >= threshold
            },
            sortBy: [
                SortDescriptor(\DailyRecoverySnapshotRecord.date, order: .reverse)
            ]
        )

        return try modelContext.fetch(descriptor).map(mapper.makeSnapshot)
    }

    func fetchSnapshot(for date: Date) async throws -> DailyRecoverySnapshot? {
        guard let record = try fetchRecord(for: date) else {
            return nil
        }

        return mapper.makeSnapshot(from: record)
    }

    func deleteSnapshot(id: UUID) async throws {
        guard let record = try fetchRecord(id: id) else {
            return
        }

        modelContext.delete(record)
        try modelContext.save()
    }

    private func update(
        _ record: DailyRecoverySnapshotRecord,
        with snapshot: DailyRecoverySnapshot,
        normalizedDate: Date,
        updatedAt: Date
    ) {
        record.id = snapshot.id
        record.date = normalizedDate
        record.score = snapshot.score
        record.status = snapshot.status
        record.recommendation = snapshot.recommendation
        record.coachMessage = snapshot.coachMessage
        record.explanation = snapshot.explanation
        record.dataQuality = mapper.makeDataQualityString(from: snapshot.dataQuality)
        record.activityCount = snapshot.activityCount
        record.checkInId = snapshot.checkInId
        record.updatedAt = updatedAt
    }

    private func fetchRecord(for date: Date) throws -> DailyRecoverySnapshotRecord? {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        var descriptor = FetchDescriptor<DailyRecoverySnapshotRecord>(
            predicate: #Predicate { record in
                record.date >= startOfDay && record.date < endOfDay
            }
        )
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).first
    }

    private func fetchRecord(id: UUID) throws -> DailyRecoverySnapshotRecord? {
        let snapshotID = id
        var descriptor = FetchDescriptor<DailyRecoverySnapshotRecord>(
            predicate: #Predicate { record in
                record.id == snapshotID
            }
        )
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).first
    }
}
