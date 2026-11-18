import Foundation
import Combine
import Supabase
import SwiftData

/// The reviewed build flag and verified server/profile lease are both required.
enum AccountActivitySyncReleaseGate { static let productionReady = ProfileOnlyPrivacyReleaseGate.productionReady }
enum AccountActivitySyncError: Error, Equatable {
    case disabled, invalidPayload, missingDistance, unauthorized, accountChanged, busy
    case pendingConflict, revisionConflict, restoreForbidden, invalidReceipt, summaryNotAuthorized
}
struct AccountActivitySyncContext: Equatable {
    let ownerID: UUID
    let scopeID: String
    let generation: Int
    let retired: Bool
}
/// A reviewed staging authorization is distinct from HealthKit/cloud-storage consent.
struct AccountActivityStagingAuthorization: Equatable {
    let ownerID: UUID
    let evidenceReference: String
    let earliestActivity: Date
    let expiresAt: Date
    let permitsOwnerPrivateStaging: Bool
}
struct AccountActivityStagePayload: Codable, Equatable {
    let p_canonical_id: UUID
    let p_source_ids: [UUID]
    let p_expected_revision: Int64
    let p_sport: String
    let p_activity_at: Date
    let p_duration_seconds: Int
    let p_distance_meters: Double?
    let p_deleted: Bool

    enum CodingKeys: String, CodingKey {
        case p_canonical_id, p_source_ids, p_expected_revision, p_sport, p_activity_at
        case p_duration_seconds, p_distance_meters, p_deleted
    }
    func encode(to encoder: Encoder) throws {
        var c=encoder.container(keyedBy:CodingKeys.self)
        try c.encode(p_canonical_id,forKey:.p_canonical_id); try c.encode(p_source_ids,forKey:.p_source_ids)
        try c.encode(p_expected_revision,forKey:.p_expected_revision); try c.encode(p_sport,forKey:.p_sport)
        try c.encode(p_activity_at,forKey:.p_activity_at); try c.encode(p_duration_seconds,forKey:.p_duration_seconds)
        if let distance=p_distance_meters { try c.encode(distance,forKey:.p_distance_meters) }
        else { try c.encodeNil(forKey:.p_distance_meters) }
        try c.encode(p_deleted,forKey:.p_deleted)
    }
    func validate(now: Date) throws {
        guard p_expected_revision >= 0, p_expected_revision < Int64.max,
              !p_source_ids.isEmpty, p_source_ids.count <= 32,
              Set(p_source_ids).count == p_source_ids.count, p_source_ids.contains(p_canonical_id),
              ["running","cycling","walking","swimming","hiking","strength","yoga","other"].contains(p_sport),
              p_activity_at.timeIntervalSince1970.isFinite, p_activity_at <= now,
              (0...604800).contains(p_duration_seconds),
              p_distance_meters.map({ $0.isFinite && (0...10000000).contains($0) }) ?? true
        else { throw AccountActivitySyncError.invalidPayload }
    }
}
struct AccountActivityV2StageParameters: Encodable {
    let payload:AccountActivityStagePayload
    let profileRevision:Int64
    enum Keys:String,CodingKey {case p_expected_profile_revision}
    func encode(to encoder:Encoder) throws {
        try payload.encode(to:encoder)
        var values=encoder.container(keyedBy:Keys.self)
        try values.encode(profileRevision,forKey:.p_expected_profile_revision)
    }
}
struct AccountActivityStageReceipt: Codable, Equatable {
    let version: Int
    let card_id: UUID
    let canonical_id: UUID
    let revision: Int64
    let staged: Bool
    let release_ready: Bool
    var summary_authorized: Bool? = nil
}
struct AccountActivityStageLookup: Codable, Equatable {
    let owner_id: UUID
    let card_id: UUID
    let canonical_id: UUID
    let source_ids: [UUID]
    let revision: Int64
    let sport: String
    let activity_at: Date
    let duration_seconds: Int
    let distance_meters: Double?
    let deleted: Bool
    var summary_authorized: Bool? = nil

    func confirms(_ payload: AccountActivityStagePayload, owner: UUID) -> Bool {
        owner_id == owner && canonical_id == payload.p_canonical_id
            && revision == payload.p_expected_revision + 1
            && Set(source_ids).isSuperset(of: Set(payload.p_source_ids))
            && sport == payload.p_sport && activity_at == payload.p_activity_at
            && duration_seconds == payload.p_duration_seconds && distance_meters == payload.p_distance_meters
            && deleted == payload.p_deleted
    }
}
@MainActor protocol AccountActivityStageTransport {
    var context: AccountActivitySyncContext? { get }
    func lookup(canonicalID: UUID) async throws -> AccountActivityStageLookup?
    func lookupSource(sourceID: UUID) async throws -> AccountActivityStageLookup?
    func stage(_ payload: AccountActivityStagePayload) async throws -> AccountActivityStageReceipt
}

extension AccountActivityStageTransport {
    func lookupSource(sourceID:UUID) async throws -> AccountActivityStageLookup? {
        throw AccountActivitySyncError.invalidPayload
    }
}

