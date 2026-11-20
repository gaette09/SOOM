import Foundation
import Combine
import SwiftUI
import Supabase

/// Explicit release opt-in. This is fresh authorization, never a timed lease.
enum FeedReturnBatchReleaseGate {
    static var enabled: Bool {
        if ReviewDemoMode.isActive {
            #if DEBUG && targetEnvironment(simulator)
            return ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_QA"] == "1"
            #else
            return false
            #endif
        }
        #if SOOM_PROFILE_VISIBLE_BATCH_V2
        return true
        #else
        return false
        #endif
    }
}
/// Feature-path selection only. This does not grant any card, media, or route access.
/// Historical v1 capability is not the deployed v2 presentation mode.
enum Feed61ActivationPolicy {
    static func usesVisibleBatch(releaseEnabled: Bool, readPolicy: AccountActivityReadPolicy,
                                 legacyPreviewEnabled: Bool, audience: FeedAudience,
                                 pageUnsupported: Bool) -> Bool {
        // Legacy preview eligibility must not veto the independently authorized
        // production v2 path. All card/media authority checks remain downstream.
        releaseEnabled && readPolicy == .profileOnlyV2 &&
        audience == .home && !pageUnsupported
    }

    static func needsLegacyPreviewCapability(readPolicy: AccountActivityReadPolicy) -> Bool {
        readPolicy == .approvedFollowersV1
    }
}

enum FeedBatchCardPreviewReleaseGate {
    static var enabled: Bool {
        #if SOOM_FEED_CARD_PROJECTION_V3
        return true
        #else
        return false
        #endif
    }
}
enum FeedReturnBatchError: Error { case malformed, changed, disabled }
struct FeedReturnBatchContext: Equatable {
    let viewerID: UUID
    let accountGeneration: Int
    let safetyRevision: Int
    let returnEpoch: Int
    static func authorizedCurrent(_ context: Self?, authViewerID: UUID?, transportViewerID: UUID?, applicationActive: Bool) -> Self? {
        guard let context, applicationActive, authViewerID == context.viewerID,
              transportViewerID == context.viewerID else { return nil }
        return context
    }
    func matches(viewerID: UUID?, accountGeneration: Int, safetyRevision: Int, returnEpoch: Int) -> Bool {
        self.viewerID == viewerID && self.accountGeneration == accountGeneration &&
        self.safetyRevision == safetyRevision && self.returnEpoch == returnEpoch
    }
}

/// Only constructed after the batch envelope, source identity and object bounds
/// have been checked. Unknown metadata does not authorize cached pixel reuse.
struct FeedReturnStorageObject: Equatable {
    let bucket: String
    let path: String
    let objectID: UUID
    let version: String
    let etag: String?
    let updatedAt: Date?
    let size: Int?
    let versionHash: String?
    var cacheVersionToken: String? {
        Self.cacheVersionToken(objectID: objectID.uuidString, version: version, etag: etag, updatedAt: updatedAt, size: size)
    }
    /// Shared with Storage.info: independent hosts must agree on an object's
    /// identity/version or simultaneous authorized reads supersede each other.
    static func cacheVersionToken(objectID: String?, version: String, etag: String?, updatedAt: Date?, size: Int?) -> String? {
        guard let objectID, let id = UUID(uuidString: objectID), let size, size > 0,
              !version.isEmpty || !(etag ?? "").isEmpty || updatedAt != nil else { return nil }
        // Storage.info omits updated_at (and transports may round timestamps),
        // while the SQL batch includes it. The Storage version is the content
        // revision shared by both endpoints; optional metadata must not make
        // two authorized hosts repeatedly revoke each other's unchanged bytes.
        // Object identity + size still fence recreation and malformed metadata.
        let identity = id.uuidString.lowercased() + "|size:" + String(size)
        if !version.isEmpty { return identity + "|version:" + version }
        if let etag, !etag.isEmpty { return identity + "|etag:" + etag }
        return identity + "|updated:" + String(updatedAt?.timeIntervalSince1970 ?? 0)
    }
}
struct FeedReturnCardGrant {
    let id: UUID
    let row: AccountActivityFeedRow
    let author: FeedProfileDTO?
    let authorRevision: String?
    let avatarObject: FeedReturnStorageObject?
    let photos: [WorkoutPhotoReference]
    let photoObjects: [String: FeedReturnStorageObject]
    let photosAvailable: Bool
    let socialStatus: ProfileActivitySocialStatus?
    var hasBatchCardPreview = false
    var batchCardPreview: FeedLinkedCardPresentation? = nil
}
enum FeedReturnAccess<Value> { case pending, denied, authorized(Value) }
struct FeedReturnBatchPresentation {
    enum Phase { case pending, ready, failed }
    let id: UUID
    let context: FeedReturnBatchContext
    var phase: Phase
    var grants: [UUID: FeedReturnCardGrant] = [:]
    var denied: Set<UUID> = []
    var requested: Set<UUID> = []
    var needsPageReload = false
    var hasMore = false
    var membershipRevision: String?

