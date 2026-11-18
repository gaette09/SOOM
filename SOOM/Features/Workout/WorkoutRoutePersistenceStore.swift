import Foundation
import SwiftData

protocol WorkoutRoutePersistenceStoring {
    func saveRoute(_ route: WorkoutRoute) async throws
    func fetchRoute(workoutId: UUID) async throws -> WorkoutRoute?
    func fetchRoutes(workoutIds: [UUID]) async throws -> [WorkoutRoute]
    func deleteRoute(workoutId: UUID) async throws
    func deleteAllRoutes() async throws
}

@MainActor
final class SwiftDataWorkoutRoutePersistenceStore: WorkoutRoutePersistenceStoring, WorkoutRouteStore {
    private let modelContext: ModelContext
    private let mapper: WorkoutRouteMapper
    private let referenceDate: () -> Date

    init(
        modelContext: ModelContext,
        mapper: WorkoutRouteMapper = WorkoutRouteMapper(),
        referenceDate: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.mapper = mapper
        self.referenceDate = referenceDate
    }

    func saveRoute(_ route: WorkoutRoute) async throws {
        if let existingRecord = try fetchRecord(workoutId: route.workoutId) {
            mapper.update(
                existingRecord,
                with: route,
                updatedAt: referenceDate()
            )
        } else {
            modelContext.insert(
                mapper.makeRecord(
                    from: route,
                    updatedAt: referenceDate()
                )
            )
        }

        if let saved = try fetchRecord(workoutId: route.workoutId) {
            try HealthCloudJournal.route(saved, context: modelContext)
        }
        try HealthCloudJournal.commit(modelContext)
    }

    func fetchRoute(workoutId: UUID) async throws -> WorkoutRoute? {
        #if DEBUG
        WorkoutCardPerformanceProbe.hit("routeFetch")
        #endif
        guard let record = try fetchRecord(workoutId: workoutId) else {
            return nil
        }

        return mapper.makeRoute(from: record)
    }

    func fetchRoutes(workoutIds: [UUID]) async throws -> [WorkoutRoute] {
        var routes: [WorkoutRoute] = []

        for workoutId in workoutIds {
            if let route = try await fetchRoute(workoutId: workoutId) {
                routes.append(route)
            }
        }

        return routes
    }

    func hasAnyWorkoutRoute() async throws -> Bool {
        var descriptor = FetchDescriptor<PersistedWorkoutRoute>()
        descriptor.fetchLimit = 1

        return try !modelContext.fetch(descriptor).isEmpty
    }

    func deleteRoute(workoutId: UUID) async throws {
        guard let record = try fetchRecord(workoutId: workoutId) else {
            return
        }

        try HealthCloudJournal.record(.route, key: record.workoutId.uuidString.lowercased(), payload: nil, deleted: true, context: modelContext)
        modelContext.delete(record)
        try HealthCloudJournal.commit(modelContext)
    }

    func deleteAllRoutes() async throws {
        let records = try modelContext.fetch(FetchDescriptor<PersistedWorkoutRoute>())

        for record in records {
            try HealthCloudJournal.record(.route, key: record.workoutId.uuidString.lowercased(), payload: nil, deleted: true, context: modelContext)
        modelContext.delete(record)
        }

        try HealthCloudJournal.commit(modelContext)
    }

    private func fetchRecord(workoutId: UUID) throws -> PersistedWorkoutRoute? {
        let workoutID = workoutId
        var descriptor = FetchDescriptor<PersistedWorkoutRoute>(
            predicate: #Predicate { record in
                record.workoutId == workoutID
            }
        )
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).first
    }
}