struct AccountActivityStageIntent: Codable, Equatable {
    let id: UUID
    let ownerID: UUID
    let evidenceReference: String
    let payload: AccountActivityStagePayload
    var outcomeUncertain: Bool
}
/// Explicit caller-local location, no automatic access to health/source stores.
@MainActor final class AccountActivityStageOutbox {
    private let directory: URL
    private static var activePaths = Set<String>()
    func acquire(owner: UUID) throws {
        guard Self.activePaths.insert(path(owner).standardizedFileURL.path).inserted else { throw AccountActivitySyncError.busy }
    }
    func release(owner: UUID) { Self.activePaths.remove(path(owner).standardizedFileURL.path) }
    init(directory: URL) { self.directory = directory }
    private func path(_ owner: UUID) -> URL { directory.appendingPathComponent(owner.uuidString.lowercased()+".json") }
    func entries(owner: UUID) throws -> [AccountActivityStageIntent] {
        let url = path(owner)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard data.count <= 8_000_000 else { throw AccountActivitySyncError.invalidPayload }
        let rows = try JSONDecoder().decode([AccountActivityStageIntent].self, from: data)
        guard rows.allSatisfy({ $0.ownerID == owner }), Set(rows.map(\.id)).count == rows.count,
              Set(rows.map(\.payload.p_canonical_id)).count == rows.count else { throw AccountActivitySyncError.invalidPayload }
        return rows
    }
    func save(_ rows: [AccountActivityStageIntent], owner: UUID) throws {
        guard rows.count <= 10000, rows.allSatisfy({ $0.ownerID == owner }) else { throw AccountActivitySyncError.invalidPayload }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(rows)
        guard data.count <= 8_000_000 else { throw AccountActivitySyncError.invalidPayload }
        try data.write(to: path(owner), options: .atomic)
    }
}