    func cardAccess(rowID: UUID) -> FeedReturnAccess<FeedReturnCardGrant> {
        if phase == .failed || denied.contains(rowID) { return .denied }
        if phase == .ready, let grant = grants[rowID] { return .authorized(grant) }
        return .pending
    }
    func avatarAccess(ownerID: UUID, path: String) -> FeedReturnAccess<FeedReturnStorageObject> {
        guard phase == .ready else { return phase == .failed ? .denied : .pending }
        let owners = grants.values.filter { $0.row.ownerID == ownerID }
        guard !owners.isEmpty else { return .denied }
        guard let value = owners.compactMap(\.avatarObject).first(where: { $0.path == path }) else { return .denied }
        return .authorized(value)
    }
    func photoAccess(_ photo: WorkoutPhotoReference) -> FeedReturnAccess<FeedReturnStorageObject> {
        guard phase == .ready else { return phase == .failed ? .denied : .pending }
        guard let authority = photo.profileAuthority, let grant = grants[authority.cardID],
              grant.row.ownerID == authority.ownerID, grant.row.revision == authority.projectionRevision,
              grant.photos.contains(photo), let object = grant.photoObjects[photo.cacheKey],
              object.path == photo.storagePath, object.bucket == photo.bucket else { return .denied }
        return .authorized(object)
    }
}
private struct FeedReturnBatchEnvironmentKey: EnvironmentKey {
    static let defaultValue: FeedReturnBatchPresentation? = nil
}
private struct FeedViewportCardsKey: EnvironmentKey {
    static let defaultValue: ((Set<UUID>) -> Void)? = nil
}
private struct FeedVisibleCardRegistrationKey: EnvironmentKey {
    static let defaultValue: ((UUID, Bool) -> Void)? = nil
}
private struct FeedReturnRetryKey: EnvironmentKey {
    static let defaultValue: ((UUID) -> Void)? = nil
}
extension EnvironmentValues {
    var soomFeedViewportCards: ((Set<UUID>) -> Void)? {
        get { self[FeedViewportCardsKey.self] }
        set { self[FeedViewportCardsKey.self] = newValue }
    }
    var soomFeedReturnRetry: ((UUID) -> Void)? {
        get { self[FeedReturnRetryKey.self] }
        set { self[FeedReturnRetryKey.self] = newValue }
    }
    var soomFeedReturnBatch: FeedReturnBatchPresentation? {
        get { self[FeedReturnBatchEnvironmentKey.self] }
        set { self[FeedReturnBatchEnvironmentKey.self] = newValue }
    }
    var soomFeedVisibleCardRegistration: ((UUID, Bool) -> Void)? {
        get { self[FeedVisibleCardRegistrationKey.self] }
        set { self[FeedVisibleCardRegistrationKey.self] = newValue }
    }
}

