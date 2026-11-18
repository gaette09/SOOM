import Foundation
import SwiftData

/// Local-only owner read model. This never publishes, changes visibility, or
/// writes a canonical alias. Alias membership comes from the Activity engine.
struct OwnerWorkoutFeedProjection {
    struct Entry {
        let canonicalID: UUID
        let sourceIDs: Set<UUID>
        let item: FeedItem
        let localItem: FeedItem
        /// Preserve provenance for every preexisting post. These are never
        /// deleted or combined into a made-up comment/reaction post identity.
        let existingServerItems: [FeedItem]
    }

    struct Snapshot {
        let ownerID: UUID
        let scopeID: String
        let entries: [Entry]

        /// Caller must pass freshly authorized server items for this account.
        /// Only explicit source membership suppresses a local duplicate; no
        /// timestamp heuristic is used to discard an unrelated server card.
        func merging(serverItems: [FeedItem], currentOwnerID: UUID?, currentScopeID: String) -> [FeedItem] {
            guard currentOwnerID == ownerID, currentScopeID == scopeID else { return [] }
            // A prior projection is not evidence for the current snapshot.
            let serverItems = serverItems.map { item in
                var fresh = item; fresh.verifiedOwnerStartDate = nil; return fresh
            }
            let aliases = entries.reduce(into: Set<UUID>()) { $0.formUnion($1.sourceIDs) }
            let unmatched = serverItems.filter {
                !($0.authorId == ownerID && $0.sourceWorkoutId.map(aliases.contains) == true)
            }
            // The prior normalization may already contain every local owner
            // card. Filter these once, not N times for N local entries.
            // Only fresh remote items supplied for this merge are considered.
            let ownerRemoteItems = serverItems.filter { !$0.isLocalDraft && $0.authorId == ownerID }
            let ownerItems = entries.map { entry in
                let current = ownerRemoteItems.filter {
                    $0.sourceWorkoutId.map(entry.sourceIDs.contains) == true
                }.sorted { a, b in
                    let first = a.sourceWorkoutId == entry.canonicalID
                    let second = b.sourceWorkoutId == entry.canonicalID
                    if first != second { return first }
                    return a.id.uuidString < b.id.uuidString
                }
                // Never resurrect a stale remote snapshot after its fresh
                // authorized lookup disappears; owner local activity remains.
                guard var matched = current.first else { return entry.localItem }
                if let start = entry.localItem.activityDate, start.timeIntervalSince1970.isFinite, start != (matched.activityDate ?? matched.createdAt) {
                    matched.verifiedOwnerStartDate = start
                }
                return matched
            }
            return (ownerItems + unmatched).sorted(by: FeedDisplayOrder.newestFirst)
        }
    }

    static func make(workouts: [UnifiedWorkout], ownerID: UUID, scopeID: String,
                     serverItems: [FeedItem] = [], authorName: String = "나") -> Snapshot {
        let trace = LoadTrace("feed-owner-group")
        let groups = UnifiedWorkoutDeduplicationEngine().canonicalGroups(workouts)
        trace.mark("canonical-group-complete")
        let entries = groups.map { group in
            let aliases = Set(group.sourceWorkouts.map(\.id))
            let existing = serverItems.filter {
                !$0.isLocalDraft && $0.authorId == ownerID && $0.sourceWorkoutId.map(aliases.contains) == true
            }.sorted { a, b in
                // Keep pinned identity when present, then deterministic post ID.
                let first = a.sourceWorkoutId == group.workout.id
                let second = b.sourceWorkoutId == group.workout.id
                if first != second { return first }
                return a.id.uuidString < b.id.uuidString
            }
            let local = localItem(group.workout, ownerID: ownerID, authorName: authorName)
            return Entry(canonicalID: group.workout.id, sourceIDs: aliases,
                         item: existing.first ?? local, localItem: local, existingServerItems: existing)
        }
        trace.mark("local-card-build-complete")
        return Snapshot(ownerID: ownerID, scopeID: scopeID, entries: entries)
    }