@MainActor final class AccountActivitySyncCandidate {
    private let transport: any AccountActivityStageTransport
    private let outbox: AccountActivityStageOutbox
    private let authorization: () -> AccountActivityStagingAuthorization?
    private let fixture: Bool
    private let clock: () -> Date
    private var running = false
    init(transport: any AccountActivityStageTransport, outbox: AccountActivityStageOutbox,
         authorization: @escaping () -> AccountActivityStagingAuthorization?, clock: @escaping () -> Date = Date.init) {
        self.transport=transport; self.outbox=outbox; self.authorization=authorization; self.clock=clock; fixture=false
    }
    #if DEBUG
    init(fixtureTransport: any AccountActivityStageTransport, outbox: AccountActivityStageOutbox,
         authorization: @escaping () -> AccountActivityStagingAuthorization?, clock: @escaping () -> Date = Date.init) {
        transport=fixtureTransport; self.outbox=outbox; self.authorization=authorization; self.clock=clock; fixture=true
    }
    #endif
    fileprivate struct Lease {
        let context: AccountActivitySyncContext
        let grant: AccountActivityStagingAuthorization
    }
    fileprivate func captureLease() throws -> Lease {
        try Task.checkCancellation()
        guard fixture || AccountActivitySyncReleaseGate.productionReady else { throw AccountActivitySyncError.disabled }
        guard let context=transport.context, !context.retired, context.generation >= 0,
              context.scopeID == context.ownerID.uuidString.lowercased(),
              let grant=authorization(), grant.ownerID==context.ownerID, grant.permitsOwnerPrivateStaging,
              !grant.evidenceReference.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              grant.expiresAt > clock() else { throw AccountActivitySyncError.unauthorized }
        return Lease(context:context,grant:grant)
    }
    fileprivate func checkLease(_ lease: Lease) throws {
        try Task.checkCancellation()
        guard transport.context==lease.context else { throw AccountActivitySyncError.accountChanged }
        guard authorization()==lease.grant, lease.grant.expiresAt>clock() else { throw AccountActivitySyncError.unauthorized }
    }
    private func validate(_ payload: AccountActivityStagePayload, now: Date) throws -> (AccountActivitySyncContext, AccountActivityStagingAuthorization) {
        guard fixture || AccountActivitySyncReleaseGate.productionReady else { throw AccountActivitySyncError.disabled }
        try payload.validate(now: now)
        guard let context=transport.context, !context.retired, context.generation >= 0,
              context.scopeID == context.ownerID.uuidString.lowercased(),
              let grant=authorization(), grant.ownerID==context.ownerID, grant.permitsOwnerPrivateStaging,
              !grant.evidenceReference.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              grant.expiresAt > now, grant.expiresAt > clock(), grant.earliestActivity <= payload.p_activity_at
        else { throw AccountActivitySyncError.unauthorized }
        return (context,grant)
    }
    func enqueue(_ payload: AccountActivityStagePayload, now: Date=Date()) throws {
        let (context,grant)=try validate(payload,now:now)
        var rows=try outbox.entries(owner:context.ownerID)
        if let prior=rows.first(where:{$0.payload.p_canonical_id==payload.p_canonical_id}) {
            guard prior.payload==payload, prior.evidenceReference==grant.evidenceReference else { throw AccountActivitySyncError.pendingConflict }
            return
        }
        rows.append(.init(id:UUID(),ownerID:context.ownerID,evidenceReference:grant.evidenceReference,payload:payload,outcomeUncertain:false))
        try outbox.save(rows,owner:context.ownerID)
    }
    /// Exact server alias resolution, not a timestamp/name heuristic. Used only
    /// for explicit tombstones and proven single-card representative continuity.
    fileprivate func lookupDeletedSource(_ sourceID:UUID) async throws -> AccountActivityStageLookup? {
        let lease=try captureLease()
        let row=try await transport.lookupSource(sourceID:sourceID)
        try checkLease(lease)
        if let row {
            guard row.owner_id==lease.context.ownerID,row.source_ids.contains(sourceID),
                  row.source_ids.contains(row.canonical_id),row.revision>0 else {throw AccountActivitySyncError.invalidReceipt}
        }
        return row
    }
    /// Preserve a proven single server card when Activity chooses another local
    /// representative. Never infer identity from dates, metrics or names.
    fileprivate func resolveExistingCanonical(_ input:AccountActivityStageInput,now:Date) async throws -> AccountActivityStageInput {
        _=try validate(input.payload(expectedRevision:0),now:now)
        guard !input.deleted else{return input}
        let sources=Set(input.sourceIDs)
        var established:AccountActivityStageLookup?
        for source in input.sourceIDs.sorted(by:{$0.uuidString<$1.uuidString}) {
            guard let row=try await lookupDeletedSource(source) else{continue}
            guard !row.deleted,Set(row.source_ids).isSubset(of:sources),sources.contains(row.canonical_id) else {
                throw AccountActivitySyncError.pendingConflict
            }
            if let established {
                guard established.canonical_id==row.canonical_id,established.card_id==row.card_id,
                      established.revision==row.revision,Set(established.source_ids)==Set(row.source_ids) else {
                    throw AccountActivitySyncError.pendingConflict
                }
            } else {established=row}
        }
        guard let established else{return input}
        return .init(canonicalID:established.canonical_id,sourceIDs:input.sourceIDs,sport:input.sport,
                     activityAt:input.activityAt,durationSeconds:input.durationSeconds,distanceMeters:input.distanceMeters,deleted:false)
    }
    /// Plans a fresh canonical snapshot only after pending uncertainty is settled.
    /// Sources must already be canonicalized by the Activity engine; no heuristic merge.
    func enqueueLatest(_ input: AccountActivityStageInput, now: Date=Date()) async throws -> Bool {
        let base=input.payload(expectedRevision:0)
        let (context,grant)=try validate(base,now:now)
        guard !running else { throw AccountActivitySyncError.busy }
        if try outbox.entries(owner:context.ownerID).contains(where:{$0.payload.p_canonical_id==input.canonicalID}) {
            throw AccountActivitySyncError.pendingConflict
        }
        let prior: AccountActivityStageLookup?
        do { prior=try await transport.lookup(canonicalID:input.canonicalID) }
        catch {
            guard transport.context==context, authorization()==grant, grant.expiresAt>clock(), !Task.isCancelled else {
                throw AccountActivitySyncError.accountChanged
            }
            throw error
        }
        guard transport.context==context, authorization()==grant, grant.expiresAt>clock(), !Task.isCancelled else {
            throw AccountActivitySyncError.accountChanged
        }
        var aliases=Set(input.sourceIDs)
        if let prior {
            guard prior.owner_id==context.ownerID, prior.canonical_id==input.canonicalID, prior.revision>0 else {
                throw AccountActivitySyncError.invalidReceipt
            }
            guard !prior.deleted || input.deleted else { throw AccountActivitySyncError.restoreForbidden }
            aliases.formUnion(prior.source_ids)
            if Set(prior.source_ids)==aliases, prior.sport==input.sport, prior.activity_at==input.activityAt,
               prior.duration_seconds==input.durationSeconds, prior.distance_meters==input.distanceMeters,
               prior.deleted==input.deleted {
                if fixture || input.deleted || prior.summary_authorized == true { return false }
            }
        }
        let payload=AccountActivityStagePayload(p_canonical_id:input.canonicalID,
            p_source_ids:aliases.sorted{$0.uuidString<$1.uuidString}, p_expected_revision:prior?.revision ?? 0,
            p_sport:input.sport,p_activity_at:input.activityAt,p_duration_seconds:input.durationSeconds,
            p_distance_meters:input.distanceMeters,p_deleted:input.deleted)
        try enqueue(payload,now:now)
        return true
    }
    /// Reads first even after timeout/restart; never invents a new ID/revision.
    func flush(now: Date=Date()) async throws -> Int {
        try await flush(now:now, canonicalID:nil)
    }
    fileprivate func flush(now: Date, canonicalID: UUID?) async throws -> Int {
        guard !running else { throw AccountActivitySyncError.busy }
        guard fixture || AccountActivitySyncReleaseGate.productionReady else { throw AccountActivitySyncError.disabled }
        let lease=try captureLease()
        let owner=lease.context.ownerID
        try outbox.acquire(owner:owner)
        running=true; defer { running=false; outbox.release(owner:owner) }
        var completed=0
        for intent in try outbox.entries(owner:owner) where canonicalID == nil || intent.payload.p_canonical_id == canonicalID {
            try checkLease(lease)
            let (context,grant)=try validate(intent.payload,now:now)
            guard context==lease.context, grant==lease.grant else { throw AccountActivitySyncError.accountChanged }
            guard context.ownerID==owner, grant.evidenceReference==intent.evidenceReference else { throw AccountActivitySyncError.unauthorized }
            func check() throws {
                try checkLease(lease)
                guard !Task.isCancelled, transport.context==context, authorization()==grant, grant.expiresAt > clock() else { throw AccountActivitySyncError.accountChanged }
            }
            let prior: AccountActivityStageLookup?
            do { prior=try await transport.lookup(canonicalID:intent.payload.p_canonical_id) }
            catch { try check(); throw error }
            try check()
            if let prior {
                guard prior.owner_id==owner, prior.canonical_id==intent.payload.p_canonical_id,
                      prior.revision > 0 else { throw AccountActivitySyncError.invalidReceipt }
                if prior.confirms(intent.payload,owner:owner) {
                    if !fixture, !intent.payload.p_deleted, prior.summary_authorized != true { throw AccountActivitySyncError.summaryNotAuthorized }
                    try remove(intent); completed += 1; continue
                }
                guard !prior.deleted || intent.payload.p_deleted else { throw AccountActivitySyncError.restoreForbidden }
                guard prior.revision==intent.payload.p_expected_revision else { throw AccountActivitySyncError.revisionConflict }
            } else if intent.payload.p_expected_revision != 0 { throw AccountActivitySyncError.revisionConflict }
            // Persist uncertain before crossing transport boundary.
            try markUncertain(intent)
            let receipt: AccountActivityStageReceipt
            do { receipt=try await transport.stage(intent.payload) }
            catch { try check(); throw error }
            try check()
            guard receipt.version==(fixture ? 1 : 2), receipt.canonical_id==intent.payload.p_canonical_id,
                  receipt.revision==intent.payload.p_expected_revision+1, receipt.staged,
                  fixture ? !receipt.release_ready : receipt.release_ready,
                  prior.map({$0.card_id==receipt.card_id}) ?? true else { throw AccountActivitySyncError.invalidReceipt }
            if !fixture, !intent.payload.p_deleted, receipt.summary_authorized != true { throw AccountActivitySyncError.summaryNotAuthorized }
            try remove(intent); completed += 1
        }
        return completed
    }
    /// Isolates a bad/uncertain card without forgetting its durable intent. A
    /// revoked grant, account change, cancellation or worker collision stops all work.
    func flushIsolated(now: Date=Date()) async throws -> AccountActivitySyncReport {
        guard !running else { throw AccountActivitySyncError.busy }
        guard fixture || AccountActivitySyncReleaseGate.productionReady else { throw AccountActivitySyncError.disabled }
        let lease=try captureLease()
        var report=AccountActivitySyncReport()
        for intent in try outbox.entries(owner:lease.context.ownerID) {
            try checkLease(lease)
            do {
                report.completed += try await flush(now:now, canonicalID:intent.payload.p_canonical_id)
                try checkLease(lease)
            } catch {
                try checkLease(lease)
                try AccountActivitySyncReport.rethrowGlobal(error)
                report.failedCanonicalIDs.insert(intent.payload.p_canonical_id)
            }
        }
        return report
    }
    private func markUncertain(_ intent: AccountActivityStageIntent) throws {
        var rows=try outbox.entries(owner:intent.ownerID)
        guard let i=rows.firstIndex(where:{$0.id==intent.id && $0.payload==intent.payload}) else { throw AccountActivitySyncError.pendingConflict }
        rows[i].outcomeUncertain=true; try outbox.save(rows,owner:intent.ownerID)
    }
    private func remove(_ intent: AccountActivityStageIntent) throws {
        var rows=try outbox.entries(owner:intent.ownerID)
        rows.removeAll {$0.id==intent.id && $0.payload==intent.payload}
        try outbox.save(rows,owner:intent.ownerID)
    }
}