@MainActor final class FeedReturnBatchStore: ObservableObject {
    let linkedCards = FeedLinkedCardStore()
    let socialPresentations = Feed60SocialPresentationStore()
    private var socialObservation: AnyCancellable?
    init() {
        socialObservation = socialPresentations.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    @Published private(set) var presentation: FeedReturnBatchPresentation?
    // Visibility schedules missing grants; it does not change rendered content.
    // Publishing objectWillChange here rebuilt every mounted card on every
    // viewport transition, even when all grants were already warm.
    private(set) var visibleRevision = 0
    let visibilityChanges = PassthroughSubject<Int, Never>()
    @Published private(set) var commitRevision = 0
    private(set) var visibleIDs: Set<UUID> = []
    private var lastVisibleIDs: Set<UUID> = []
    private var viewportIDs: Set<UUID>?
    private var lastViewportIDs: Set<UUID> = []
    private(set) var requestCount = 0
    private var knownAvatarObjects: [UUID: FeedReturnStorageObject] = [:]
    private var knownPhotoObjects: [UUID: [String: FeedReturnStorageObject]] = [:]
    func isCurrent(id: UUID, context: FeedReturnBatchContext?) -> Bool {
        guard let current = presentation, let context else { return false }
        return current.id == id && current.phase == .ready && current.context == context
    }
    func isCurrent(authority: FeedLinkedCardAuthority, context: FeedReturnBatchContext?) -> Bool {
        guard isCurrent(id: authority.batchID, context: context),
              presentation?.context == authority.context,
              case .authorized(let grant)? = presentation?.cardAccess(rowID: authority.row.cardID) else { return false }
        return grant.id == authority.grantID && grant.row == authority.row
    }
    func register(cardID: UUID, visible: Bool) {
        let before = visibleIDs
        if visible { visibleIDs.insert(cardID) } else { visibleIDs.remove(cardID) }
        guard before != visibleIDs else { return }
        if !visibleIDs.isEmpty { lastVisibleIDs = visibleIDs }
        visibleRevision += 1
        visibilityChanges.send(visibleRevision)
    }
    func setViewport(_ ids: Set<UUID>) {
        guard viewportIDs != ids else { return }
        viewportIDs = ids
        if !ids.isEmpty { lastViewportIDs = ids }
        visibleRevision += 1
        visibilityChanges.send(visibleRevision)
    }
    @discardableResult func invalidateResource(_ resource: String) -> Bool {
        guard var current = presentation, current.phase == .ready else { return false }
        let affected = current.grants.values.filter { $0.photoObjects[resource] != nil || $0.photos.contains { $0.cacheKey == resource } }.map { $0.row.cardID }
        guard !affected.isEmpty else { return false }
        for id in affected { current.grants.removeValue(forKey: id); current.requested.remove(id); current.denied.remove(id) }
        presentation = current
        linkedCards.retain(using: current); socialPresentations.retain(using: current)
        commitRevision += 1
        return true
    }
    func targets(loadedRows: [AccountActivityFeedRow], missingOnly: Bool = false) -> [UUID] {
        let all = loadedRows.map(\.cardID), allowed = Set(all)
        // This is metadata bookkeeping, not an authority lease. Bound it to the
        // current page prefix; a later return still requires a fresh receipt.
        knownPhotoObjects = knownPhotoObjects.filter { allowed.contains($0.key) }
        knownAvatarObjects = knownAvatarObjects.filter { allowed.contains($0.key) }
        let targets: Set<UUID>
        if let viewportIDs {
            let viewport = (viewportIDs.isEmpty ? lastViewportIDs : viewportIDs).intersection(allowed)
            if viewport.isEmpty { targets = Set(all.prefix(8)) }
            else {
                var nearby = viewport
                for index in all.indices where viewport.contains(all[index]) {
                    if index > 0 { nearby.insert(all[index - 1]) }
                    if index + 1 < all.count { nearby.insert(all[index + 1]) }
                }
                targets = nearby
            }
        } else if all.count <= 50 { targets = allowed }
        else { targets = (visibleIDs.isEmpty ? lastVisibleIDs : visibleIDs).intersection(allowed) }
        var coalesced = targets
        if (missingOnly && presentation?.phase == .ready) || all.count <= FeedViewModel.pageSize {
            // Authorize a small page-local block when its first missing card
            // approaches the viewport. This avoids one RPC per scrolling row.
            // It is still a fresh server check, not a cached authority extension.
            for index in all.indices where targets.contains(all[index]) && presentation?.requested.contains(all[index]) != true {
                let start = (index / 4) * 4
                coalesced.formUnion(all[start..<min(start + 4, all.count)])
            }
        }
        return all.filter { coalesced.contains($0) && (!missingOnly || presentation?.requested.contains($0) != true) }.prefix(50).map { $0 }
    }
    @discardableResult func begin(context: FeedReturnBatchContext) -> UUID {
        linkedCards.clear(); socialPresentations.clear()
        let id = UUID()
        presentation = .init(id: id, context: context, phase: .pending)
        return id
    }
    @discardableResult func beginRetry(context: FeedReturnBatchContext) -> Bool {
        guard let current = presentation, current.context == context, current.phase == .failed else { return false }
        begin(context: context) // Synchronous latch: another tap cannot queue another retry.
        return true
    }
    func invalidate() {
        linkedCards.clear(); socialPresentations.clear()
        guard let old = presentation else { return }
        presentation = .init(id: UUID(), context: old.context, phase: .pending)
    }
    func invalidateForMembershipChange(_ value: FeedReturnBatchPresentation) {
        FeedStaleSummaryCache.shared.clear()
        // Close presentation synchronously, before a potentially slow page read.
        invalidate()
        for cardID in value.denied {
            WorkoutPhotoImageCache.shared.revoke(resources: Set(knownPhotoObjects.removeValue(forKey: cardID)?.keys.map { $0 } ?? []))
            if let object = knownAvatarObjects.removeValue(forKey: cardID) {
                FeedAvatarImageCache.shared.pixels.invalidateResource(object.bucket + ":" + object.path)
            }
        }
    }
    func countRequest() { requestCount += 1 }
    func publish(_ value: FeedReturnBatchPresentation, expectedID: UUID, merging: Bool = false) -> Bool {
        guard let old = presentation, old.id == expectedID, old.context == value.context else { return false }
        // A fresh denial/removal/version change invalidates older loaders too,
        // not only the now-hidden card. Pending verification keeps pixels only.
        var revoked = Set<String>()
        var revokedAvatars = Set<String>()
        for cardID in value.denied {
            if let oldAvatar = knownAvatarObjects.removeValue(forKey: cardID) {
                revokedAvatars.insert(oldAvatar.bucket + ":" + oldAvatar.path)
            }
            revoked.formUnion(knownPhotoObjects.removeValue(forKey: cardID)?.keys.map { $0 } ?? [])
        }
        for (cardID, grant) in value.grants {
            if let oldAvatar = knownAvatarObjects[cardID],
               grant.avatarObject?.path != oldAvatar.path || grant.avatarObject?.cacheVersionToken != oldAvatar.cacheVersionToken {
                revokedAvatars.insert(oldAvatar.bucket + ":" + oldAvatar.path)
            }
            knownAvatarObjects[cardID] = grant.avatarObject
            let previous = knownPhotoObjects[cardID] ?? [:]
            for (key, object) in previous where grant.photoObjects[key]?.cacheVersionToken != object.cacheVersionToken || grant.photoObjects[key] == nil {
                revoked.insert(key)
            }
            knownPhotoObjects[cardID] = grant.photoObjects
        }
        WorkoutPhotoImageCache.shared.revoke(resources: revoked)
        for resource in revokedAvatars { FeedAvatarImageCache.shared.pixels.invalidateResource(resource) }
        if merging, old.phase == .ready {
            var merged = value
            merged.grants = old.grants.merging(value.grants) { _, latest in latest }
            for id in value.denied { merged.grants.removeValue(forKey: id) }
            merged.denied.formUnion(old.denied.subtracting(Set(value.grants.keys)))
            merged.requested.formUnion(old.requested)
            presentation = merged
        } else { presentation = value }
        if let presentation { linkedCards.retain(using: presentation); socialPresentations.retain(using: presentation) }
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
           let age = ProcessInfo.processInfo.environment["SOOM_STALE_TEST_AGE_SECONDS"].flatMap(Double.init),
           age > 0, age < ProcessInfo.processInfo.systemUptime {
            // Exercise old persisted snapshots without changing the device clock
            // or bypassing this freshly verified synthetic batch's authority.
            FeedStaleSummaryCache.shared.accept(value, now: Date().addingTimeInterval(-age),
                uptime: ProcessInfo.processInfo.systemUptime - age)
        } else { FeedStaleSummaryCache.shared.accept(value) }
        #else
        FeedStaleSummaryCache.shared.accept(value)
        #endif
        commitRevision += 1
        return true
    }
    func fail(expectedID: UUID) {
        guard let old = presentation, old.id == expectedID else { return }
        linkedCards.clear(); socialPresentations.clear()
        presentation = .init(id: UUID(), context: old.context, phase: .failed)
    }
}

struct FeedReturnBatchParameters: Encodable {
    let p_card_ids: [UUID]
    let p_scope = "home"
    let p_account_generation: Int
    let p_safety_revision: Int
    let p_return_epoch: Int
    let p_loaded_card_ids: [UUID]
}
private struct FeedReturnBatchWire: Decodable {
    let version: Int, viewer_id: UUID, release_ready: Bool, scope: String
    let account_generation: Int, safety_revision: Int, return_epoch: Int
    let rows: [Card]
    let needs_page_reload: Bool, has_more: Bool, membership_revision: String
    struct Object: Decodable {
        let object_id: UUID, version: String
        let etag: String?, updated_at: String?, size: Int?, version_hash: String?
        let authorized: Bool?, bucket: String?, storage_path: String?
        @MainActor func validated(bucket: String, path: String, maximumBytes: Int) throws -> FeedReturnStorageObject {
            let date = updated_at.flatMap(ProfileActivitySocialAdapter.date)
            guard version.count <= 256, (etag?.count ?? 0) <= 512,
                  updated_at == nil || date != nil,
                  size.map({ $0 > 0 && $0 <= maximumBytes }) ?? true,
                  version_hash.map(FeedReturnBatchAdapter.validHash) ?? true else { throw FeedReturnBatchError.malformed }
            return .init(bucket: bucket, path: path, objectID: object_id, version: version, etag: etag,
                         updatedAt: date, size: size, versionHash: version_hash)
        }
    }
    struct Photos: Decodable {
        let version: Int, viewer_id: UUID, card_id: UUID, owner_id: UUID, canonical_id: UUID
        let projection_revision: Int64, profile_revision: Int64
        let backing: String, source_id: UUID, bucket: String, release_ready: Bool
        let rows: [Photo]
        struct Photo: Decodable {
            let id: UUID, card_id: UUID, storage_path: String, sort_order: Int
            let object: Object
        }
        @MainActor func validated(row: AccountActivityFeedRow, viewerID: UUID) throws -> ([WorkoutPhotoReference], [String: FeedReturnStorageObject]) {
            let envelope = AccountActivityProfilePhotoEnvelope(version: version, viewer_id: viewer_id, card_id: card_id,
                owner_id: owner_id, canonical_id: canonical_id, projection_revision: projection_revision,
                profile_revision: profile_revision, backing: backing, source_id: source_id, bucket: bucket,
                release_ready: release_ready, rows: rows.map { .init(id: $0.id, card_id: $0.card_id, storage_path: $0.storage_path, sort_order: $0.sort_order) })
            let photos = try envelope.validated(viewerID: viewerID, cardID: row.cardID, ownerID: row.ownerID,
                                               canonicalID: row.canonicalID, revision: row.revision)
            var objects: [String: FeedReturnStorageObject] = [:]
            for (photo, item) in zip(photos, rows) {
                objects[photo.cacheKey] = try item.object.validated(bucket: bucket, path: photo.storagePath, maximumBytes: WorkoutPhotoPolicy.maximumBytes)
            }
            return (photos, objects)
        }
    }
    struct Card: Decodable {
        let card_id: UUID, allowed: Bool
        let summary: AccountActivityFeedRow?, author: FeedProfileDTO?, author_revision: String?
        let avatar: Object?, photos: Photos?, social: ProfileActivitySocialStatus?, social_revision: String?
        let card_preview: FeedBatchCardPreviewWire?
    }
}

@MainActor struct FeedReturnBatchAdapter {
    typealias Read = (FeedReturnBatchParameters) async throws -> Data
    let read: Read
    let current: () -> FeedReturnBatchContext?
    let expectedVersion: Int
    init(client: SupabaseClient, current: @escaping () -> FeedReturnBatchContext?) {
        expectedVersion = FeedBatchCardPreviewReleaseGate.enabled ? 3 : 2
        self.current = {
            let proposed = current()
            return FeedReturnBatchContext.authorizedCurrent(proposed, authViewerID: proposed?.viewerID,
                transportViewerID: client.auth.currentSession?.user.id,
                applicationActive: UIApplication.shared.applicationState == .active)
        }
        let endpoint = FeedBatchCardPreviewReleaseGate.enabled
            ? "soom_activity_social_visible_batch_candidate_v3" : "soom_activity_social_visible_batch_candidate_v2"
        read = { parameters in
            let request = try client.rpc(endpoint, params: parameters)
            if FeedBatchCardPreviewReleaseGate.enabled {
                return try await request.setHeader(name: SupabaseWorkoutSharedDetailService.header,
                    value: SupabaseWorkoutSharedDetailService.contract).execute().data
            }
            return try await request.execute().data
        }
    }
    init(read: @escaping Read, current: @escaping () -> FeedReturnBatchContext?, expectedVersion: Int = 2) { self.read = read; self.current = current; self.expectedVersion = expectedVersion }
    func load(cardIDs: [UUID], loadedRows: [AccountActivityFeedRow], context: FeedReturnBatchContext, id: UUID) async throws -> FeedReturnBatchPresentation {
        guard current() == context, !Task.isCancelled, !AccountDeletionWriteFence.shared.isRetired(context.viewerID),
              context.accountGeneration >= 0, context.safetyRevision >= 0, context.returnEpoch >= 0,
              cardIDs.count <= 50, loadedRows.count <= 500,
              Set(cardIDs).count == cardIDs.count, Set(loadedRows.map(\.cardID)).count == loadedRows.count,
              Set(cardIDs).isSubset(of: Set(loadedRows.map(\.cardID))) else { throw FeedReturnBatchError.changed }
        let params = FeedReturnBatchParameters(p_card_ids: cardIDs, p_account_generation: context.accountGeneration,
            p_safety_revision: context.safetyRevision, p_return_epoch: context.returnEpoch, p_loaded_card_ids: loadedRows.map(\.cardID))
        let data = try await read(params)
        guard current() == context, !Task.isCancelled, !AccountDeletionWriteFence.shared.isRetired(context.viewerID) else { throw FeedReturnBatchError.changed }
        return try Self.validate(data, cardIDs: cardIDs, loadedRows: loadedRows, context: context, id: id, expectedVersion: expectedVersion)
    }
    static func validHash(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { (48...57).contains($0.value) || (97...102).contains($0.value) }
    }
    static func validate(_ data: Data, cardIDs: [UUID], loadedRows: [AccountActivityFeedRow], context: FeedReturnBatchContext, id: UUID, now: Date = Date(), expectedVersion: Int = 2) throws -> FeedReturnBatchPresentation {
        guard [2, 3].contains(expectedVersion), cardIDs.count <= 50, loadedRows.count <= 500, Set(cardIDs).count == cardIDs.count,
              Set(loadedRows.map(\.cardID)).count == loadedRows.count,
              Set(cardIDs).isSubset(of: Set(loadedRows.map(\.cardID))),
              let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rawRows = raw["rows"] as? [[String: Any]] else { throw FeedReturnBatchError.malformed }
        // No unnoticed health/detail fields or leaked denied-row payloads.
        for value in rawRows {
            guard let allowed = value["allowed"] as? Bool else { throw FeedReturnBatchError.malformed }
            let keys = Set(value.keys)
            var expected: Set<String> = allowed
                ? ["card_id","allowed","summary","author","author_revision","avatar","photos","social","social_revision"]
                : ["card_id","allowed"]
            if allowed && expectedVersion == 3 { expected.insert("card_preview") }
            guard keys == expected else { throw FeedReturnBatchError.malformed }
            if allowed {
                guard let summary = value["summary"] as? [String: Any], Set(summary.keys) ==
                    Set(["card_id","canonical_id","owner_id","sport","activity_at","duration_seconds","distance_meters","revision"]) else { throw FeedReturnBatchError.malformed }
            }
        }
        let wire = try JSONDecoder().decode(FeedReturnBatchWire.self, from: data)
        guard wire.version == expectedVersion, wire.release_ready, wire.viewer_id == context.viewerID, wire.scope == "home",
              wire.account_generation == context.accountGeneration, wire.safety_revision == context.safetyRevision,
              wire.return_epoch == context.returnEpoch, validHash(wire.membership_revision),
              wire.rows.count == cardIDs.count, Set(wire.rows.map(\.card_id)) == Set(cardIDs),
              Set(wire.rows.map(\.card_id)).count == wire.rows.count else { throw FeedReturnBatchError.malformed }
        let known = Dictionary(uniqueKeysWithValues: loadedRows.map { ($0.cardID, $0) })
        var result = FeedReturnBatchPresentation(id: id, context: context, phase: .ready, requested: Set(cardIDs),
            needsPageReload: wire.needs_page_reload, hasMore: wire.has_more, membershipRevision: wire.membership_revision)
        for entry in wire.rows {
            guard entry.allowed else { result.denied.insert(entry.card_id); continue }
            guard let rawRow = entry.summary, let old = known[entry.card_id], rawRow.canonicalID == old.canonicalID,
                  let row = try AccountActivityCardEnvelope(version: 2, viewerID: context.viewerID, row: rawRow, releaseReady: true)
                    .validateCandidate(expectedCardID: entry.card_id, requestViewerID: context.viewerID, currentViewerID: context.viewerID,
                        requestGeneration: context.accountGeneration, currentGeneration: context.accountGeneration,
                        latestPermittedDate: now, expectedOwnerID: old.ownerID, expectedPolicy: .profileOnlyV2),
                  entry.author.map({ $0.id == row.ownerID && !$0.displayName.isEmpty && $0.displayName.count <= 256 && ($0.handle?.count ?? 0) <= 64 }) ?? true,
                  entry.author_revision.map(validHash) ?? (entry.author == nil),
                  entry.social_revision.map(validHash) ?? (entry.social == nil) else { throw FeedReturnBatchError.malformed }
            var avatar: FeedReturnStorageObject?
            if let object = entry.avatar {
                guard object.authorized == true, object.bucket == ProfileAvatarPolicy.bucket,
                      let path = object.storage_path, path == entry.author?.avatarPath,
                      ProfileAvatarPolicy.isOwnedPath(path, by: row.ownerID) else { throw FeedReturnBatchError.malformed }
                avatar = try object.validated(bucket: ProfileAvatarPolicy.bucket, path: path, maximumBytes: ProfileAvatarPolicy.maximumBytes)
            }
            let media = try entry.photos?.validated(row: row, viewerID: context.viewerID)
            if let status = entry.social {
                let r = status.receipt
                guard status.state == "ready", r.version == 2, r.release_ready, r.viewer_id == context.viewerID,
                      r.card_id == row.cardID, r.owner_id == row.ownerID, r.canonical_id == row.canonicalID,
                      r.projection_revision == row.revision, r.profile_revision > 0, r.profile_revision < Int64.max,
                      r.hasValidRouting,
                      (0...1_000_000_000).contains(status.comment_count), (0...1_000_000_000).contains(status.cheer_count),
                      status.latest_comment_at.map({ ProfileActivitySocialAdapter.date($0) != nil }) ?? true,
                      status.comment_count != 0 || status.latest_comment_at == nil else { throw FeedReturnBatchError.malformed }
            }
            var preview: FeedLinkedCardPresentation?
            if expectedVersion == 3 {
                guard let cardPreview = entry.card_preview else { throw FeedReturnBatchError.malformed }
                // Bind the projection to the same freshly authorized legacy source.
                // Native-only cards may report unavailable, never an unrelated post.
                let legacyID = entry.social?.receipt.read_sources?.first(where: { $0.source_kind == "legacy" })?.source_id
                if cardPreview.state == "ready" {
                    guard let legacyID, let date = row.cursor?.activityAt else { throw FeedReturnBatchError.malformed }
                    preview = try cardPreview.validated(postID: legacyID, ownerID: row.ownerID, date: date)
                } else {
                    _ = try cardPreview.validated(postID: legacyID ?? row.cardID, ownerID: row.ownerID, date: now)
                }
            }
            result.grants[row.cardID] = .init(id: UUID(), row: row, author: entry.author, authorRevision: entry.author_revision,
                avatarObject: avatar, photos: media?.0 ?? [], photoObjects: media?.1 ?? [:], photosAvailable: entry.photos != nil,
                socialStatus: entry.social, hasBatchCardPreview: expectedVersion == 3, batchCardPreview: preview)
        }
        return result
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Synthetic wire fixture. No Supabase session or user image bytes are used.
@MainActor enum FeedReturnBatchDemo {
    static var requests = 0
    static var requestTargets: [String] = []
    static var heldRequests: Set<Int> = []
    private static var releasedRequests: Set<Int> = []
    static func releaseHeldRequests() { releasedRequests.formUnion(heldRequests) }
    static func read(_ p: FeedReturnBatchParameters, rows: [AccountActivityFeedRow]) async throws -> Data {
        guard ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_QA"] == "1" else { throw FeedReturnBatchError.disabled }
        requests += 1
        let request = requests
        // Synthetic-only reader: bounded invented-card diagnostic, never production IDs.
        requestTargets.append(p.p_card_ids.map { String(Int($0.uuidString.split(separator: "-").last ?? "") ?? -1) }.joined(separator: ","))
        if requestTargets.count > 16 { requestTargets.removeFirst() }
        if request == 2, ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_FAIL_SECOND"] == "1" {
            throw URLError(.notConnectedToInternet)
        }
        if (request > 1 || ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_HOLD_FIRST"] == "1"), ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_HOLD_RETURN"] == "1",
           !(request > 2 && ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_DENY_AFTER_FIRST"] == "1") {
            heldRequests.insert(request)
            defer { heldRequests.remove(request); releasedRequests.remove(request) }
            while !releasedRequests.contains(request) {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        let delay = Int(ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_DELAY_MS"] ?? "250") ?? 250
        try await Task.sleep(for: .milliseconds(max(0, min(5000, delay))))
        let hash = String(repeating: "a", count: 64)
        var results: [[String: Any]] = []
        for row in rows where p.p_card_ids.contains(row.cardID) {
            if request > 1 && ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_DENY_AFTER_FIRST"] == "1" {
                results.append(["card_id": row.cardID.uuidString, "allowed": false]); continue
            }
            let photos: [WorkoutPhotoReference]
            let mixedPhotoIndex = Int(row.cardID.uuidString.split(separator: "-").last ?? "")
            if ProcessInfo.processInfo.environment["SOOM_STALE_TEXT_ONLY_QA"] == "1",
               ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1" {
                photos = []
            } else if ProcessInfo.processInfo.environment["SOOM_FEED_OWN_PHOTO_GRANT_QA"] == "1",
               ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
               row.ownerID == ReviewDemoMode.userID {
                // Demo seed explicitly uses workoutID as its synthetic postID.
                // Production postID/workoutID are different; no alias is inferred.
                let local = try await ReviewDemoPhotoStore.shared.load(workoutID: row.canonicalID, ownerID: row.ownerID)
                let context = AccountActivityInteractionContext(viewerID: ReviewDemoMode.userID,
                    generation: p.p_account_generation, safetyRevision: p.p_safety_revision,
                    storageScopeID: ReviewDemoMode.userID.uuidString.lowercased())
                let envelope = AccountActivityProfilePhotoEnvelope(version: 2, viewer_id: ReviewDemoMode.userID,
                    card_id: row.cardID, owner_id: row.ownerID, canonical_id: row.canonicalID,
                    projection_revision: row.revision, profile_revision: 1, backing: "legacy",
                    source_id: row.canonicalID, bucket: WorkoutPhotoPolicy.bucket, release_ready: true,
                    rows: local.enumerated().map { index, photo in
                        AccountActivityPhotoMetadata(id: photo.id, card_id: row.cardID,
                            storage_path: photo.storagePath, sort_order: index)
                    })
                photos = try await AccountActivityProfilePhotoAdapter(read: { _ in envelope }, context: { context }).load(row: row)
            } else if ProcessInfo.processInfo.environment["SOOM_FEED_PAGINATION_QA"] == "1" {
                photos = [] // Pagination tests do not allocate 20 image fixtures.
             } else if FeedUniquePhotoFixture.groups != nil && FeedUniquePhotoFixture.group(row: row) == nil {
                photos = [] // Exactly two foreign media rows; four slots each in both modes.
            } else if Feed61MixedReuseDemo.enabled &&
                        (row.ownerID == ReviewDemoMode.userID || mixedPhotoIndex.map({ $0 % 4 != 2 }) != false) {
                // Stable sparse foreign media; the own row uses its real demo
                // local-media path, not a fake independently shared photo grant.
                photos = []
            } else {
                photos = try await ReviewDemoPhotoStore.shared.seedProfilePhotoFixture(row: row, context:
                    .init(viewerID: ReviewDemoMode.userID, generation: p.p_account_generation,
                        safetyRevision: p.p_safety_revision, storageScopeID: ReviewDemoMode.userID.uuidString.lowercased()))
            }
            var photoEnvelope: Any = NSNull()
            if let authority = photos.first?.profileAuthority {
                photoEnvelope = ["version": 2, "viewer_id": ReviewDemoMode.userID.uuidString,
                    "card_id": row.cardID.uuidString, "owner_id": row.ownerID.uuidString, "canonical_id": row.canonicalID.uuidString,
                    "projection_revision": row.revision, "profile_revision": authority.profileRevision,
                    "backing": "legacy", "source_id": authority.sourceID.uuidString, "bucket": authority.bucket, "release_ready": true,
                    "rows": photos.enumerated().map { index, photo in
                        ["id": photo.id.uuidString, "card_id": row.cardID.uuidString, "storage_path": photo.storagePath, "sort_order": index,
                         "object": ["object_id": photo.id.uuidString, "version": "synthetic-v1", "etag": NSNull(),
                                    "updated_at": "2026-01-01T00:00:00Z", "size": ReviewDemoPhotoStore.shared.bytes(for: photo)?.count ?? 0,
                                    "version_hash": hash]] as [String: Any]
                    }]
            }
            let avatarID = UUID(uuidString: "A9130000-0000-4000-8000-000000000777")!
            let avatarPath = row.ownerID.uuidString.lowercased() + "/" + avatarID.uuidString.lowercased() + ".jpg"
            guard let avatarBytes = ReviewDemoAvatarStore.sampleImageData(), avatarBytes.count <= ProfileAvatarPolicy.maximumBytes else { throw FeedReturnBatchError.malformed }
            let avatar: [String: Any] = ["authorized": true, "bucket": ProfileAvatarPolicy.bucket,
                "storage_path": avatarPath, "object_id": avatarID.uuidString, "version": "synthetic-avatar-v1",
                "etag": NSNull(), "updated_at": "2026-01-01T00:00:00Z", "size": avatarBytes.count, "version_hash": hash]
            results.append(["card_id": row.cardID.uuidString, "allowed": true,
                "summary": ["card_id": row.cardID.uuidString, "owner_id": row.ownerID.uuidString, "canonical_id": row.canonicalID.uuidString,
                            "sport": row.sport, "activity_at": row.activityAt, "duration_seconds": row.durationSeconds,
                            "distance_meters": row.distanceMeters as Any? ?? NSNull(), "revision": row.revision],
                "author": ["id": row.ownerID.uuidString, "display_name": "데모 운동 기록", "handle": NSNull(), "avatar_path": avatarPath],
                "author_revision": hash, "avatar": avatar, "photos": photoEnvelope,
                "social": NSNull(), "social_revision": NSNull()])
        }
        let previewV3 = ProcessInfo.processInfo.environment["SOOM_FEED_CARD_PREVIEW_V3_QA"] == "1"
        if previewV3 {
            for i in results.indices where results[i]["allowed"] as? Bool == true {
                guard let row = rows.first(where: { $0.cardID.uuidString == results[i]["card_id"] as? String }) else { continue }
                let postID = row.canonicalID.uuidString
                results[i]["social"] = ["state": "ready", "comment_count": 0, "cheer_count": 0,
                    "latest_comment_at": NSNull(), "viewer_has_cheered": false,
                    "receipt": ["version": 2, "release_ready": true, "viewer_id": ReviewDemoMode.userID.uuidString,
                        "card_id": row.cardID.uuidString, "owner_id": row.ownerID.uuidString, "canonical_id": row.canonicalID.uuidString,
                        "projection_revision": row.revision, "profile_revision": 1, "backing": "legacy",
                        "source_id": postID, "write_backing": "legacy",
                        "read_sources": [["source_kind": "legacy", "source_id": postID]], "source_revision": String(repeating: "a", count: 32)]]
                results[i]["social_revision"] = hash
                results[i]["card_preview"] = ["version": 1, "state": "ready", "serializer_version": 1,
                    "post_id": postID, "owner_id": row.ownerID.uuidString, "post_revision": "2026-01-01T00:00:00Z",
                    "snapshot_revision": 1, "consent_revision": 1, "title": "합성 대회 기록", "caption": NSNull(),
                    "device_name": "합성 기기", "location_name": "합성 장소", "route_state": "ready",
                    "authorized_route_geometry": (0..<20).map { index in
                        ["latitude": 37.5 + Double(index) * 0.0001, "longitude": 127.0 + Double(index) * 0.0001, "segment": 0] as [String: Any]
                    }]
            }
        }
        return try JSONSerialization.data(withJSONObject: ["version": previewV3 ? 3 : 2, "viewer_id": ReviewDemoMode.userID.uuidString,
            "release_ready": true, "scope": "home", "account_generation": p.p_account_generation,
            "safety_revision": p.p_safety_revision, "return_epoch": p.p_return_epoch, "rows": results,
            "needs_page_reload": false,
            "has_more": Feed61MixedReuseDemo.enabled
                ? p.p_loaded_card_ids.count < Feed61MixedReuseDemo.total
                : (ProcessInfo.processInfo.environment["SOOM_FEED_PAGINATION_QA"] == "1" && p.p_loaded_card_ids.count < 20),
            "membership_revision": hash])
    }
}
#endif
