import Foundation
import SwiftData
import Network

@MainActor
final class HealthAccountStorageController: ObservableObject {
    @Published private(set) var container: ModelContainer
    @Published private(set) var userID: UUID?
    @Published private(set) var cloudConsentGranted = false
    @Published private(set) var isSyncing = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var conflictCount = 0
    @Published private(set) var invalidRecordCount = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var dataRevision = 0
    var scopeID: String { userID?.uuidString.lowercased() ?? "guest" }
    var scopeDirectory: URL { baseDirectory.appendingPathComponent(scopeID, isDirectory: true) }
    var autoPublishImportedWorkouts: Bool {
        guard userID != nil else { return false }
        if userID == ReviewDemoMode.userID { return UserDefaults.standard.object(forKey: "SOOM.autoPublishImportedWorkouts.\(scopeID)") as? Bool ?? true }
        guard defaultWorkoutAudience != .privatePost else { return false }
        return UserDefaults.standard.object(forKey: "SOOM.autoPublishImportedWorkouts.\(scopeID)") as? Bool ?? true
    }
    /// Local choice only schedules new imports; server revalidation authorizes publication.
    var defaultWorkoutAudience: FeedPostVisibility {
        guard userID != nil else { return .privatePost }
        if userID == ReviewDemoMode.userID { return .publicPost }
        return (UserDefaults.standard.string(forKey: "SOOM.workoutAudience.v1.\(scopeID)")
            .flatMap(FeedPostVisibility.init(rawValue:))).flatMap { $0 == .mutual ? nil : $0 } ?? .privatePost
    }
    func setAutoPublishImportedWorkouts(_ enabled: Bool) {
        guard userID != nil else { return }
        UserDefaults.standard.set(enabled, forKey: "SOOM.autoPublishImportedWorkouts.\(scopeID)")
        objectWillChange.send()
    }

    static var schema: Schema {
        Schema([CheckInRecord.self, DailyRecoverySnapshotRecord.self,
                UnifiedWorkoutRecord.self, PersistedWorkoutRoute.self, HealthCloudOutboxRecord.self])
    }
    private let guestContainer: ModelContainer
    private let baseDirectory: URL
    private let remote: (any HealthCloudRemote)?
    private let inMemory: Bool
    private let automaticallySync: Bool
    private var accountContainers: [UUID: ModelContainer] = [:]
    private var generation = 0
    private var activeSyncID: UUID?
    private var anotherSyncRequested = false
    private var commitObserver: NSObjectProtocol?
    private var networkMonitor: NWPathMonitor?