@MainActor struct SupabaseAccountActivityStageTransport: AccountActivityStageTransport {
    let client: SupabaseClient
    let currentContext: () -> AccountActivitySyncContext?
    let currentProfileRevision: () -> Int64?
    init(client:SupabaseClient,currentContext:@escaping ()->AccountActivitySyncContext?,
         currentProfileRevision:@escaping ()->Int64? = { nil }) {
        self.client=client;self.currentContext=currentContext;self.currentProfileRevision=currentProfileRevision
    }
    var context: AccountActivitySyncContext? { currentContext() }
    private func check() throws -> Int64 {
        guard AccountActivitySyncReleaseGate.productionReady, ProfileOnlyPrivacyReleaseGate.productionReady else { throw AccountActivitySyncError.disabled }
        guard let context, !context.retired, context.scopeID==context.ownerID.uuidString.lowercased(),
              context.generation >= 0, client.auth.currentSession?.user.id==context.ownerID,
              let revision=currentProfileRevision(),revision>0 else { throw AccountActivitySyncError.accountChanged }
        return revision
    }
    private struct Envelope: Decodable {
        let version: Int; let viewer_id: UUID; let row: AccountActivityStageLookup?
        let profile_revision:Int64;let release_ready: Bool;let summary_authorized:Bool
    }
    func lookup(canonicalID: UUID) async throws -> AccountActivityStageLookup? {
        let revision=try check(),expected=context
        struct Params: Encodable { let p_canonical_id: UUID }
        let result: Envelope = try await client.rpc("soom_activity_owner_lookup_candidate_v2",params:Params(p_canonical_id:canonicalID)).execute().value
        guard result.version==2,result.viewer_id==expected?.ownerID,result.release_ready,
              result.profile_revision==revision,try check()==revision,context==expected else { throw AccountActivitySyncError.invalidReceipt }
        var row=result.row;row?.summary_authorized=result.summary_authorized
        return row
    }
    func lookupSource(sourceID:UUID) async throws -> AccountActivityStageLookup? {
        let revision=try check(),expected=context
        struct Params:Encodable { let p_source_id:UUID }
        let result:Envelope=try await client.rpc("soom_activity_owner_source_lookup_candidate_v2",params:Params(p_source_id:sourceID)).execute().value
        guard result.version==2,result.viewer_id==expected?.ownerID,result.release_ready,
              result.profile_revision==revision,try check()==revision,context==expected,
              result.row.map({$0.source_ids.contains(sourceID)}) ?? true else { throw AccountActivitySyncError.invalidReceipt }
        var row=result.row;row?.summary_authorized=result.summary_authorized
        return row
    }
    func stage(_ payload: AccountActivityStagePayload) async throws -> AccountActivityStageReceipt {
        let revision=try check(),expected=context;try payload.validate(now:Date())
        struct Result:Decodable {
            let version:Int;let card_id:UUID;let canonical_id:UUID;let revision:Int64
            let staged:Bool;let release_ready:Bool;let profile_revision:Int64;let summary_authorized:Bool
        }
        let receipt:Result=try await client.rpc("soom_activity_stage_candidate_v2",params:AccountActivityV2StageParameters(payload:payload,profileRevision:revision)).execute().value
        guard receipt.version==2,receipt.profile_revision==revision,try check()==revision,context==expected else {throw AccountActivitySyncError.invalidReceipt}
        return .init(version:receipt.version,card_id:receipt.card_id,canonical_id:receipt.canonical_id,
            revision:receipt.revision,staged:receipt.staged,release_ready:receipt.release_ready,summary_authorized:receipt.summary_authorized)
    }
}