    /// Read the exact same account-scoped records and canonical engine as
    /// ActivityCalendarView, including old/private/offline records. There is no
    /// date cutoff and no implicit external disclosure.
    @MainActor
    static func read(context: ModelContext, storage: HealthAccountStorageController,
                     expectedOwnerID: UUID, expectedScopeID: String,
                     serverItems: [FeedItem] = [], authorName: String = "나") throws -> Snapshot? {
        guard storage.userID == expectedOwnerID, storage.scopeID == expectedScopeID,
              context.container === storage.container, !HealthCloudJournal.isRetired(context) else { return nil }
        let trace = LoadTrace("feed-owner-local-read")
        let records = try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>(sortBy: [SortDescriptor(\.startDate, order: .reverse)]))
        trace.mark("fetch-complete-records-\(records.count)")
        let workouts = records.map { UnifiedWorkoutPersistenceMapper().makeWorkout(from: $0) }
        trace.mark("scalar-map-complete")
        guard storage.userID == expectedOwnerID, storage.scopeID == expectedScopeID,
              context.container === storage.container, !HealthCloudJournal.isRetired(context) else { return nil }
        return make(workouts: workouts, ownerID: expectedOwnerID, scopeID: expectedScopeID,
                    serverItems: serverItems, authorName: authorName)
    }

    private static func localItem(_ workout: UnifiedWorkout, ownerID: UUID, authorName: String) -> FeedItem {
        let distance = workout.distanceMeters.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let seconds = workout.durationSeconds.isFinite ? max(0, workout.durationSeconds) : 0
        let minutes = Int(min(seconds / 60, Double(Int.max / 60)))
        let card = ShareableWorkoutCardModel(
            id: workout.id, workoutType: workout.workoutType, title: workout.displayTitle,
            distanceText: distance.map { String(format: "%.1f km", $0 / 1_000) } ?? "거리 없음",
            durationText: minutes >= 60 ? "\(minutes / 60)시간 \(minutes % 60)분" : "\(minutes)분",
            averagePaceText: FeedCardFormatting.movement(sport: workout.workoutType, distance: distance, seconds: seconds, pace: nil),
            primaryMessage: "활동에 저장된 본인 운동이에요.", growthMessage: "이 기기에서 본인에게 표시됩니다.",
            recoveryMessage: "", footerText: "SOOM · 본인 운동", visibility: .privateOnly,
            staticRoutePreview: StaticRoutePreview(imageURL: nil, bounds: nil, routeExists: false,
                fallbackStyle: StaticRouteFallbackStyle(workoutType: workout.workoutType)))
        return FeedItem(id: workout.id, authorName: authorName, authorHandle: nil, authorId: ownerID,
                        isLocalDraft: true, isOwnerLocalWorkout: true, createdAt: workout.createdAt,
                        itemType: .workoutSession, visibility: .privateOnly, cardData: .workoutSession(card),
                        sourceWorkoutId: workout.id, caption: nil, activityContext: workout.displayTitle,
                        contextLabels: [FeedContextLabel(title: "본인 운동", icon: nil)],
                        activityDate: workout.startDate, deviceName: workout.deviceName ?? workout.feedSourceLabel,
                        workoutDistanceMeters: distance, workoutDurationSeconds: seconds)
    }
}


/// A local-only memo, scoped to one refresh operation. Never holds server
/// authority: the caller merges only freshly supplied server items each time.
/// No cross-return cache is used until all local mutation paths are proven.
@MainActor
final class FeedOwnerProjectionOperationMemo<Key: Equatable, Value> {
    private var operation: UUID?
    private var entry: (key: Key, value: Value)?
    func begin() -> UUID {
        let token = UUID()
        operation = token; entry = nil
        return token
    }
    func end(_ token: UUID) {
        guard operation == token else { return }
        operation = nil; entry = nil
    }
    func invalidate() { entry = nil }
    func value(for key: Key, load: () throws -> Value?) rethrows -> Value? {
        if operation != nil, let entry, entry.key == key { return entry.value }
        // Clear before loading so absence/error never leaves an old value.
        entry = nil
        let value = try load()
        if operation != nil, let value { entry = (key, value) }
        return value
    }
}

struct FeedOwnerProjectionOperationKey: Equatable {
    let owner: UUID
    let scope: String
    let accountGeneration: Int
    let dataRevision: Int
    let container: ObjectIdentifier
    let context: ObjectIdentifier
}
