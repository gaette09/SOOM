import Foundation
import Supabase

enum AccountActivityInteractionReleaseGate { static let productionReady = false }
enum AccountActivityCommentResolution: Equatable { case found, absent, unavailable }
enum AccountActivityInteractionError: Error, Equatable {
    case disabled, accountChanged, invalidResponse, invalidRequest, requiresLegacyPath, uncertainWrite
}
enum AccountActivityInteractionTarget: Codable, Equatable {
    case native(cardID: UUID, ownerID: UUID)
    case legacy(cardID: UUID, postID: UUID)
    var cardID: UUID { switch self { case .native(let id, _), .legacy(let id, _): return id } }
}
struct AccountActivityInteractionContext: Equatable {
    let viewerID: UUID?
    let generation: Int
    let safetyRevision: Int
    let storageScopeID: String
}
struct AccountActivityCommentMention: Codable, Equatable {
    let user_id: UUID
    let handle: String
}
struct AccountActivityCommentRequest: Codable, Equatable {
    let id: UUID // Persist and reuse this request ID. Never regenerate after an uncertain result.
    let body: String
    let mentions: [AccountActivityCommentMention]
    let parentID: UUID?
}
struct AccountActivityNativeComment: Decodable, Identifiable, Equatable {
    let id: UUID
    let card_id: UUID
    let author_id: UUID
    let parent_id: UUID?
    let reply_to_id: UUID?
    let created_at: String
    let is_deleted: Bool
    let body: String
    let mentions: [AccountActivityCommentMention]
}
struct AccountActivityCommentCursor: Equatable {
    let createdAt: String
    let id: UUID
}
struct AccountActivityPhotoMetadata: Decodable, Equatable, Identifiable {
    let id: UUID
    let card_id: UUID
    let storage_path: String
    let sort_order: Int
}
struct AccountActivityInteractionParameters: Encodable {
    var p_card_id: UUID
    var p_comment_id: UUID? = nil
    var p_body: String? = nil
    var p_mentions: [AccountActivityCommentMention]? = nil
    var p_parent_comment_id: UUID? = nil
    var p_limit: Int? = nil
    var p_after_at: String? = nil
    var p_after_id: UUID? = nil
    var p_expected_photo_ids: [UUID]? = nil
    var p_photos: [AccountActivityPhotoReference]? = nil
}
struct AccountActivityPendingComment: Codable, Equatable {
    let ownerID: UUID
    let target: AccountActivityInteractionTarget
    let request: AccountActivityCommentRequest
}
@MainActor
protocol AccountActivityCommentJournal {
    func read() throws -> [AccountActivityPendingComment]
    func write(_ rows: [AccountActivityPendingComment]) throws
}
@MainActor
final class FileAccountActivityCommentJournal: AccountActivityCommentJournal {
    private let url: URL
    private let ownerID: UUID?
    init(ownerID: UUID?, url: URL? = nil, preview: Bool = false, readPolicy: AccountActivityReadPolicy = .approvedFollowersV1) {
        self.ownerID=ownerID
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HealthAccounts/\(ownerID?.uuidString.lowercased() ?? "unavailable")/native-comment-\(preview ? "preview-" : "")pending-v\(readPolicy.rawValue).json")
    }
    func read() throws -> [AccountActivityPendingComment] {
        guard let ownerID else { throw AccountActivityInteractionError.accountChanged }
        return try AccountDeletionWriteFence.shared.withActiveScope(ownerID) {
            guard FileManager.default.fileExists(atPath:url.path) else { return [] }
            let rows=try JSONDecoder().decode([AccountActivityPendingComment].self,from:Data(contentsOf:url))
            guard rows.allSatisfy({$0.ownerID==ownerID}) else { throw AccountActivityInteractionError.accountChanged }
            return rows
        }
    }
    func write(_ rows: [AccountActivityPendingComment]) throws {
        guard let ownerID,rows.allSatisfy({$0.ownerID==ownerID}) else { throw AccountActivityInteractionError.accountChanged }
        try AccountDeletionWriteFence.shared.withActiveScope(ownerID) {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(rows).write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            var resource=URLResourceValues();resource.isExcludedFromBackup=true
            var file=url;try file.setResourceValues(resource)
        }
    }
}
@MainActor
final class MemoryAccountActivityCommentJournal: AccountActivityCommentJournal {
    private var rows: [AccountActivityPendingComment] = []
    func read() throws -> [AccountActivityPendingComment] { rows }
    func write(_ rows: [AccountActivityPendingComment]) throws { self.rows = rows }
}
@MainActor
protocol AccountActivityInteractionTransport {
    var readPolicy: AccountActivityReadPolicy { get }
    func call(_ name: String, params: AccountActivityInteractionParameters) async throws -> Data
}
extension AccountActivityInteractionTransport { var readPolicy: AccountActivityReadPolicy { .approvedFollowersV1 } }
@MainActor
struct SupabaseAccountActivityInteractionTransport: AccountActivityInteractionTransport {
    let client: SupabaseClient
    var preview: Bool = false
    var readPolicy: AccountActivityReadPolicy = .approvedFollowersV1
    func call(_ name: String, params: AccountActivityInteractionParameters) async throws -> Data {
        guard AccountActivityInteractionAdapter.allowedRPCs.contains(name),
              name.hasSuffix("_candidate_v\(readPolicy.rawValue)"), !preview || readPolicy == .approvedFollowersV1 else { throw AccountActivityInteractionError.invalidRequest }
        if preview {
            guard !name.contains("photos"), let owner = client.auth.currentSession?.user.id else { throw AccountActivityInteractionError.disabled }
            let capability = try await AccountActivityPreviewService(client: client, owner: owner).capability()
            guard capability.enabled, client.auth.currentSession?.user.id == owner else { throw AccountActivityInteractionError.disabled }
            let data = try await client.rpc(name.replacingOccurrences(of: "_candidate_v1", with: "_preview_v1"), params: params).execute().data
            guard client.auth.currentSession?.user.id == owner, !AccountDeletionWriteFence.shared.isRetired(owner) else { throw AccountActivityInteractionError.accountChanged }
            return data
        }
        guard readPolicy.interactionsProductionReady else { throw AccountActivityInteractionError.disabled }
        return try await client.rpc(name, params: params).execute().data
    }
}