struct AccountActivityStageInput: Codable, Equatable {
    let canonicalID: UUID
    let sourceIDs: [UUID]
    let sport: String
    let activityAt: Date
    let durationSeconds: Int
    let distanceMeters: Double?
    let deleted: Bool
    /// Same grouping as Activity. Canonical identity changes are NOT guessed or
    /// merged here. The worker may retain one exact server identity only after
    /// verifying its entire alias set; multi-card merge/split remains pending.
    static func canonicalInputs(_ workouts:[UnifiedWorkout], now:Date=Date()) throws -> [Self] {
        try UnifiedWorkoutDeduplicationEngine().canonicalGroups(workouts).map { group in
            let workout=group.workout
            guard workout.durationSeconds.isFinite, workout.durationSeconds >= 0,
                  workout.durationSeconds <= 604800 else { throw AccountActivitySyncError.invalidPayload }
            let input=Self(canonicalID:workout.id,sourceIDs:group.sourceWorkouts.map(\.id).sorted{$0.uuidString<$1.uuidString},
                sport:workout.workoutType.rawValue,activityAt:workout.startDate,
                durationSeconds:Int(workout.durationSeconds.rounded(.down)),distanceMeters:workout.distanceMeters,deleted:false)
            try input.payload(expectedRevision:0).validate(now:now)
            return input
        }
    }
    /// Snapshot conversion is per canonical group, never per source alias. One
    /// malformed workout must not prevent unrelated valid records from queuing.
    static func canonicalBatch(_ workouts:[UnifiedWorkout], now:Date=Date()) -> AccountActivityCanonicalBatch {
        var result=AccountActivityCanonicalBatch()
        for group in UnifiedWorkoutDeduplicationEngine().canonicalGroups(workouts) {
            do { result.inputs += try canonicalInputs(group.sourceWorkouts, now:now) }
            catch { result.rejectedCanonicalIDs.insert(group.workout.id) }
        }
        return result
    }
    func payload(expectedRevision: Int64) -> AccountActivityStagePayload {
        .init(p_canonical_id:canonicalID,p_source_ids:sourceIDs,p_expected_revision:expectedRevision,
              p_sport:sport,p_activity_at:activityAt,p_duration_seconds:durationSeconds,
              p_distance_meters:distanceMeters,p_deleted:deleted)
    }
}
/// One candidate owner worker. Call only with an authorized canonical snapshot;
/// this API does not read HealthKit/SwiftData or derive consent from account scope.
@MainActor final class AccountActivitySyncOrchestrator {
    let engine: AccountActivitySyncCandidate
    private var running=false
    init(engine: AccountActivitySyncCandidate) { self.engine=engine }
    /// Explicit best-effort mode. Validation/transport failures are returned,
    /// not silently discarded; retries first resolve the exact durable payload.
    func reconcileIsolated(_ inputs:[AccountActivityStageInput], now:Date=Date(),
                           onAcknowledged:((AccountActivityStageInput) throws -> Void)? = nil) async throws -> AccountActivitySyncReport {
        guard !running else { throw AccountActivitySyncError.busy }
        guard Set(inputs.map(\.canonicalID)).count==inputs.count else { throw AccountActivitySyncError.invalidPayload }
        // Cross-card alias ambiguity is a batch integrity error, not a bad card
        // that can safely be skipped after another card has already been sent.
        var aliases=Set<UUID>()
        for input in inputs {
            guard Set(input.sourceIDs).isDisjoint(with:aliases) else { throw AccountActivitySyncError.pendingConflict }
            aliases.formUnion(input.sourceIDs)
        }
        let lease=try engine.captureLease()
        running=true; defer { running=false }
        var report=try await engine.flushIsolated(now:now)
        try engine.checkLease(lease)
        for input in inputs where !report.failedCanonicalIDs.contains(input.canonicalID) {
            var succeeded=false
            do {
                try engine.checkLease(lease)
                let resolved=try await engine.resolveExistingCanonical(input,now:now)
                try engine.checkLease(lease)
                guard !report.failedCanonicalIDs.contains(resolved.canonicalID) else {throw AccountActivitySyncError.pendingConflict}
                let queued=try await engine.enqueueLatest(resolved,now:now)
                try engine.checkLease(lease)
                if queued {
                    report.completed += try await engine.flush(now:now,canonicalID:resolved.canonicalID)
                    try engine.checkLease(lease)
                }
                succeeded=true
            } catch {
                try engine.checkLease(lease)
                try AccountActivitySyncReport.rethrowGlobal(error)
                report.failedCanonicalIDs.insert(input.canonicalID)
            }
            // Persist each proven desired mutation before starting the next card.
            // An acknowledgement storage failure stops the batch, never drops work.
            if succeeded {try onAcknowledged?(input)}
        }
        return report
    }
    func reconcile(_ inputs:[AccountActivityStageInput], now:Date=Date()) async throws -> Int {
        guard !running else { throw AccountActivitySyncError.busy }
        guard Set(inputs.map(\.canonicalID)).count==inputs.count else { throw AccountActivitySyncError.invalidPayload }
        var aliases=Set<UUID>()
        for input in inputs {
            try input.payload(expectedRevision:0).validate(now:now)
            guard Set(input.sourceIDs).isDisjoint(with:aliases) else { throw AccountActivitySyncError.pendingConflict }
            aliases.formUnion(input.sourceIDs)
        }
        let lease=try engine.captureLease()
        running=true; defer {running=false}
        var staged=try await engine.flush(now:now)
        try engine.checkLease(lease)
        for input in inputs {
            try engine.checkLease(lease)
            let resolved=try await engine.resolveExistingCanonical(input,now:now)
            try engine.checkLease(lease)
            let queued=try await engine.enqueueLatest(resolved,now:now)
            try engine.checkLease(lease)
            if queued { staged += try await engine.flush(now:now); try engine.checkLease(lease) }
        }
        return staged
    }
}

