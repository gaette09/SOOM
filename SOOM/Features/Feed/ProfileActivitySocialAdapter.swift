import Foundation
import Supabase

/// Separate from the summary/photo gates. Enable only with the reviewed server contract.
enum ProfileActivitySocialReleaseGate {
    #if SOOM_PROFILE_SOCIAL_V2
    static let productionReady = true
    #else
    static let productionReady = false
    #endif
}
enum ProfileActivitySocialLiveGate {
    static func context(_ value: AccountActivityInteractionContext, sessionID: UUID?, isActive: Bool) -> AccountActivityInteractionContext {
        guard isActive, let viewer = value.viewerID, sessionID == viewer else {
            return .init(viewerID: nil, generation: value.generation, safetyRevision: value.safetyRevision, storageScopeID: value.storageScopeID)
        }
        return value
    }
}
enum ProfileActivitySocialError: Error, Equatable {
    case disabled, accountChanged, malformed, changed, pendingWrite, invalidRequest
}
struct ProfileActivitySocialExpected: Codable, Equatable {
    let backing: String
    let source_id: UUID
    let projection_revision: Int64
    let profile_revision: Int64
    var write_backing: String? = nil
    var read_sources: [ProfileSocialReadSource]? = nil
    var source_revision: String? = nil
    enum CodingKeys: String, CodingKey {
        case backing, source_id, projection_revision, profile_revision, write_backing, read_sources, source_revision
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(backing, forKey: .backing)
        try values.encode(source_id.uuidString.lowercased(), forKey: .source_id)
        try values.encode(projection_revision, forKey: .projection_revision)
        try values.encode(profile_revision, forKey: .profile_revision)
        try values.encodeIfPresent(write_backing, forKey: .write_backing)
        try values.encodeIfPresent(read_sources, forKey: .read_sources)
        try values.encodeIfPresent(source_revision, forKey: .source_revision)
    }

}
struct ProfileActivitySocialReceipt: Codable, Equatable {
    let version: Int
    let viewer_id: UUID
    let card_id: UUID
    let owner_id: UUID
    let canonical_id: UUID
    let projection_revision: Int64
    let profile_revision: Int64
    let backing: String
    let source_id: UUID
    let release_ready: Bool
    var expected: ProfileActivitySocialExpected {
        .init(backing: backing, source_id: source_id, projection_revision: projection_revision, profile_revision: profile_revision, write_backing: write_backing, read_sources: read_sources, source_revision: source_revision)
    }
    var write_backing: String? = nil
    var read_sources: [ProfileSocialReadSource]? = nil
    var source_revision: String? = nil
}
struct ProfileSocialReadSource: Codable, Equatable, Hashable {
    let source_kind: String
    let source_id: UUID
    enum CodingKeys: String, CodingKey { case source_kind, source_id }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(source_kind, forKey: .source_kind)
        try values.encode(source_id.uuidString.lowercased(), forKey: .source_id)
    }

}
struct ProfileSocialSourceKey: Codable, Equatable, Hashable {
    let source_kind: String
    let id: UUID
}
extension ProfileActivitySocialReceipt {
    var hasValidRouting: Bool {
        guard let write_backing, let read_sources, let source_revision,
              source_revision.count == 32, source_revision.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
              ["legacy", "native"].contains(write_backing),
              read_sources == read_sources.sorted(by: { $0.source_kind < $1.source_kind }),
              Set(read_sources.map(\.source_kind)).count == read_sources.count,
              read_sources.allSatisfy({ ["legacy", "native"].contains($0.source_kind) && ($0.source_kind != "native" || $0.source_id == card_id) }),
              read_sources.contains(.init(source_kind: write_backing, source_id: source_id)) else { return false }
        if backing == "mixed" { return read_sources.count == 2 && write_backing == "legacy" }
        return ["legacy", "native"].contains(backing) && write_backing == backing && read_sources == [.init(source_kind: backing, source_id: source_id)]
    }
    func permits(source: String?) -> Bool {
        hasValidRouting && source.map { tag in read_sources?.contains(where: { $0.source_kind == tag }) == true } == true
    }
}