struct AccountActivityResolvedPhoto: Identifiable {
    let id: UUID
    let url: URL
    let expiresAt: Date
    let context: AccountActivityInteractionContext
}
@MainActor
protocol AccountActivityPhotoSigning {
    var trustedOrigin: URL { get }
    func sign(path: String, expiresIn: Int) async throws -> URL
}
@MainActor
struct SupabaseAccountActivityPhotoSigner: AccountActivityPhotoSigning {
    let client: SupabaseClient
    let trustedOrigin: URL // App-configured Supabase origin, never returned by metadata.
    func sign(path: String, expiresIn: Int) async throws -> URL {
        guard AccountActivityInteractionReleaseGate.productionReady else { throw AccountActivityInteractionError.disabled }
        guard expiresIn == 60 else { throw AccountActivityInteractionError.invalidRequest }
        return try await client.storage.from("activity-photos-candidate").createSignedURL(path:path,expiresIn:expiresIn)
    }
}
@MainActor
final class AccountActivityInteractionAdapter {
    static let legacyRPCs: Set<String> = ["soom_activity_interaction_status_candidate_v1",
        "soom_activity_native_comments_candidate_v1", "soom_activity_native_add_comment_candidate_v1",
        "soom_activity_native_delete_comment_candidate_v1", "soom_activity_photos_candidate_v1",
        "soom_activity_comment_request_status_candidate_v1", "soom_activity_replace_photos_candidate_v1"]
    static let allowedRPCs = legacyRPCs.union(legacyRPCs.map { $0.replacingOccurrences(of: "_candidate_v1", with: "_candidate_v2") })
    private let policy: AccountActivityReadPolicy
    private let transport: any AccountActivityInteractionTransport
    private let context: () -> AccountActivityInteractionContext
    private let fixture: Bool
    private let preview: Bool
    private let journal: any AccountActivityCommentJournal
    private var inFlight = Set<UUID>()
    private var uncertainDeletes = Set<UUID>()
    private var retryAllowed = Set<UUID>()
    private var unresolved: [UUID: (AccountActivityInteractionContext, AccountActivityInteractionTarget, AccountActivityCommentRequest)] = [:]
    init(transport: any AccountActivityInteractionTransport, context: @escaping () -> AccountActivityInteractionContext,
         journal: (any AccountActivityCommentJournal)? = nil, preview: Bool = false) {
        self.preview = preview
        policy = transport.readPolicy
        self.transport = transport; self.context = context; fixture = false; self.journal = journal ?? FileAccountActivityCommentJournal(ownerID: context().viewerID, preview: preview, readPolicy: transport.readPolicy)
    }
    #if DEBUG
    private init(fixtureTransport: any AccountActivityInteractionTransport, context: @escaping () -> AccountActivityInteractionContext, journal: any AccountActivityCommentJournal) {
        transport = fixtureTransport; policy = fixtureTransport.readPolicy; self.context = context; fixture = true; preview = false; self.journal = journal
    }
    static func localFixture(transport: any AccountActivityInteractionTransport,
                             context: @escaping () -> AccountActivityInteractionContext, journal: (any AccountActivityCommentJournal)? = nil) -> AccountActivityInteractionAdapter {
        .init(fixtureTransport: transport, context: context, journal: journal ?? MemoryAccountActivityCommentJournal())
    }
    #endif
    private func begin(_ target: AccountActivityInteractionTarget) throws -> AccountActivityInteractionContext {
        guard !preview || policy == .approvedFollowersV1 else { throw AccountActivityInteractionError.disabled }
        guard fixture || (preview && policy == .approvedFollowersV1) || policy.interactionsProductionReady else { throw AccountActivityInteractionError.disabled }
        guard case .native = target else { throw AccountActivityInteractionError.requiresLegacyPath }
        let c = context()
        guard let viewer = c.viewerID, !AccountDeletionWriteFence.shared.isRetired(viewer), c.generation >= 0, c.storageScopeID == viewer.uuidString.lowercased(), !Task.isCancelled else {
            throw AccountActivityInteractionError.accountChanged
        }
        return c
    }
    private func check(_ c: AccountActivityInteractionContext) throws {
        guard transport.readPolicy == policy, context() == c, c.viewerID.map({ !AccountDeletionWriteFence.shared.isRetired($0) }) == true, !Task.isCancelled else { throw AccountActivityInteractionError.accountChanged }
    }
    private func gate(_ version: Int, _ backing: String, _ ready: Bool) throws {
        guard version == policy.rawValue, backing == "native", (fixture || preview) ? !ready : (ready && policy.interactionsProductionReady) else {
            throw AccountActivityInteractionError.invalidResponse
        }
    }
    private struct Status: Decodable { let version: Int; let card_id: UUID; let backing: String; let state: String; let release_ready: Bool }
    private func status(_ target: AccountActivityInteractionTarget, _ c: AccountActivityInteractionContext) async throws {
        let data = try await transport.call(policy.interactionRPC("soom_activity_interaction_status_candidate_v1"), params: .init(p_card_id: target.cardID))
        try check(c)
        let value = try JSONDecoder().decode(Status.self, from: data)
        try gate(value.version, value.backing, value.release_ready)
        guard value.card_id == target.cardID, value.state == "native_ready" else { throw AccountActivityInteractionError.invalidResponse }
    }
    private struct Comments: Decodable { let version: Int; let backing: String; let release_ready: Bool; let rows: [AccountActivityNativeComment] }
    func loadComments(_ target: AccountActivityInteractionTarget, limit: Int = 50,
                      after: AccountActivityCommentCursor? = nil) async throws -> [AccountActivityNativeComment] {
        let c = try begin(target)
        guard (1...100).contains(limit), after.map({ Self.date($0.createdAt) != nil }) ?? true else { throw AccountActivityInteractionError.invalidRequest }
        try await status(target, c)
        let data = try await transport.call(policy.interactionRPC("soom_activity_native_comments_candidate_v1"), params: .init(p_card_id: target.cardID,
            p_limit: limit, p_after_at: after?.createdAt, p_after_id: after?.id))
        try check(c)
        let value = try JSONDecoder().decode(Comments.self, from: data)
        try gate(value.version, value.backing, value.release_ready)
        guard value.rows.count <= limit, Set(value.rows.map(\.id)).count == value.rows.count else { throw AccountActivityInteractionError.invalidResponse }
        var previous = after
        for row in value.rows {
            guard row.card_id == target.cardID, let date = Self.date(row.created_at),
                  row.body.count <= 500, row.mentions.count <= 10,
                  Set(row.mentions.map(\.user_id)).count == row.mentions.count,
                  row.parent_id != row.id, row.reply_to_id != row.id,
                  !row.is_deleted || (row.body.isEmpty && row.mentions.isEmpty) else { throw AccountActivityInteractionError.invalidResponse }
            if let previous, let pDate = Self.date(previous.createdAt) {
                guard date > pDate || (date == pDate && row.id.uuidString.lowercased() > previous.id.uuidString.lowercased()) else {
                    throw AccountActivityInteractionError.invalidResponse
                }
            }
            previous = .init(createdAt: row.created_at, id: row.id)
        }
        return value.rows
    }
    func submit(_ target: AccountActivityInteractionTarget, request: AccountActivityCommentRequest) async throws -> UUID {
        let c = try begin(target)
        guard !request.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, request.body.count <= 500,
              request.mentions.count <= 10, Set(request.mentions.map(\.user_id)).count == request.mentions.count,
              request.parentID != request.id, request.mentions.allSatisfy({ !$0.handle.isEmpty && $0.handle.count <= 80 }) else {
            throw AccountActivityInteractionError.invalidRequest
        }
        // Without an exact server request-status contract, uncertainty never authorizes replay.
        let savedPending = try journal.read().filter { $0.ownerID == c.viewerID && $0.target == target }
        let isRetry = retryAllowed.remove(request.id) != nil && savedPending.count == 1 && savedPending.first?.request == request
        guard (isRetry || savedPending.isEmpty),
              (isRetry || unresolved[request.id] == nil), (isRetry || !unresolved.values.contains(where: { $0.0 == c && $0.1 == target })),
              inFlight.insert(request.id).inserted else { throw AccountActivityInteractionError.uncertainWrite }
        defer { inFlight.remove(request.id) }
        try await status(target, c)
        var saved = try journal.read()
        if !isRetry {
            guard !saved.contains(where: { $0.request.id == request.id }) else { throw AccountActivityInteractionError.invalidRequest }
            saved.append(.init(ownerID: c.viewerID!, target: target, request: request))
        }
        try journal.write(saved) // Durable frozen intent before the first write RPC.
        unresolved[request.id] = (c, target, request)
        do {
            let data = try await transport.call(policy.interactionRPC("soom_activity_native_add_comment_candidate_v1"), params: .init(p_card_id: target.cardID,
                p_comment_id: request.id, p_body: request.body, p_mentions: request.mentions, p_parent_comment_id: request.parentID))
            try check(c)
            let id = try JSONDecoder().decode(UUID.self, from: data)
            guard id == request.id else { throw AccountActivityInteractionError.invalidResponse }
            try removePending(request.id, owner: c.viewerID!)
            return id
        } catch { throw AccountActivityInteractionError.uncertainWrite }
    }
    func pendingRequests(_ target: AccountActivityInteractionTarget) throws -> [AccountActivityCommentRequest] {
        let c = try begin(target)
        return try journal.read().filter { $0.ownerID == c.viewerID && $0.target == target }.map(\.request)
    }
    private func removePending(_ id: UUID, owner: UUID) throws {
        try journal.write(journal.read().filter { !($0.ownerID == owner && $0.request.id == id) })
        unresolved.removeValue(forKey: id)
    }
    /// Explicit retry only after the same frozen request is proven absent.
    func retryConfirmedAbsent(_ target: AccountActivityInteractionTarget, request: AccountActivityCommentRequest) async throws -> UUID {
        let c = try begin(target)
        guard try pendingRequests(target).contains(request) else { throw AccountActivityInteractionError.invalidRequest }
        let result = try await resolve(target, request: request)
        try check(c)
        if result == .found { return request.id }
        guard result == .absent else { throw AccountActivityInteractionError.uncertainWrite }
        // Keep the durable entry throughout status recheck and retry.
        retryAllowed.insert(request.id)
        defer { retryAllowed.remove(request.id) }
        return try await submit(target, request: request)
    }
    /// User-requested cancellation only: never discards an unverified write.
    func discardConfirmedAbsent(_ target: AccountActivityInteractionTarget, request: AccountActivityCommentRequest) async throws -> AccountActivityCommentResolution {
        let c = try begin(target)
        guard try pendingRequests(target).contains(request) else { throw AccountActivityInteractionError.invalidRequest }
        let resolution = try await resolve(target, request: request)
        try check(c)
        if resolution == .absent { try removePending(request.id, owner: c.viewerID!) }
        return resolution // found was already finalized; unavailable remains durable.
    }
    private struct Receipt: Decodable {
        let id: UUID; let card_id: UUID; let author_id: UUID; let body: String
        let mentions: [AccountActivityCommentMention]; let parent_id: UUID?; let reply_to_id: UUID?
        let deleted_at: String?
    }
    private struct RequestStatus: Decodable {
        let version: Int?; let backing: String?; let state: String; let release_ready: Bool?
        let receipt: Receipt?
    }
    /// Only an exact identity/body/parent receipt resolves an uncertain write.
    /// Absence is reported, not automatically retried or replaced with a fresh ID.
    func resolve(_ target: AccountActivityInteractionTarget, request: AccountActivityCommentRequest) async throws -> AccountActivityCommentResolution {
        let c = try begin(target)
        try await status(target, c)
        let data = try await transport.call(policy.interactionRPC("soom_activity_comment_request_status_candidate_v1"),
            params: .init(p_card_id: target.cardID, p_comment_id: request.id))
        try check(c)
        let value = try JSONDecoder().decode(RequestStatus.self, from: data)
        if value.state == "unavailable" { return .unavailable }
        guard let version = value.version, let backing = value.backing, let ready = value.release_ready else {
            throw AccountActivityInteractionError.invalidResponse
        }
        try gate(version, backing, ready)
        if value.state == "absent", value.receipt == nil { return .absent }
        guard value.state == "found", let row = value.receipt, row.id == request.id,
              row.card_id == target.cardID, row.author_id == c.viewerID, row.deleted_at == nil,
              row.body == request.body, row.reply_to_id == request.parentID,
              Set(row.mentions.map(\.user_id)) == Set(request.mentions.map(\.user_id)),
              row.mentions.count == request.mentions.count,
              row.mentions.allSatisfy({ request.mentions.contains($0) }) else {
            throw AccountActivityInteractionError.invalidResponse
        }
        try removePending(request.id, owner: c.viewerID!)
        return .found
    }
    func delete(_ target: AccountActivityInteractionTarget, commentID: UUID, authorID: UUID) async throws {
        let c = try begin(target)
        guard c.viewerID == authorID else { throw AccountActivityInteractionError.invalidRequest }
        guard !uncertainDeletes.contains(commentID), inFlight.insert(commentID).inserted else { throw AccountActivityInteractionError.uncertainWrite }
        defer { inFlight.remove(commentID) }
        try await status(target, c)
        do {
            let data = try await transport.call(policy.interactionRPC("soom_activity_native_delete_comment_candidate_v1"), params: .init(p_card_id: target.cardID, p_comment_id: commentID))
            try check(c)
            guard try JSONDecoder().decode(Bool.self, from: data) else { throw AccountActivityInteractionError.invalidResponse }
        } catch {
            uncertainDeletes.insert(commentID)
            throw AccountActivityInteractionError.uncertainWrite
        }
    }
    private struct Photos: Decodable { let version: Int; let backing: String; let release_ready: Bool; let bucket: String; let rows: [AccountActivityPhotoMetadata] }
    func loadPhotos(_ target: AccountActivityInteractionTarget) async throws -> [AccountActivityPhotoMetadata] {
        let c = try begin(target)
        guard case .native(_, let owner) = target else { throw AccountActivityInteractionError.requiresLegacyPath }
        try await status(target, c)
        let data = try await transport.call(policy.interactionRPC("soom_activity_photos_candidate_v1"), params: .init(p_card_id: target.cardID))
        try check(c)
        let value = try JSONDecoder().decode(Photos.self, from: data)
        try gate(value.version, value.backing, value.release_ready)
        guard value.bucket == "activity-photos-candidate", value.rows.count <= 6,
              Set(value.rows.map(\.id)).count == value.rows.count else { throw AccountActivityInteractionError.invalidResponse }
        for (i, row) in value.rows.enumerated() {
            guard row.card_id == target.cardID, row.sort_order == i,
                  row.storage_path == "\(owner.uuidString.lowercased())/\(target.cardID.uuidString.lowercased())/\(row.id.uuidString.lowercased()).jpg" else {
                throw AccountActivityInteractionError.invalidResponse
            }
        }
        return value.rows // Metadata only; no public URL construction, download or upload.
    }
    /// No shared URL cache: each authorized load signs exact private paths for 60 seconds.
    func resolvePhotos(_ target: AccountActivityInteractionTarget, signer: any AccountActivityPhotoSigning) async throws -> [AccountActivityResolvedPhoto] {
        let c = try begin(target)
        let metadata = try await loadPhotos(target)
        try check(c)
        guard signer.trustedOrigin.scheme == "https", signer.trustedOrigin.host != nil,
              signer.trustedOrigin.user == nil, signer.trustedOrigin.password == nil else { throw AccountActivityInteractionError.invalidResponse }
        var result: [AccountActivityResolvedPhoto] = []
        for photo in metadata {
            let issuedAt = Date()
            let url = try await signer.sign(path:photo.storage_path,expiresIn:60)
            try check(c)
            guard url.scheme == "https", url.host == signer.trustedOrigin.host,
                  url.port == signer.trustedOrigin.port, url.user == nil, url.password == nil,
                  url.fragment == nil,
                  url.path == "/storage/v1/object/sign/activity-photos-candidate/" + photo.storage_path,
                  URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.contains(where:{$0.name == "token" && !($0.value ?? "").isEmpty}) == true else {
                throw AccountActivityInteractionError.invalidResponse
            }
            result.append(.init(id:photo.id,url:url,expiresAt:issuedAt.addingTimeInterval(60),context:c))
        }
        try await status(target,c) // Recheck access after signing, before exposing URLs to UI.
        return result
    }
    func isPhotoCurrent(_ photo: AccountActivityResolvedPhoto, now: Date = Date()) -> Bool {
        context() == photo.context && now < photo.expiresAt && !Task.isCancelled
    }
    private static func date(_ string: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: string) { return date }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: string)
    }
}