    init(remote: (any HealthCloudRemote)? = nil, baseDirectory: URL? = nil,
         guestContainer: ModelContainer? = nil, inMemory: Bool = false,
         monitorNetwork: Bool = true, automaticallySync: Bool = true) throws {
        self.remote = remote
        self.inMemory = inMemory
        self.automaticallySync = automaticallySync
        self.baseDirectory = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HealthAccounts", isDirectory: true)
        // Keep the default store URL for legacy/guest data. Adding the outbox
        // model is additive; existing health fields and records are preserved.
        let guest = try guestContainer ?? ModelContainer(for: Self.schema,
            configurations: [ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)])
        self.guestContainer = guest
        self.container = guest
        if !inMemory {
            try Self.protectDirectory(self.baseDirectory)
            if let configuration = guest.configurations.first, !configuration.isStoredInMemoryOnly { try Self.protectStoreFiles(configuration.url) }
        }
        commitObserver = NotificationCenter.default.addObserver(forName: HealthCloudJournal.didCommit,
            object: nil, queue: .main) { [weak self] notification in
                let owner = notification.object as? UUID
                Task { @MainActor [weak self] in
                    guard let self, self.userID == owner else { return }
                    try? self.refreshCounts()
                    guard self.automaticallySync else { return }
                    self.anotherSyncRequested = true
                    await self.syncNow()
                }
            }
        if monitorNetwork && !inMemory {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in await self?.syncNow() }
            }
            monitor.start(queue: DispatchQueue(label: "SOOM.HealthCloudConnectivity"))
            networkMonitor = monitor
        }
    }

    deinit {
        if let commitObserver { NotificationCenter.default.removeObserver(commitObserver) }
        networkMonitor?.cancel()
    }

    /// Root must mask the old subtree if opening the new database throws.
    /// No old context is rebound: delayed saves remain in their original account.
    func switchAccount(userID: UUID?) throws {
        guard self.userID != userID else { return }
        generation += 1
        activeSyncID = nil
        isSyncing = false
        anotherSyncRequested = false
        errorMessage = nil
        cloudConsentGranted = false
        lastSyncAt = nil
        let next: ModelContainer
        if let userID {
            if let cached = accountContainers[userID] { next = cached }
            else {
                let configuration: ModelConfiguration
                if inMemory {
                    configuration = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                } else {
                    let directory = baseDirectory.appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
                    try Self.protectDirectory(directory)
                    configuration = ModelConfiguration(schema: Self.schema,
                        url: directory.appendingPathComponent("health.store"), cloudKitDatabase: .none)
                }
                next = try ModelContainer(for: Self.schema, configurations: [configuration])
                if !inMemory { try Self.protectStoreFiles(configuration.url) }
                HealthCloudJournal.register(next, userID: userID)
                accountContainers[userID] = next
            }
            HealthCloudJournal.register(next, userID: userID)
        } else { next = guestContainer }
        self.userID = userID
        self.container = next
        cloudConsentGranted = try metadata("consent", context: next.mainContext)?.payload == Data([1])
        dataRevision += 1
        try refreshCounts()
    }

    func setCloudConsent(_ granted: Bool) throws {
        guard userID != nil else { return }
        generation += 1
        activeSyncID = nil
        isSyncing = false
        let context = container.mainContext
        let entry = try makeMetadata("consent", context: context)
        entry.payload = Data([granted ? 1 : 0])
        try context.save()
        cloudConsentGranted = granted
        errorMessage = nil
        if granted && automaticallySync { Task { await self.syncNow() } }
    }

    /// The explicit UI action copies legacy guest records once into a chosen
    /// account. Claim-before-copy permits safe retry after interruption, and
    /// prevents later B login from claiming A's legacy history. Guest originals
    /// stay local until the user separately resets them.
    func importGuestData(expectedUserID: UUID) throws {
        guard userID == expectedUserID, cloudConsentGranted else { throw HealthCloudError.accountChanged }
        let guest = guestContainer.mainContext
        let claim = try makeMetadata("guestClaim", context: guest)
        let owner = Data(expectedUserID.uuidString.lowercased().utf8)
        guard claim.payload == nil || claim.payload == owner else { throw HealthCloudError.guestImportClaimed }
        claim.payload = owner
        try guest.save()
        let destination = container.mainContext
        // Each key is imported at most once. A later explicit import may add
        // new guest records without overwriting account edits or tombstones.
        for value in try guest.fetch(FetchDescriptor<UnifiedWorkoutRecord>()) {
            try importPayload(.workout, key: value.id.uuidString.lowercased(),
                payload: HealthCloudPayload(workout: UnifiedWorkoutPersistenceMapper().makeWorkout(from: value),
                    telemetry: try value.telemetryData.map { try JSONDecoder().decode(WorkoutTelemetry.self, from: $0) }), context: destination)
        }
        for value in try guest.fetch(FetchDescriptor<PersistedWorkoutRoute>()) {
            try importPayload(.route, key: value.workoutId.uuidString.lowercased(),
                payload: HealthCloudPayload(route: .init(value)), context: destination)
        }
        for value in try guest.fetch(FetchDescriptor<CheckInRecord>()) {
            try importPayload(.checkIn, key: value.id.uuidString.lowercased(),
                payload: HealthCloudPayload(checkIn: .init(value)), context: destination)
        }
        for value in try guest.fetch(FetchDescriptor<DailyRecoverySnapshotRecord>()) {
            try importPayload(.recoverySnapshot, key: HealthCloudJournal.snapshotKey(value.date),
                payload: HealthCloudPayload(snapshot: .init(value)), context: destination)
        }
        let completed = try makeMetadata("guestImportComplete", context: destination)
        completed.payload = Data([1])
        try destination.save()
        dataRevision += 1
        try refreshCounts()
        if automaticallySync { Task { await self.syncNow() } }
    }

    func syncNow() async {
        guard !ReviewDemoMode.isActive else { return }
        guard let owner = userID, cloudConsentGranted else { return }
        guard let remote else { errorMessage = HealthCloudError.unavailable.localizedDescription; return }
        guard activeSyncID == nil else { anotherSyncRequested = true; return }
        let expectedGeneration = generation
        let operation = UUID()
        let context = container.mainContext
        activeSyncID = operation
        isSyncing = true
        anotherSyncRequested = false
        errorMessage = nil
        var completed = false
        var committedContentChanges = false
        defer {
            if activeSyncID == operation {
                // One content notification per sync, including partial success
                // followed by failure. Never notify a replacement account.
                if committedContentChanges, userID == owner, generation == expectedGeneration {
                    dataRevision += 1
                }
                activeSyncID = nil
                isSyncing = false
                try? refreshCounts()
                if completed && anotherSyncRequested {
                    anotherSyncRequested = false
                    Task { await self.syncNow() }
                }
            }
        }
        do {
            // Pull first so an offline edit sees a newer server version before
            // upload; mismatches preserve the unsent local payload as conflict.
            let cursor = try makeMetadata("cursor", context: context)
            while true {
                let rows = try await remote.pull(after: cursor.serverVersion, expectedUserID: owner)
                try assertCurrent(owner, generation: expectedGeneration)
                let preparedRows = try await HealthCloudJournal.prepareBatch(rows)
                try assertCurrent(owner, generation: expectedGeneration)
                try Task.checkCancellation()
                var appliedPullPayload = false
                for prepared in preparedRows {
                    let row = prepared.row
                    if try receiveOrQuarantine(row, context: context, prepared: prepared) { appliedPullPayload = true }
                    cursor.serverVersion = max(cursor.serverVersion, row.revision)
                }
                try context.save()
                if appliedPullPayload { committedContentChanges = true }
                if rows.isEmpty { break }
            }
            var pendingQuery = FetchDescriptor<HealthCloudOutboxRecord>(
                predicate: #Predicate { $0.pending && !$0.conflicted },
                sortBy: [SortDescriptor(\HealthCloudOutboxRecord.kind, order: .reverse)])
            pendingQuery.fetchLimit = 1
            // Fetch a single pending payload at a time; many large route blobs
            // must not accumulate in the synchronization task's pending array.
            while let entry = try context.fetch(pendingQuery).first {
                var appliedPushPayload = false
                try assertCurrent(owner, generation: expectedGeneration)
                let mutation = HealthCloudMutation(kind: entry.kind, recordKey: entry.recordKey,
                    payload: entry.payload, isDeleted: entry.isTombstone,
                    baseVersion: entry.serverVersion, mutationID: entry.mutationID)
                let result = try await remote.push(mutation, expectedUserID: owner)
                try assertCurrent(owner, generation: expectedGeneration)
                guard result.kind == mutation.kind, result.recordKey == mutation.recordKey else {
                    throw HealthCloudError.invalidPayload
                }
                if result.accepted == true && entry.mutationID != mutation.mutationID && result.version > mutation.baseVersion + 1 {
                    // A repeated receipt can return a newer remote version. It
                    // cannot be the base for an edit made while this RPC awaited.
                    markConflict(entry, row: result)
                } else if result.accepted == true {
                    entry.serverVersion = result.version
                    // A newer local edit during await must remain pending. It
                    // rebases on the acknowledged version and gets another turn.
                    if entry.mutationID == mutation.mutationID {
                        entry.pending = false
                        entry.payload = result.payloadData
                        entry.isTombstone = result.isDeleted
                        try HealthCloudJournal.apply(kind: result.kind, key: result.recordKey,
                            data: result.payloadData, deleted: result.isDeleted, context: context)
                        appliedPushPayload = true
                    } else { anotherSyncRequested = true }
                } else { markConflict(entry, row: result) }
                try context.save()
                if appliedPushPayload { committedContentChanges = true }
            }
            try refreshCounts()
            if conflictCount > 0 { errorMessage = HealthCloudError.conflict.localizedDescription }
            else if invalidRecordCount > 0 { errorMessage = "일부 기록의 형식을 확인하지 못해 따로 보관했어요. 다른 기록은 복원했습니다." }
            lastSyncAt = Date()
            // Successful empty pulls and already-applied receipts change sync
            // metadata, not workout content. Do not invalidate every feed card.
            completed = true
        } catch {
            context.rollback()
            if userID == owner && generation == expectedGeneration {
                errorMessage = (error as? HealthCloudError)?.localizedDescription ?? HealthCloudError.unavailable.localizedDescription
            }
        }
    }

    /// Use after remote account deletion (or an explicit device reset). Outbox
    /// payloads are health data too; clearing only the four UI stores is insufficient.
    func eraseCurrentScopeData(expectedUserID: UUID?, retireScope: Bool = false) throws {
        guard userID == expectedUserID else { throw HealthCloudError.accountChanged }
        generation += 1
        activeSyncID = nil
        isSyncing = false
        let context = container.mainContext
        try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<PersistedWorkoutRoute>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<CheckInRecord>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<DailyRecoverySnapshotRecord>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<HealthCloudOutboxRecord>()).forEach { context.delete($0) }
        try context.save()
        if retireScope {
            HealthCloudJournal.retire(container)
            UserDefaults.standard.removeObject(forKey: "SOOM.autoPublishImportedWorkouts.\(scopeID)")
        }
        cloudConsentGranted = false
        pendingCount = 0
        conflictCount = 0
        invalidRecordCount = 0
        dataRevision += 1
    }

    func resolveConflicts(expectedUserID: UUID, keepingLocal: Bool) async {
        guard userID == expectedUserID, cloudConsentGranted, activeSyncID == nil else { return }
        do {
            let context = container.mainContext
            for entry in try context.fetch(FetchDescriptor<HealthCloudOutboxRecord>()).filter({ $0.conflicted }) {
                entry.serverVersion = entry.conflictVersion
                if keepingLocal {
                    entry.pending = true
                    entry.mutationID = UUID()
                } else {
                    entry.payload = entry.conflictPayload
                    entry.isTombstone = entry.conflictDeleted
                    entry.pending = false
                    try HealthCloudJournal.apply(kind: entry.kind, key: entry.recordKey,
                        data: entry.payload, deleted: entry.isTombstone, context: context)
                }
                entry.conflicted = false
                entry.conflictPayload = nil
            }
            try context.save()
            dataRevision += 1
            try refreshCounts()
            await syncNow()
        } catch { errorMessage = HealthCloudError.unavailable.localizedDescription }
    }

    private func receiveOrQuarantine(_ row: HealthCloudRemoteRecord, context: ModelContext, prepared: HealthCloudJournal.PreparedRemoteRow? = nil) throws -> Bool {
        let quarantineKey = row.kind + ":" + row.recordKey
        do {
            if let prepared {
                guard prepared.valid else { throw HealthCloudError.invalidPayload }
            } else {
                try HealthCloudJournal.validate(kind: row.kind, key: row.recordKey, data: row.payloadData, deleted: row.isDeleted)
            }
        } catch {
            switch error {
            case HealthCloudError.invalidPayload, is DecodingError:
                let invalid = try HealthCloudJournal.find("_invalid", key: quarantineKey, context: context)
                    ?? HealthCloudOutboxRecord(kind: "_invalid", recordKey: quarantineKey, payload: nil)
                if invalid.modelContext == nil { context.insert(invalid) }
                invalid.payload = try JSONEncoder().encode(row)
                invalid.pending = false
                invalid.serverVersion = row.version
                return false
            default: throw error
            }
        }
        let applied = try receive(row, context: context, prepared: prepared)
        if let invalid = try HealthCloudJournal.find("_invalid", key: quarantineKey, context: context) { context.delete(invalid) }
        return applied
    }

    private func receive(_ row: HealthCloudRemoteRecord, context: ModelContext, prepared: HealthCloudJournal.PreparedRemoteRow? = nil) throws -> Bool {
        let payloadData = prepared?.data ?? row.payloadData
        guard HealthCloudKind(rawValue: row.kind) != nil else { throw HealthCloudError.invalidPayload }
        let entry = try HealthCloudJournal.find(row.kind, key: row.recordKey, context: context)
            ?? HealthCloudOutboxRecord(kind: row.kind, recordKey: row.recordKey, payload: nil)
        if entry.modelContext == nil { entry.pending = false; context.insert(entry) }
        guard row.version > entry.serverVersion else { return false }
        if entry.pending {
            // This can also be a retry after the server committed but the
            // acknowledgment was lost. Compare payload before declaring conflict.
            if HealthCloudPayload.equivalent(entry.payload, payloadData) && entry.isTombstone == row.isDeleted {
                entry.serverVersion = row.version; entry.pending = false
            } else { markConflict(entry, row: row) }
            return false
        }
        if let prepared { try HealthCloudJournal.apply(prepared, context: context) }
        else { try HealthCloudJournal.apply(kind: row.kind, key: row.recordKey,
            data: payloadData, deleted: row.isDeleted, context: context) }
        entry.payload = payloadData
        entry.isTombstone = row.isDeleted
        entry.serverVersion = row.version
        entry.pending = false
        return true
    }
    private func markConflict(_ entry: HealthCloudOutboxRecord, row: HealthCloudRemoteRecord) {
        entry.conflicted = true
        entry.conflictPayload = row.payloadData
        entry.conflictVersion = row.version
        entry.conflictDeleted = row.isDeleted
    }
    private func assertCurrent(_ owner: UUID, generation: Int) throws {
        guard !ReviewDemoMode.isActive, userID == owner, self.generation == generation, cloudConsentGranted else { throw HealthCloudError.accountChanged }
    }
    private func refreshCounts() throws {
        guard userID != nil else { pendingCount = 0; conflictCount = 0; invalidRecordCount = 0; return }
        // Count in the store. Fetching model objects here hydrates every route /
        // telemetry payload while opening an existing account on the main actor.
        let context = container.mainContext
        pendingCount = try context.fetchCount(FetchDescriptor<HealthCloudOutboxRecord>(predicate: #Predicate {
            $0.pending && ($0.kind == "workout" || $0.kind == "route"
                || $0.kind == "checkIn" || $0.kind == "recoverySnapshot")
        }))
        conflictCount = try context.fetchCount(FetchDescriptor<HealthCloudOutboxRecord>(predicate: #Predicate { $0.conflicted }))
        invalidRecordCount = try context.fetchCount(FetchDescriptor<HealthCloudOutboxRecord>(predicate: #Predicate { $0.kind == "_invalid" }))
    }
    private static func protectDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try protectItem(directory)
    }
    private static func protectStoreFiles(_ storeURL: URL) throws {
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) { try protectItem(url) }
        }
    }
    private static func protectItem(_ original: URL) throws {
        var url = original
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }

    private func metadata(_ key: String, context: ModelContext) throws -> HealthCloudOutboxRecord? {
        try HealthCloudJournal.find("_metadata", key: key, context: context)
    }
    private func makeMetadata(_ key: String, context: ModelContext) throws -> HealthCloudOutboxRecord {
        if let existing = try metadata(key, context: context) { return existing }
        let value = HealthCloudOutboxRecord(kind: "_metadata", recordKey: key, payload: nil)
        value.pending = false
        context.insert(value)
        return value
    }
    private func importPayload(_ kind: HealthCloudKind, key: String, payload: HealthCloudPayload, context: ModelContext) throws {
        guard try HealthCloudJournal.find(kind.rawValue, key: key, context: context) == nil else { return }
        try HealthCloudJournal.apply(kind: kind.rawValue, key: key, data: payload.encoded(), deleted: false, context: context)
        try HealthCloudJournal.record(kind, key: key, payload: payload, context: context)
    }
}