struct AccountActivityCanonicalBatch {
    var inputs: [AccountActivityStageInput] = []
    var rejectedCanonicalIDs = Set<UUID>()
}
struct AccountActivitySyncReport: Equatable {
    var completed = 0
    var failedCanonicalIDs = Set<UUID>()
    static func rethrowGlobal(_ error: Error) throws {
        try Task.checkCancellation()
        if error is CancellationError { throw error }
        if let databaseError=error as? PostgrestError,
           ["42501", "PGRST301", "PGRST302", "PGRST303"].contains(databaseError.code ?? "") {
            throw AccountActivitySyncError.unauthorized
        }
        if let syncError=error as? AccountActivitySyncError {
            switch syncError {
            case .disabled, .unauthorized, .accountChanged, .busy: throw error
            default: break
            }
        }
    }
}

// MARK: - All-source durable automatic reconciliation

/// This queue is upstream of the revision-aware transport outbox. Saving a local
/// desired snapshot never waits for a network lookup and never changes originals.
/// The transport outbox separately retains an uncertain *previous* write until
/// its exact lookup receipt is resolved, before the latest desired state is sent.
struct AccountActivityDesiredMutation: Codable, Equatable {
    let mutationID: UUID
    let input: AccountActivityStageInput
}
struct AccountActivityAutomaticQueueState: Codable, Equatable {
    let ownerID: UUID
    var known: [UUID: AccountActivityStageInput] = [:]
    var pending: [UUID: AccountActivityDesiredMutation] = [:]
}
@MainActor final class AccountActivityAutomaticQueue {
    private let directory: URL
    init(directory: URL) { self.directory = directory }
    private func path(_ owner: UUID) -> URL {
        directory.appendingPathComponent("automatic-" + owner.uuidString.lowercased() + ".json")
    }
    func load(owner: UUID) throws -> AccountActivityAutomaticQueueState {
        let url=path(owner)
        guard FileManager.default.fileExists(atPath:url.path) else { return .init(ownerID:owner) }
        let data=try Data(contentsOf:url)
        guard data.count <= 32_000_000 else { throw AccountActivitySyncError.invalidPayload }
        let state=try JSONDecoder().decode(AccountActivityAutomaticQueueState.self,from:data)
        guard state.ownerID==owner, state.known.count<=100_000,
              state.known.allSatisfy({$0.key==$0.value.canonicalID}),
              state.pending.allSatisfy({$0.key==$0.value.input.canonicalID && state.known[$0.key]==$0.value.input})
        else { throw AccountActivitySyncError.invalidPayload }
        return state
    }
    private func save(_ state:AccountActivityAutomaticQueueState) throws {
        guard state.known.count<=100_000 else { throw AccountActivitySyncError.invalidPayload }
        let data=try JSONEncoder().encode(state)
        guard data.count<=32_000_000 else { throw AccountActivitySyncError.invalidPayload }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try data.write(to:path(state.ownerID),options:.atomic)
    }
    /// Missing rows are NOT deletes. A canonical card is tombstoned only when
    /// every previously known source alias has an explicit durable tombstone.
    /// A partial alias deletion leaves the remaining canonical workout intact.
    @discardableResult func record(owner:UUID, inputs:[AccountActivityStageInput],
                                  deletedSourceIDs:Set<UUID>, now:Date=Date()) throws -> Int {
        guard Set(inputs.map(\.canonicalID)).count==inputs.count else { throw AccountActivitySyncError.invalidPayload }
        var aliases=Set<UUID>()
        for input in inputs {
            try input.payload(expectedRevision:0).validate(now:now)
            guard !input.deleted, Set(input.sourceIDs).isDisjoint(with:aliases) else { throw AccountActivitySyncError.pendingConflict }
            aliases.formUnion(input.sourceIDs)
        }
        var state=try load(owner:owner)
        let liveIDs=Set(inputs.map(\.canonicalID))
        func replace(_ input:AccountActivityStageInput) {
            guard state.known[input.canonicalID] != input else { return }
            state.known[input.canonicalID]=input
            state.pending[input.canonicalID] = .init(mutationID:UUID(),input:input)
        }
        for input in inputs { replace(input) }
        for old in Array(state.known.values) where !old.deleted && !liveIDs.contains(old.canonicalID) {
            guard Set(old.sourceIDs).isSubset(of:deletedSourceIDs),
                  Set(old.sourceIDs).isDisjoint(with:aliases) else { continue }
            replace(.init(canonicalID:old.canonicalID,sourceIDs:old.sourceIDs,sport:old.sport,
                activityAt:old.activityAt,durationSeconds:old.durationSeconds,distanceMeters:old.distanceMeters,deleted:true))
        }
        try save(state)
        return state.pending.count
    }
    @discardableResult func recordTombstone(_ input:AccountActivityStageInput,owner:UUID) throws -> Bool {
        try input.payload(expectedRevision:0).validate(now:Date())
        guard input.deleted else {throw AccountActivitySyncError.invalidPayload}
        var state=try load(owner:owner)
        guard state.known[input.canonicalID] != input else {return false}
        state.known[input.canonicalID]=input
        state.pending[input.canonicalID] = .init(mutationID:UUID(),input:input)
        try save(state);return true
    }
    /// A receipt for an older snapshot cannot clear a newer edit queued during await.
    func acknowledge(_ mutations:[AccountActivityDesiredMutation], owner:UUID) throws {
        var state=try load(owner:owner)
        for mutation in mutations where state.pending[mutation.input.canonicalID]==mutation {
            state.pending.removeValue(forKey:mutation.input.canonicalID)
        }
        try save(state)
    }
}

