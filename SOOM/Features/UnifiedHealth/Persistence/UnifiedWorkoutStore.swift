import Foundation
import SwiftData

protocol UnifiedWorkoutStore {
    func saveWorkout(_ workout: UnifiedWorkout) async throws
    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws
    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout]
    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout?
    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout?
    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws
    func updateCompanions(id: UUID, names: [String]) async throws
    func deleteWorkout(id: UUID) async throws
    func deleteAllWorkouts() async throws
}

extension UnifiedWorkoutStore {
    /// Raw source records stay available for provider upserts and duplicate
    /// review. Read-only product surfaces consume one enriched session each.
    func fetchCanonicalRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        UnifiedWorkoutDeduplicationEngine().canonicalWorkouts(try await fetchRecentWorkouts(days: days))
    }
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
        try HealthCloudJournal.commit(modelContext)
    }

    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {
        for workout in workouts {
            try upsert(workout)
        }

        try HealthCloudJournal.commit(modelContext)
    }

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        #if DEBUG
        WorkoutCardPerformanceProbe.hit("workoutFetch")
        #endif
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

    func hasAnyWorkout() async throws -> Bool {
        var descriptor = FetchDescriptor<UnifiedWorkoutRecord>()
        descriptor.fetchLimit = 1

        return try !modelContext.fetch(descriptor).isEmpty
    }

    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {
        guard let record = try fetchRecord(id: id) else {
            return
        }

        record.isExcludedFromAnalysis = isExcluded
        record.updatedAt = referenceDate()
        try HealthCloudJournal.workout(record, context: modelContext)
        try HealthCloudJournal.commit(modelContext)
    }

    func updateCompanions(id: UUID, names: [String]) async throws {
        guard let record = try fetchRecord(id: id) else {
            return
        }

        record.companionNames = names
        record.updatedAt = referenceDate()
        try HealthCloudJournal.workout(record, context: modelContext)
        try HealthCloudJournal.commit(modelContext)
    }

    func deleteWorkout(id: UUID) async throws {
        guard let record = try fetchRecord(id: id) else {
            return
        }

        try recordDeletion(record)
        modelContext.delete(record)
        try HealthCloudJournal.commit(modelContext)
    }

    func deleteAllWorkouts() async throws {
        let records = try modelContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>())

        for record in records {
            try recordDeletion(record)
            modelContext.delete(record)
        }

        try HealthCloudJournal.commit(modelContext)
    }

    private func recordDeletion(_ record: UnifiedWorkoutRecord) throws {
        try HealthCloudJournal.record(.workout, key: record.id.uuidString.lowercased(), payload: nil, deleted: true, context: modelContext)
        guard modelContext.container.schema.entities.contains(where: { $0.name == "PersistedWorkoutRoute" }) else { return }
        let workoutID = record.id
        let routes = try modelContext.fetch(FetchDescriptor<PersistedWorkoutRoute>(predicate: #Predicate { $0.workoutId == workoutID }))
        for route in routes {
            try HealthCloudJournal.record(.route, key: route.workoutId.uuidString.lowercased(), payload: nil, deleted: true, context: modelContext)
            modelContext.delete(route)
        }
    }

    private func upsert(_ workout: UnifiedWorkout) throws {
        let existingRecord: UnifiedWorkoutRecord?

        if let externalId = workout.externalId {
            existingRecord = try fetchRecord(externalId: externalId, source: workout.source)
        } else {
            existingRecord = try fetchRecord(id: workout.id)
        }

        let saved: UnifiedWorkoutRecord
        if let existingRecord {
            // External identity upserts must preserve route/draft foreign IDs.
            let stableID = existingRecord.id
            mapper.update(existingRecord, with: workout)
            existingRecord.id = stableID
            saved = existingRecord
        } else {
            saved = mapper.makeRecord(from: workout)
            modelContext.insert(saved)
        }
        try HealthCloudJournal.workout(saved, context: modelContext)
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