struct ProfileActivitySocialStatus: Decodable, Equatable {
    let receipt: ProfileActivitySocialReceipt
    let state: String
    let comment_count: Int
    let latest_comment_at: String?
    let cheer_count: Int
    let viewer_has_cheered: Bool
    func hasRecentComment(now: Date = Date()) -> Bool {
        guard comment_count > 0, let value = latest_comment_at, let date = ProfileActivitySocialAdapter.date(value) else { return false }
        return date <= now && now.timeIntervalSince(date) < 12 * 60 * 60
    }
}
struct ProfileActivitySocialCursor: Codable, Equatable { let created_at: String; let id: UUID; var source_kind: String? = nil }
struct ProfileActivitySocialComment: Decodable, Identifiable, Equatable {
    let id: UUID
    let card_id: UUID
    let author_id: UUID?
    let body: String
    let created_at: String
    let parent_id: UUID?
    let reply_to_id: UUID?
    let is_deleted: Bool
    let mentions: [FeedMentionDraft.Selection]
    let author_profile: FeedProfileDTO?
    var source_kind: String? = nil
    var parent_source: String? = nil
    var reply_to_source: String? = nil
    var sourceKey: ProfileSocialSourceKey { .init(source_kind: source_kind ?? "", id: id) }
    var parentKey: ProfileSocialSourceKey? { parent_id.map { .init(source_kind: parent_source ?? "", id: $0) } }
    var replyKey: ProfileSocialSourceKey? { reply_to_id.map { .init(source_kind: reply_to_source ?? "", id: $0) } }
    func display(viewer: UUID) throws -> FeedComment {
        guard !is_deleted, let author_id, let date = ProfileActivitySocialAdapter.date(created_at) else { throw ProfileActivitySocialError.malformed }
        return .init(id: id, authorId: author_id, body: body, createdAt: date, isViewerAuthor: author_id == viewer,
                     profile: author_profile, parentCommentID: parent_id, isDeleted: is_deleted)
    }
}
struct ProfileActivitySocialComments: Decodable {
    let receipt: ProfileActivitySocialReceipt
    let rows: [ProfileActivitySocialComment]
    let parents: [ProfileActivitySocialComment]
    let next_cursor: ProfileActivitySocialCursor?
}
struct ProfileActivitySocialReaction: Decodable, Identifiable {
    let id: UUID
    let card_id: UUID
    let user_id: UUID
    let reaction_type: String
    let created_at: String
    let author_profile: FeedProfileDTO?
    var source_kind: String? = nil
    var provenance: [ProfileSocialSourceKey]? = nil
    var sourceKey: ProfileSocialSourceKey { .init(source_kind: source_kind ?? "", id: id) }
}
struct ProfileActivitySocialReactions: Decodable {
    let receipt: ProfileActivitySocialReceipt
    let rows: [ProfileActivitySocialReaction]
    let next_cursor: ProfileActivitySocialCursor?
}
struct ProfileActivitySocialMentions: Decodable {
    let receipt: ProfileActivitySocialReceipt
    let rows: [FeedProfileDTO]
}
struct ProfileActivitySocialPayload: Codable, Equatable {
    var comment_id: UUID? = nil
    var body: String? = nil
    var mentions: [FeedMentionDraft.Selection]? = nil
    var parent_comment_id: UUID? = nil
    var desired: Bool? = nil
    var source_kind: String? = nil
}
struct ProfileActivitySocialParameters: Encodable {
    var p_card_id: UUID
    var p_expected: ProfileActivitySocialExpected? = nil
    var p_limit: Int? = nil
    var p_after_at: String? = nil
    var p_after_id: UUID? = nil
    var p_query: String? = nil
    var p_request_id: UUID? = nil
    var p_operation: String? = nil
    var p_payload: ProfileActivitySocialPayload? = nil
    var p_after_source: String? = nil
}
struct ProfileActivitySocialWriteResult: Decodable {
    let comment_id: UUID?
    var source_kind: String? = nil
    let deleted: Bool?
    let desired: Bool?
}
struct ProfileActivitySocialMutationResult: Decodable {
    let receipt: ProfileActivitySocialReceipt
    let request_id: UUID
    let operation: String
    let state: String
    let payload: ProfileActivitySocialPayload?
    let result: ProfileActivitySocialWriteResult?
}
struct ProfileActivitySocialPending: Codable, Equatable, Identifiable {
    let id: UUID
    let receipt: ProfileActivitySocialReceipt
    let operation: String
    let payload: ProfileActivitySocialPayload
}
@MainActor protocol ProfileActivitySocialTransport {
    func call(_ name: String, params: ProfileActivitySocialParameters) async throws -> Data
}
@MainActor struct SupabaseProfileActivitySocialTransport: ProfileActivitySocialTransport {
    let client: SupabaseClient
    func call(_ name: String, params: ProfileActivitySocialParameters) async throws -> Data {
        guard ProfileActivitySocialReleaseGate.productionReady, ProfileActivitySocialAdapter.rpcNames.contains(name) else {
            throw ProfileActivitySocialError.disabled
        }
        return try await client.rpc(name, params: params).execute().data
    }
}
@MainActor protocol ProfileActivitySocialJournal {
    func read() throws -> [ProfileActivitySocialPending]
    func write(_ values: [ProfileActivitySocialPending]) throws
}
@MainActor final class FileProfileActivitySocialJournal: ProfileActivitySocialJournal {
    private let owner: UUID
    private let url: URL
    init(owner: UUID, url: URL? = nil) {
        self.owner = owner
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HealthAccounts/\(owner.uuidString.lowercased())/profile-social-pending-v2.json")
    }
    func read() throws -> [ProfileActivitySocialPending] {
        try AccountDeletionWriteFence.shared.withActiveScope(owner) {
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let values = try JSONDecoder().decode([ProfileActivitySocialPending].self, from: Data(contentsOf: url))
            guard values.allSatisfy({ $0.receipt.viewer_id == owner }), Set(values.map(\.id)).count == values.count else {
                throw ProfileActivitySocialError.accountChanged
            }
            return values
        }
    }
    func write(_ values: [ProfileActivitySocialPending]) throws {
        guard values.allSatisfy({ $0.receipt.viewer_id == owner }) else { throw ProfileActivitySocialError.accountChanged }
        try AccountDeletionWriteFence.shared.withActiveScope(owner) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(values).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var resources = URLResourceValues(); resources.isExcludedFromBackup = true
            var file = url; try file.setResourceValues(resources)
        }
    }
}
@MainActor final class MemoryProfileActivitySocialJournal: ProfileActivitySocialJournal {
    var values: [ProfileActivitySocialPending] = []
    func read() throws -> [ProfileActivitySocialPending] { values }
    func write(_ values: [ProfileActivitySocialPending]) throws { self.values = values }
}