struct AccountActivityLocalSnapshot {
    let batch: AccountActivityCanonicalBatch
    let deletedSourceIDs: Set<UUID>
    /// Reads all records already authorized and stored in this account, with no
    /// date cut-off and no new HealthKit/Google/Strava permission or network call.
    @MainActor static func read(context:ModelContext, expected:AccountActivitySyncContext,
                                now:Date=Date()) throws -> Self {
        guard !expected.retired, expected.scopeID==expected.ownerID.uuidString.lowercased(),
              HealthCloudJournal.accountID(for:context)==expected.ownerID,
              !HealthCloudJournal.isRetired(context) else { throw AccountActivitySyncError.accountChanged }
        let records=try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>())
        let workouts=records.map { UnifiedWorkoutPersistenceMapper().makeWorkout(from:$0) }
        let entries=try context.fetch(FetchDescriptor<HealthCloudOutboxRecord>())
        let deleted=Set(entries.filter{$0.kind==HealthCloudKind.workout.rawValue && $0.isTombstone && !$0.conflicted}
            .compactMap{UUID(uuidString:$0.recordKey)})
        return .init(batch:AccountActivityStageInput.canonicalBatch(workouts,now:now),deletedSourceIDs:deleted)
    }
}

/// One worker per signed-in container. The host requests it on launch, foreground,
/// local didCommit, restored dataRevision and explicit retry. Capture/persistence
/// completes synchronously; network delivery runs independently of local import.
@MainActor final class AccountActivityAutomaticSyncWorker: ObservableObject {
    @Published private(set) var pendingCount=0
    @Published private(set) var rejectedCanonicalIDs=Set<UUID>()
    @Published private(set) var lastError: String?
    @Published private(set) var isRunning=false
    private let queue:AccountActivityAutomaticQueue
    private let orchestrator:AccountActivitySyncOrchestrator
    private let currentContext:()->AccountActivitySyncContext?
    private let snapshot:() throws -> AccountActivityLocalSnapshot
    private var task:Task<Void,Never>?
    private var followUp=false
    init(queue:AccountActivityAutomaticQueue, orchestrator:AccountActivitySyncOrchestrator,
         currentContext:@escaping ()->AccountActivitySyncContext?,
         snapshot:@escaping () throws -> AccountActivityLocalSnapshot) {
        self.queue=queue;self.orchestrator=orchestrator;self.currentContext=currentContext;self.snapshot=snapshot
    }
    /// Caller supplies an actual staging grant through the engine. Public profile
    /// alone never authorizes storing health summaries remotely.
    func request() {
        do {
            let lease=try orchestrator.engine.captureLease()
            guard currentContext()==lease.context else { throw AccountActivitySyncError.accountChanged }
            let value=try snapshot()
            try orchestrator.engine.checkLease(lease)
            guard currentContext()==lease.context else { throw AccountActivitySyncError.accountChanged }
            pendingCount=try queue.record(owner:lease.context.ownerID,inputs:value.batch.inputs,deletedSourceIDs:value.deletedSourceIDs)
            rejectedCanonicalIDs=value.batch.rejectedCanonicalIDs
            lastError=nil
            if task != nil { followUp=true;return }
            task=Task { await self.drain(expected:lease.context) }
        } catch { lastError=String(describing:error) }
    }
    func cancel() { task?.cancel();followUp=false }
    private func drain(expected:AccountActivitySyncContext) async {
        isRunning=true
        defer { isRunning=false;task=nil }
        repeat {
            followUp=false
            do {
                guard !Task.isCancelled,currentContext()==expected else { throw AccountActivitySyncError.accountChanged }
                let state=try queue.load(owner:expected.ownerID)
                let mutations=state.pending.values.sorted{$0.input.canonicalID.uuidString<$1.input.canonicalID.uuidString}
                let captured=Dictionary(uniqueKeysWithValues:mutations.map{($0.input.canonicalID,$0)})
                var acknowledgedAny=false
                defer {
                    if acknowledgedAny {NotificationCenter.default.post(name:FeedPostManagement.didChange,object:expected.ownerID)}
                }
                let report=try await orchestrator.reconcileIsolated(mutations.map(\.input),onAcknowledged:{ input in
                    guard !Task.isCancelled,self.currentContext()==expected else {throw AccountActivitySyncError.accountChanged}
                    guard let mutation=captured[input.canonicalID] else {throw AccountActivitySyncError.invalidPayload}
                    try self.queue.acknowledge([mutation],owner:expected.ownerID)
                    self.pendingCount=try self.queue.load(owner:expected.ownerID).pending.count
                    acknowledgedAny=true
                })
                guard !Task.isCancelled,currentContext()==expected else { throw AccountActivitySyncError.accountChanged }
                pendingCount=try queue.load(owner:expected.ownerID).pending.count
                rejectedCanonicalIDs.formUnion(report.failedCanonicalIDs)
                lastError=report.failedCanonicalIDs.isEmpty ? nil : "일부 운동 반영을 재시도해야 해요."
                if try await recoverExplicitTombstones(expected:expected) { followUp=true }
            } catch {
                lastError=String(describing:error)
                // Keep both durable queues. No unbounded retry or notification burst.
                return
            }
        } while followUp && !Task.isCancelled
    }
    private func recoverExplicitTombstones(expected:AccountActivitySyncContext) async throws -> Bool {
        let value=try snapshot(),known=try queue.load(owner:expected.ownerID)
        let knownAliases=Set(known.known.values.flatMap(\.sourceIDs))
        let liveAliases=Set(value.batch.inputs.flatMap(\.sourceIDs))
        let missing=value.deletedSourceIDs.subtracting(knownAliases).subtracting(liveAliases)
        var changed=false
        for source in missing.sorted(by:{$0.uuidString<$1.uuidString}) {
            guard !Task.isCancelled,currentContext()==expected else {throw AccountActivitySyncError.accountChanged}
            guard let row=try await orchestrator.engine.lookupDeletedSource(source) else {continue}
            guard !Task.isCancelled,currentContext()==expected else {throw AccountActivitySyncError.accountChanged}
            // Re-read after await: a restored/live alias must win over the old
            // deletion snapshot rather than tombstoning a surviving workout.
            let fresh=try snapshot(),aliases=Set(row.source_ids)
            guard aliases.isSubset(of:fresh.deletedSourceIDs),
                  aliases.isDisjoint(with:Set(fresh.batch.inputs.flatMap(\.sourceIDs))) else {continue}
            let input=AccountActivityStageInput(canonicalID:row.canonical_id,sourceIDs:row.source_ids,
                sport:row.sport,activityAt:row.activity_at,durationSeconds:row.duration_seconds,
                distanceMeters:row.distance_meters,deleted:true)
            changed = try queue.recordTombstone(input,owner:expected.ownerID) || changed
        }
        return changed
    }
    func waitUntilIdle() async { await task?.value }
}
