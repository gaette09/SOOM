import Foundation
import SwiftData

/// Uses the currently opened account's existing workout database. The optional
/// blob travels with that workout's cloud outbox, account deletion and restore.
@MainActor
struct WorkoutTelemetryStore {
    let modelContext: ModelContext

    func save(_ telemetry: WorkoutTelemetry) throws {
        guard telemetry.samples.count <= 100_000, telemetry.intervals.count <= 100_000,
              telemetry.splits.count <= 2_000, telemetry.heartRateZones.count <= 20,
              telemetry.summaryMetrics.count <= 100, telemetry.events.count <= 2_000 else {
            throw WorkoutTelemetryError.tooLarge
        }
        guard let record = try record(workoutID: telemetry.workoutID) else { throw HealthCloudError.invalidPayload }
        let workout = UnifiedWorkoutPersistenceMapper().makeWorkout(from: record)
        let incoming = telemetry.validated(for: workout).coalescingSamples()
        let existing = try load(workoutID: telemetry.workoutID)
        let merged = (existing.map { incoming.merging($0) } ?? incoming).coalescingSamples()
        if var comparable = existing {
            comparable.fetchedAt = merged.fetchedAt
            if comparable == merged { return }
        }
        guard !merged.isEmpty, merged != existing else { return }
        let data = try JSONEncoder().encode(merged)
        guard data.count < 19 * 1_024 * 1_024 else { throw WorkoutTelemetryError.tooLarge }
        record.telemetryData = data
        try HealthCloudJournal.workout(record, context: modelContext)
        try HealthCloudJournal.commit(modelContext)
    }

    func load(workoutID: UUID) throws -> WorkoutTelemetry? {
        guard let record = try record(workoutID: workoutID), let data = record.telemetryData else { return nil }
        let value = try JSONDecoder().decode(WorkoutTelemetry.self, from: data)
        return value.validated(for: UnifiedWorkoutPersistenceMapper().makeWorkout(from: record))
    }

    /// Only members of the same account and the same strict duplicate group can
    /// contribute channels. Do not copy or add the distance totals together.
    func resolved(for workout: UnifiedWorkout) throws -> WorkoutTelemetry? {
        let related = try relatedWorkouts(to: workout).filter { workout.preferredWorkoutID != nil || $0.id == workout.id }
        var result = try load(workoutID: workout.id)
        for member in related where member.id != workout.id {
            guard var next = try load(workoutID: member.id) else { continue }
            next.workoutID = workout.id
            if workout.preferredWorkoutID != nil, let primary = result {
                for channel in WorkoutTelemetryChannel.allCases where primary.samples.contains(where: { $0.value(for: channel) != nil }) {
                    next.samples = next.samples.map { $0.removing(channel) }.filter(\.hasMeasurement)
                }
                if primary.samples.contains(where: { $0.distanceMeters != nil }) {
                    next.samples = next.samples.map { var copy = $0; copy.distanceMeters = nil; return copy }.filter(\.hasMeasurement)
                }
                let kinds = Set(primary.intervals.map(\.kind))
                next.intervals.removeAll { kinds.contains($0.kind) }
            }
            result = result.map { $0.merging(next) } ?? next
        }
        return result?.validated(for: workout)
    }

    func relatedWorkouts(to workout: UnifiedWorkout) throws -> [UnifiedWorkout] {
        let lower = workout.startDate.addingTimeInterval(-86_400)
        let upper = workout.startDate.addingTimeInterval(86_400)
        let records = try modelContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>(
            predicate: #Predicate { $0.startDate >= lower && $0.startDate <= upper }))
        let mapper = UnifiedWorkoutPersistenceMapper()
        let engine = UnifiedWorkoutDeduplicationEngine()
        return engine.canonicalGroups(records.map(mapper.makeWorkout))
            .first { $0.sourceWorkouts.contains { $0.id == workout.id } }?.sourceWorkouts
            .sorted { $0.id.uuidString < $1.id.uuidString } ?? []
    }

    func resolvedRoute(for workout: UnifiedWorkout) async throws -> WorkoutRoute? {
        let store = SwiftDataWorkoutRoutePersistenceStore(modelContext: modelContext)
        let related = try relatedWorkouts(to: workout).filter { workout.preferredWorkoutID != nil || $0.id == workout.id }
        let ordered = related.sorted {
            if $0.id == workout.id && $1.id != workout.id { return true }
            if $1.id == workout.id && $0.id != workout.id { return false }
            return $0.id.uuidString < $1.id.uuidString
        }
        for member in ordered {
            var ids = [member.id]
            if member.source == .appleHealthKit, let raw = member.externalId, let id = UUID(uuidString: raw), !ids.contains(id) { ids.append(id) }
            for id in ids {
                guard let route = try await store.fetchRoute(workoutId: id) else { continue }
                let points = route.coordinates.filter {
                    guard let time = $0.timestamp else { return true }
                    return time >= workout.startDate && time <= workout.endDate
                }
                guard points.count > 1 else { continue }
                // Select one complete route, never splice conflicting GPS tracks.
                return WorkoutRoute(id: route.id, workoutId: workout.id, source: route.source,
                    coordinates: points, totalDistanceMeters: workout.distanceMeters ?? route.totalDistanceMeters,
                    totalElevationGain: route.totalElevationGain, createdAt: route.createdAt)
            }
        }
        return nil
    }

    private func record(workoutID: UUID) throws -> UnifiedWorkoutRecord? {
        var query = FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.id == workoutID })
        query.fetchLimit = 1
        return try modelContext.fetch(query).first
    }
}

enum WorkoutTelemetryError: Error, LocalizedError {
    case tooLarge
    var errorDescription: String? { "상세 측정값이 한 번에 저장할 수 있는 크기를 넘었어요. 운동 요약은 보관됩니다." }
}