@MainActor final class ProfileActivitySocialAdapter {
    static let rpcNames = Set(["status", "comments", "reactions", "mentions", "mutate", "request_status"].map { "soom_activity_social_\($0)_candidate_v2" })
    private let transport: any ProfileActivitySocialTransport
    private let context: () -> AccountActivityInteractionContext
    private let journal: any ProfileActivitySocialJournal
    private let fixture: Bool
    private var writing = Set<UUID>()
    init(transport: any ProfileActivitySocialTransport, context: @escaping () -> AccountActivityInteractionContext,
         journal: any ProfileActivitySocialJournal) {
        self.transport = transport; self.context = context; self.journal = journal; fixture = false
    }
    #if DEBUG
    private init(fixtureTransport: any ProfileActivitySocialTransport, context: @escaping () -> AccountActivityInteractionContext,
                 journal: any ProfileActivitySocialJournal) {
        transport = fixtureTransport; self.context = context; self.journal = journal; fixture = true
    }
    static func localFixture(transport: any ProfileActivitySocialTransport, context: @escaping () -> AccountActivityInteractionContext,
                             journal: any ProfileActivitySocialJournal) -> ProfileActivitySocialAdapter {
        .init(fixtureTransport: transport, context: context, journal: journal)
    }
    #endif
    nonisolated static func date(_ value: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    private func begin() throws -> AccountActivityInteractionContext {
        guard fixture || ProfileActivitySocialReleaseGate.productionReady else { throw ProfileActivitySocialError.disabled }
        let c = context()
        guard let viewer = c.viewerID, c.generation >= 0, c.safetyRevision >= 0,
              c.storageScopeID == viewer.uuidString.lowercased(), !AccountDeletionWriteFence.shared.isRetired(viewer), !Task.isCancelled else {
            throw ProfileActivitySocialError.accountChanged
        }
        return c
    }
    private func check(_ c: AccountActivityInteractionContext) throws {
        guard try begin() == c else { throw ProfileActivitySocialError.accountChanged }
    }
    private func validate(_ receipt: ProfileActivitySocialReceipt, row: AccountActivityFeedRow,
                          context c: AccountActivityInteractionContext, pinned: ProfileActivitySocialReceipt? = nil) throws {
        try check(c)
        guard row.readPolicy == .profileOnlyV2, receipt.version == 2, receipt.release_ready == !fixture,
              receipt.viewer_id == c.viewerID, receipt.card_id == row.cardID, receipt.owner_id == row.ownerID,
              receipt.canonical_id == row.canonicalID, receipt.projection_revision == row.revision,
              receipt.projection_revision > 0, receipt.profile_revision > 0, receipt.profile_revision < Int64.max,
              receipt.hasValidRouting else {
            throw ProfileActivitySocialError.malformed
        }
        if let pinned, pinned != receipt { throw ProfileActivitySocialError.changed }
    }
    private func call<T: Decodable>(_ suffix: String, _ parameters: ProfileActivitySocialParameters,
                                    context c: AccountActivityInteractionContext, as type: T.Type) async throws -> T {
        try check(c)
        let data = try await transport.call("soom_activity_social_\(suffix)_candidate_v2", params: parameters)
        try check(c)
        return try JSONDecoder().decode(type, from: data)
    }
    func status(row: AccountActivityFeedRow) async throws -> ProfileActivitySocialStatus {
        let c = try begin()
        let result = try await call("status", .init(p_card_id: row.cardID), context: c, as: ProfileActivitySocialStatus.self)
        try validate(result.receipt, row: row, context: c)
        guard result.state == "ready", (0...1_000_000_000).contains(result.comment_count), (0...1_000_000_000).contains(result.cheer_count),
              result.latest_comment_at.map({ Self.date($0) != nil }) ?? true,
              result.comment_count != 0 || result.latest_comment_at == nil else { throw ProfileActivitySocialError.malformed }
        return result
    }
    private func validateComment(_ value: ProfileActivitySocialComment, receipt: ProfileActivitySocialReceipt) throws {
        guard receipt.permits(source: value.source_kind),
              (value.parent_id == nil ? value.parent_source == nil : value.parent_source == value.source_kind),
              (value.reply_to_id == nil ? value.reply_to_source == nil : value.reply_to_source == value.source_kind) else { throw ProfileActivitySocialError.malformed }
        guard Self.date(value.created_at) != nil, value.body.count <= 500, value.parent_id != value.id,
              value.reply_to_id != value.id, value.mentions.count <= 10,
              Set(value.mentions.map(\.userID)).count == value.mentions.count,
              value.author_profile.map({ $0.id == value.author_id }) ?? true,
              (value.is_deleted ? (value.author_id == nil && value.body.isEmpty && value.mentions.isEmpty && value.author_profile == nil) : value.author_id != nil) else {
            throw ProfileActivitySocialError.malformed
        }
    }
    private func validatePage(_ ids: [ProfileSocialSourceKey], times: [String], cursor: ProfileActivitySocialCursor?, next: ProfileActivitySocialCursor?, limit: Int) throws {
        guard ids.count <= limit, Set(ids).count == ids.count else { throw ProfileActivitySocialError.malformed }
        var previous = cursor
        for (id, time) in zip(ids, times) {
            guard let d = Self.date(time) else { throw ProfileActivitySocialError.malformed }
            if let p = previous {
                guard let pd = Self.date(p.created_at), d > pd || (d == pd && (id.source_kind > (p.source_kind ?? "") || (id.source_kind == p.source_kind && id.id.uuidString.lowercased() > p.id.uuidString.lowercased()))) else {
                    throw ProfileActivitySocialError.malformed
                }
            }
            previous = .init(created_at: time, id: id.id, source_kind: id.source_kind)
        }
        if let next { guard next == previous, !ids.isEmpty else { throw ProfileActivitySocialError.malformed } }
    }
    func comments(row: AccountActivityFeedRow, receipt: ProfileActivitySocialReceipt, after: ProfileActivitySocialCursor? = nil) async throws -> ProfileActivitySocialComments {
        let c = try begin(); try validate(receipt, row: row, context: c)
        guard after == nil || receipt.permits(source: after?.source_kind) else { throw ProfileActivitySocialError.malformed }
        let result = try await call("comments", .init(p_card_id: row.cardID, p_expected: receipt.expected, p_limit: 50,
            p_after_at: after?.created_at, p_after_id: after?.id, p_after_source: after?.source_kind), context: c, as: ProfileActivitySocialComments.self)
        try validate(result.receipt, row: row, context: c, pinned: receipt)
        try validatePage(result.rows.map(\.sourceKey), times: result.rows.map(\.created_at), cursor: after, next: result.next_cursor, limit: 50)
        guard result.parents.count <= 100, Set(result.parents.map(\.sourceKey)).count == result.parents.count else { throw ProfileActivitySocialError.malformed }
        for value in result.rows + result.parents {
            guard value.card_id == row.cardID else { throw ProfileActivitySocialError.malformed }
            try validateComment(value, receipt: receipt)
        }
        let pageIDs = Set(result.rows.map(\.sourceKey))
        guard result.parents.allSatisfy({ parent in !pageIDs.contains(parent.sourceKey) && result.rows.contains(where: { $0.parentKey == parent.sourceKey || $0.replyKey == parent.sourceKey }) }) else {
            throw ProfileActivitySocialError.malformed
        }
        let byID = Dictionary(uniqueKeysWithValues: (result.rows + result.parents).map { ($0.sourceKey, $0) })
        for value in result.rows + result.parents {
            if let parentID = value.parentKey, let root = byID[parentID], root.parent_id != nil { throw ProfileActivitySocialError.malformed }
            if let replyID = value.replyKey, let reply = byID[replyID] {
                guard value.parentKey == (reply.parentKey ?? reply.sourceKey) else { throw ProfileActivitySocialError.malformed }
            }
        }
        return result
    }
    func reactions(row: AccountActivityFeedRow, receipt: ProfileActivitySocialReceipt, after: ProfileActivitySocialCursor? = nil) async throws -> ProfileActivitySocialReactions {
        let c = try begin(); try validate(receipt, row: row, context: c)
        guard after == nil || receipt.permits(source: after?.source_kind) else { throw ProfileActivitySocialError.malformed }
        let result = try await call("reactions", .init(p_card_id: row.cardID, p_expected: receipt.expected, p_limit: 50,
            p_after_at: after?.created_at, p_after_id: after?.id, p_after_source: after?.source_kind), context: c, as: ProfileActivitySocialReactions.self)
        try validate(result.receipt, row: row, context: c, pinned: receipt)
        try validatePage(result.rows.map(\.sourceKey), times: result.rows.map(\.created_at), cursor: after, next: result.next_cursor, limit: 50)
        guard Set(result.rows.map(\.user_id)).count == result.rows.count,
              result.rows.allSatisfy({ r in r.card_id == row.cardID && receipt.permits(source: r.source_kind) && r.provenance.map({ !$0.isEmpty && Set($0).count == $0.count && $0.contains(r.sourceKey) && $0.allSatisfy({ receipt.permits(source: $0.source_kind) }) }) == true && r.reaction_type == "cheer" && (r.author_profile.map({ $0.id == r.user_id }) ?? true) }) else { throw ProfileActivitySocialError.malformed }
        return result
    }
    func mentions(row: AccountActivityFeedRow, receipt: ProfileActivitySocialReceipt, query: String) async throws -> [FeedProfileDTO] {
        let c = try begin(); try validate(receipt, row: row, context: c)
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...100).contains(term.count) else { return [] }
        let result = try await call("mentions", .init(p_card_id: row.cardID, p_expected: receipt.expected, p_limit: 5, p_query: term), context: c, as: ProfileActivitySocialMentions.self)
        try validate(result.receipt, row: row, context: c, pinned: receipt)
        guard result.rows.count <= 5, Set(result.rows.map(\.id)).count == result.rows.count,
              result.rows.allSatisfy({ $0.id != c.viewerID && $0.handle?.isEmpty == false }) else { throw ProfileActivitySocialError.malformed }
        return result.rows
    }
    func pending(row: AccountActivityFeedRow) throws -> [ProfileActivitySocialPending] {
        let c = try begin()
        return try journal.read().filter { $0.receipt.viewer_id == c.viewerID && $0.receipt.card_id == row.cardID }
    }
    func hasEarlierPending(row: AccountActivityFeedRow, receipt: ProfileActivitySocialReceipt) throws -> Bool {
        let c = try begin(); try validate(receipt, row: row, context: c)
        guard !fixture, let viewer = c.viewerID else { return false }
        for policy in [AccountActivityReadPolicy.approvedFollowersV1, .profileOnlyV2] {
            if try FileAccountActivityCommentJournal(ownerID: viewer, readPolicy: policy).read().contains(where: { $0.target.cardID == row.cardID }) { return true }
        }
        for source in receipt.read_sources ?? [] where source.source_kind == "legacy" {
            if try FeedCommentPendingStore.read(viewer: viewer, post: source.source_id) != nil { return true }
        }
        return false
    }
    private func parameters(_ request: ProfileActivitySocialPending) -> ProfileActivitySocialParameters {
        .init(p_card_id: request.receipt.card_id, p_expected: request.receipt.expected,
              p_request_id: request.id, p_operation: request.operation, p_payload: request.payload)
    }
    private func verifyResult(_ value: ProfileActivitySocialMutationResult, request: ProfileActivitySocialPending,
                              row: AccountActivityFeedRow, context c: AccountActivityInteractionContext) throws {
        try validate(value.receipt, row: row, context: c, pinned: request.receipt)
        guard value.request_id == request.id, value.operation == request.operation,
              ["found", "absent"].contains(value.state), value.state != "found" || value.payload == request.payload else {
            throw ProfileActivitySocialError.malformed
        }
        if value.state == "found" {
            guard let result = value.result else { throw ProfileActivitySocialError.malformed }
            switch request.operation {
            case "comment_add": guard result.source_kind == request.payload.source_kind, result.comment_id == request.payload.comment_id else { throw ProfileActivitySocialError.malformed }
            case "comment_delete": guard result.source_kind == request.payload.source_kind, result.comment_id == request.payload.comment_id, result.deleted == true else { throw ProfileActivitySocialError.malformed }
            case "cheer_set": guard result.desired == request.payload.desired else { throw ProfileActivitySocialError.malformed }
            default: throw ProfileActivitySocialError.malformed
            }
        }
    }
    private func remove(_ request: ProfileActivitySocialPending) throws {
        var all = try journal.read(); all.removeAll { $0.id == request.id && $0.receipt.viewer_id == request.receipt.viewer_id }
        try journal.write(all)
    }
    private func execute(row: AccountActivityFeedRow, request: ProfileActivitySocialPending) async throws {
        let c = try begin(); try validate(request.receipt, row: row, context: c)
        guard !writing.contains(row.cardID), try pending(row: row).isEmpty, !(try hasEarlierPending(row: row, receipt: request.receipt)) else { throw ProfileActivitySocialError.pendingWrite }
        writing.insert(row.cardID); defer { writing.remove(row.cardID) }
        var all = try journal.read(); all.append(request); try journal.write(all)
        // Every transport/validation failure retains the exact request. Never infer rollback.
        let value: ProfileActivitySocialMutationResult
        do {
            value = try await call("mutate", parameters(request), context: c, as: ProfileActivitySocialMutationResult.self)
        } catch let rejected as PostgrestError where FeedCommentFailurePolicy.isDefinitiveFirstRejection(code: rejected.code) {
            // Only this first, newly generated request is covered by an explicit SQL rollback.
            // Recovery requests never use this path; a timed-out older attempt stays journaled.
            try check(c)
            try remove(request)
            throw rejected
        }
        try verifyResult(value, request: request, row: row, context: c)
        guard value.state == "found" else { throw ProfileActivitySocialError.pendingWrite }
        try remove(request)
    }
    func addComment(row: AccountActivityFeedRow, receipt: ProfileActivitySocialReceipt, body: String,
                    parentID: UUID?, mentions: [FeedMentionDraft.Selection], parentSource: String? = nil) async throws {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...500).contains(body.count), mentions.count <= 10, Set(mentions.map(\.userID)).count == mentions.count else { throw ProfileActivitySocialError.invalidRequest }
        let source = parentID == nil ? receipt.write_backing : parentSource
        guard receipt.permits(source: source), parentID != nil || parentSource == nil else { throw ProfileActivitySocialError.invalidRequest }
        let id = UUID()
        try await execute(row: row, request: .init(id: id, receipt: receipt, operation: "comment_add",
            payload: .init(comment_id: id, body: body, mentions: mentions.sorted { $0.userID.uuidString.lowercased() < $1.userID.uuidString.lowercased() }, parent_comment_id: parentID, source_kind: source)))
    }
    func deleteComment(row: AccountActivityFeedRow, receipt: ProfileActivitySocialReceipt, comment: ProfileActivitySocialComment) async throws {
        let c = try begin()
        guard comment.card_id == row.cardID, receipt.permits(source: comment.source_kind), comment.author_id == c.viewerID, !comment.is_deleted else { throw ProfileActivitySocialError.invalidRequest }
        try await execute(row: row, request: .init(id: UUID(), receipt: receipt, operation: "comment_delete", payload: .init(comment_id: comment.id, source_kind: comment.source_kind)))
    }
    func setCheer(row: AccountActivityFeedRow, receipt: ProfileActivitySocialReceipt, desired: Bool) async throws {
        try await execute(row: row, request: .init(id: UUID(), receipt: receipt, operation: "cheer_set", payload: .init(desired: desired)))
    }
    /// A user-initiated recovery first resolves the old request, then optionally retries that same request only.
    func resolve(row: AccountActivityFeedRow, request: ProfileActivitySocialPending, retryIfAbsent: Bool) async throws -> Bool {
        let c = try begin(); try validate(request.receipt, row: row, context: c)
        guard !writing.contains(row.cardID), try pending(row: row).contains(request) else { throw ProfileActivitySocialError.pendingWrite }
        writing.insert(row.cardID); defer { writing.remove(row.cardID) }
        let status = try await call("request_status", parameters(request), context: c, as: ProfileActivitySocialMutationResult.self)
        try verifyResult(status, request: request, row: row, context: c)
        if status.state == "found" { try remove(request); return true }
        guard retryIfAbsent else { return false }
        let result = try await call("mutate", parameters(request), context: c, as: ProfileActivitySocialMutationResult.self)
        try verifyResult(result, request: request, row: row, context: c)
        guard result.state == "found" else { throw ProfileActivitySocialError.pendingWrite }
        try remove(request); return true
    }
}



/// Canonical interaction identity. This, never a UI surrogate, is sent to the server.

/// UI-only compatibility bridge for UUID-based FeedComment components.
/// Retain only within one verified card/account/lineage presentation scope.
struct ProfileSocialPresentationIdentity {
    private var forward: [ProfileSocialSourceKey: UUID] = [:]
    private var reverse: [UUID: ProfileSocialSourceKey] = [:]

    mutating func presentationID(for key: ProfileSocialSourceKey) -> UUID {
        if let existing = forward[key] { return existing }
        var candidate = UUID()
        while reverse[candidate] != nil { candidate = UUID() }
        forward[key] = candidate
        reverse[candidate] = key
        return candidate
    }

    func existingID(for key: ProfileSocialSourceKey) -> UUID? { forward[key] }

    func sourceKey(for presentationID: UUID) -> ProfileSocialSourceKey? {
        reverse[presentationID]
    }

    mutating func reset() {
        forward.removeAll()
        reverse.removeAll()
    }
}
