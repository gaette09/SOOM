import Foundation
import SwiftData

/// Registration is container-scoped, never a global current-user lookup. A
/// delayed task holding A's context can only add to A's outbox after switching to B.
@MainActor
enum HealthCloudJournal {
    private final class Registration {
        weak var container: ModelContainer?
        let userID: UUID
        var isRetired = false
        init(container: ModelContainer, userID: UUID) { self.container = container; self.userID = userID }
    }
    private static var accounts: [ObjectIdentifier: Registration] = [:]
    private static var suppressions: Set<ObjectIdentifier> = []
    static let didCommit = Notification.Name("SOOM.HealthCloudJournal.didCommit")

    static func register(_ container: ModelContainer, userID: UUID) {
        if let previous = accounts[ObjectIdentifier(container)], previous.container === container { return }
        accounts[ObjectIdentifier(container)] = Registration(container: container, userID: userID)
    }
    static func accountID(for context: ModelContext) -> UUID? {
        guard let registration = accounts[ObjectIdentifier(context.container)], registration.container === context.container else { return nil }
        return registration.userID
    }
    static func withoutRecording<T>(_ context: ModelContext, operation: () throws -> T) rethrows -> T {
        let key = ObjectIdentifier(context.container)
        let wasSuppressed = suppressions.contains(key)
        suppressions.insert(key)
        defer { if !wasSuppressed { suppressions.remove(key) } }
        return try operation()
    }
    static func retire(_ container: ModelContainer) {
        guard let registration = accounts[ObjectIdentifier(container)], registration.container === container else { return }
        registration.isRetired = true
    }
    static func isRetired(_ context: ModelContext) -> Bool {
        guard let registration = accounts[ObjectIdentifier(context.container)], registration.container === context.container else { return false }
        return registration.isRetired
    }
    private static func assertWritable(_ context: ModelContext) throws {
        if let registration = accounts[ObjectIdentifier(context.container)],
           registration.container === context.container, registration.isRetired {
            context.rollback()
            throw HealthCloudError.accountChanged
        }
    }
    static func commit(_ context: ModelContext) throws {
        // Empty cleanup retries remain safe after another store failed erasure.
        if context.hasChanges { try assertWritable(context) }
        do { try context.save() }
        catch { context.rollback(); throw error }
        didSave(context)
    }
    static func didSave(_ context: ModelContext) {
        guard let userID = accountID(for: context),
              !suppressions.contains(ObjectIdentifier(context.container)) else { return }
        NotificationCenter.default.post(name: didCommit, object: userID)
    }
    static func record(_ kind: HealthCloudKind, key: String, payload: HealthCloudPayload?,
                       deleted: Bool = false, context: ModelContext) throws {
        try assertWritable(context)
        guard accountID(for: context) != nil,
              !suppressions.contains(ObjectIdentifier(context.container)) else { return }
        let encoded = try payload?.encoded()
        if let entry = try find(kind.rawValue, key: key, context: context) {
            // Repeated imports/refreshes with unchanged content need no network work.
            guard entry.payload != encoded || entry.isTombstone != deleted else { return }
            entry.payload = encoded
            entry.isTombstone = deleted
            entry.pending = true
            entry.mutationID = UUID()
        } else {
            context.insert(HealthCloudOutboxRecord(kind: kind.rawValue, recordKey: key,
                payload: encoded, isDeleted: deleted))
        }
    }
    static func find(_ kind: String, key: String, context: ModelContext) throws -> HealthCloudOutboxRecord? {
        let fullKey = kind + ":" + key
        var query = FetchDescriptor<HealthCloudOutboxRecord>(predicate: #Predicate { $0.key == fullKey })
        query.fetchLimit = 1
        return try context.fetch(query).first
    }
    static func workout(_ record: UnifiedWorkoutRecord, context: ModelContext) throws {
        try self.record(.workout, key: record.id.uuidString.lowercased(),
            payload: HealthCloudPayload(workout: UnifiedWorkoutPersistenceMapper().makeWorkout(from: record),
                telemetry: try record.telemetryData.map { try JSONDecoder().decode(WorkoutTelemetry.self, from: $0) }), context: context)
    }
    static func route(_ record: PersistedWorkoutRoute, context: ModelContext) throws {
        try self.record(.route, key: record.workoutId.uuidString.lowercased(),
            payload: HealthCloudPayload(route: .init(record)), context: context)
    }
    static func checkIn(_ record: CheckInRecord, context: ModelContext) throws {
        try self.record(.checkIn, key: record.id.uuidString.lowercased(),
            payload: HealthCloudPayload(checkIn: .init(record)), context: context)
    }
    static func snapshot(_ record: DailyRecoverySnapshotRecord, context: ModelContext) throws {
        try self.record(.recoverySnapshot, key: snapshotKey(record.date),
            payload: HealthCloudPayload(snapshot: .init(record)), context: context)
    }
    nonisolated static func snapshotKey(_ date: Date) -> String {
        // Store-local calendar day is already normalized by the snapshot store.
        String(Int64(date.timeIntervalSince1970))
    }

    nonisolated static func validate(kind: String, key: String, data: Data?, deleted: Bool) throws {
        guard let kind = HealthCloudKind(rawValue: kind) else { throw HealthCloudError.invalidPayload }
        if kind == .recoverySnapshot {
            guard Int64(key) != nil else { throw HealthCloudError.invalidPayload }
        } else {
            guard UUID(uuidString: key) != nil else { throw HealthCloudError.invalidPayload }
        }
        if deleted {
            guard data == nil else { throw HealthCloudError.invalidPayload }
            return
        }
        guard let data else { throw HealthCloudError.invalidPayload }
        let payload = try HealthCloudPayload.decode(data)
        switch kind {
        case .workout:
            guard let id = UUID(uuidString: key), payload.workout?.id == id else { throw HealthCloudError.invalidPayload }
            if let telemetry = payload.telemetry, telemetry.workoutID != id { throw HealthCloudError.invalidPayload }
        case .route:
            guard let id = UUID(uuidString: key), let route = payload.route, route.workoutId == id else { throw HealthCloudError.invalidPayload }
            if route.coordinateCount > 0 {
                guard WorkoutRouteMapper().decodeCoordinates(route.encodedCoordinates).count == route.coordinateCount else { throw HealthCloudError.invalidPayload }
            }
        case .checkIn:
            guard let id = UUID(uuidString: key), payload.checkIn?.id == id else { throw HealthCloudError.invalidPayload }
        case .recoverySnapshot:
            guard let snapshot = payload.snapshot, snapshotKey(snapshot.date) == key else { throw HealthCloudError.invalidPayload }
        }
    }

    /// Validate immutable transport bytes off the UI executor. SwiftData reads,
    /// conflict handling, commits and account checks remain on the main actor.
    nonisolated static func validateBatch(_ rows: [HealthCloudRemoteRecord]) async throws -> [Bool] {
        let task = Task.detached(priority: .userInitiated) {
            #if DEBUG
            assert(!Thread.isMainThread, "Transport validation must stay off the UI thread")
            #endif
            return try rows.map { row in
                try Task.checkCancellation()
                do {
                    try validate(kind: row.kind, key: row.recordKey, data: row.payloadData, deleted: row.isDeleted)
                    return true
                } catch {
                    switch error {
                    case HealthCloudError.invalidPayload, is DecodingError: return false
                    default: throw error
                    }
                }
            }
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    /// Applies a server version to the account cache. The outbox is handled by
    /// the synchronizer, so this operation must not generate a new local edit.
    static func apply(kind: String, key: String, data: Data?, deleted: Bool, context: ModelContext) throws {
        guard let kind = HealthCloudKind(rawValue: kind) else { throw HealthCloudError.invalidPayload }
        let payload = try data.map(HealthCloudPayload.decode)
        try withoutRecording(context) {
            switch kind {
            case .workout:
                guard let id = UUID(uuidString: key), deleted || payload?.workout?.id == id else {
                    throw HealthCloudError.invalidPayload
                }
                let records = try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.id == id }))
                if deleted { records.forEach { context.delete($0) } }
                else if let workout = payload?.workout {
                    if let existing = records.first {
                        UnifiedWorkoutPersistenceMapper().update(existing, with: workout)
                        existing.isExcludedFromAnalysis = workout.isExcludedFromAnalysis
                        existing.companionNames = workout.companionNames
                        existing.createdAt = workout.createdAt
                        existing.userTitle = workout.userTitle
                        existing.userDescription = workout.userDescription
                        existing.sharingVisibilityRaw = workout.sharingVisibilityRaw
                        existing.isBookmarked = workout.isBookmarked
                        existing.deviceName = workout.deviceName
                        existing.locationName = workout.locationName
                        existing.preferredWorkoutID = workout.preferredWorkoutID
                        existing.keepSeparate = workout.keepSeparate
                        existing.resolutionRequestID = workout.resolutionRequestID
                    }
                    else { context.insert(UnifiedWorkoutPersistenceMapper().makeRecord(from: workout)) }
                    // Older clients omit the optional detail payload. Preserve
                    // known detail when applying such a summary-only update.
                    if let incoming = payload?.telemetry {
                        guard incoming.workoutID == id else { throw HealthCloudError.invalidPayload }
                        let target = try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.id == id })).first
                        target?.telemetryData = try JSONEncoder().encode(incoming.validated(for: workout))
                    }
                }
            case .route:
                guard let id = UUID(uuidString: key), deleted || payload?.route?.workoutId == id else {
                    throw HealthCloudError.invalidPayload
                }
                let records = try context.fetch(FetchDescriptor<PersistedWorkoutRoute>(predicate: #Predicate { $0.workoutId == id }))
                records.forEach { context.delete($0) }
                if !deleted, let route = payload?.route { context.insert(route.makeRecord()) }
            case .checkIn:
                guard let id = UUID(uuidString: key), deleted || payload?.checkIn?.id == id else {
                    throw HealthCloudError.invalidPayload
                }
                let records = try context.fetch(FetchDescriptor<CheckInRecord>(predicate: #Predicate { $0.id == id }))
                records.forEach { context.delete($0) }
                if !deleted, let checkIn = payload?.checkIn { context.insert(checkIn.makeRecord()) }
            case .recoverySnapshot:
                guard let seconds = TimeInterval(key) else { throw HealthCloudError.invalidPayload }
                let date = Date(timeIntervalSince1970: seconds)
                guard deleted || payload?.snapshot?.date == date else { throw HealthCloudError.invalidPayload }
                let records = try context.fetch(FetchDescriptor<DailyRecoverySnapshotRecord>(predicate: #Predicate { $0.date == date }))
                records.forEach { context.delete($0) }
                if !deleted, let snapshot = payload?.snapshot { context.insert(snapshot.makeRecord()) }
            }
        }
    }
}
