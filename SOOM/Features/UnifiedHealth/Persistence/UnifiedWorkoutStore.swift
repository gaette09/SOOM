import Foundation
import SwiftData

protocol UnifiedWorkoutStore {
    func saveWorkout(_ workout: UnifiedWorkout) async throws
    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws
    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout]
    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout?
    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout?
    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws
    func deleteWorkout(id: UUID) async throws
}

@MainActor
final class SwiftDataUnifiedWorkoutStore: UnifiedWorkoutStore {
    private let modelContext: ModelContext
    private let mapper: UnifiedWorkoutPersistenceMapper
    private let referenceDate: () -> Date

    init(
        modelContext: ModelContext,
        mapper: UnifiedWorkoutPersistenceMapper = UnifiedWorkoutPersistenceMapper(),
        referenceDate: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.mapper = mapper
        self.referenceDate = referenceDate
    }

    func saveWorkout(_ workout: UnifiedWorkout) async throws {
        try upsert(workout)
        try modelContext.save()
    }

    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {
        for workout in workouts {
            try upsert(workout)
        }

        try modelContext.save()
    }

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        guard days > 0 else { return [] }

        let threshold = Calendar.current.date(
            byAdding: .day,
            value: -days,
            to: referenceDate()
        ) ?? referenceDate()

        let descriptor = FetchDescriptor<UnifiedWorkoutRecord>(
            predicate: #Predicate { record in
                record.startDate >= threshold
            },
            sortBy: [
                SortDescriptor(\UnifiedWorkoutRecord.startDate, order: .reverse)
            ]
        )

        return try modelContext.fetch(descriptor).map(mapper.makeWorkout)
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? {
        guard let record = try fetchRecord(id: id) else {
            return nil
        }

        return mapper.makeWorkout(from: record)
    }

    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? {
        guard let record = try fetchRecord(externalId: externalId, source: source) else {
            return nil
        }

        return mapper.makeWorkout(from: record)
    }

    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {
        guard let record = try fetchRecord(id: id) else {
            return
        }

        record.isExcludedFromAnalysis = isExcluded
        record.updatedAt = referenceDate()
        try modelContext.save()
    }

    func deleteWorkout(id: UUID) async throws {
        guard let record = try fetchRecord(id: id) else {
            return
        }

        modelContext.delete(record)
        try modelContext.save()
    }

    private func upsert(_ workout: UnifiedWorkout) throws {
        let existingRecord: UnifiedWorkoutRecord?

        if let externalId = workout.externalId {
            existingRecord = try fetchRecord(externalId: externalId, source: workout.source)
        } else {
            existingRecord = try fetchRecord(id: workout.id)
        }

        if let existingRecord {
            mapper.update(
                existingRecord,
                with: workout,
                syncTimestamp: referenceDate()
            )
        } else {
            modelContext.insert(
                mapper.makeRecord(
                    from: workout,
                    syncTimestamp: referenceDate()
                )
            )
        }
    }

    private func fetchRecord(id: UUID) throws -> UnifiedWorkoutRecord? {
        let workoutID = id
        var descriptor = FetchDescriptor<UnifiedWorkoutRecord>(
            predicate: #Predicate { record in
                record.id == workoutID
            }
        )
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).first
    }

    private func fetchRecord(externalId: String, source: UnifiedDataSource) throws -> UnifiedWorkoutRecord? {
        let externalID = externalId
        let sourceRaw = source.rawValue
        var descriptor = FetchDescriptor<UnifiedWorkoutRecord>(
            predicate: #Predicate { record in
                record.externalId == externalID && record.sourceRaw == sourceRaw
            }
        )
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).first
    }
}
