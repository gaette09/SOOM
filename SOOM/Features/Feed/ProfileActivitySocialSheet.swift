import SwiftUI
import Supabase
import UIKit

extension ProfileActivitySocialAdapter {
    @MainActor static func live(row: AccountActivityFeedRow? = nil, context: @escaping () -> AccountActivityInteractionContext) -> ProfileActivitySocialAdapter? {
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_PROFILE_SOCIAL_QA"] == "1", let row {
            let store = ProfileActivitySocialUIFixture.shared(row: row)
            return .localFixture(transport: store, context: context, journal: store.journal)
        }
        #endif
        guard ProfileActivitySocialReleaseGate.productionReady, let viewer = context().viewerID,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
              client.auth.currentSession?.user.id == viewer else { return nil }
        return .init(transport: SupabaseProfileActivitySocialTransport(client: client), context: {
            let value = context()
            return ProfileActivitySocialLiveGate.context(value, sessionID: client.auth.currentSession?.user.id,
                isActive: UIApplication.shared.applicationState == .active)
        }, journal: FileProfileActivitySocialJournal(owner: viewer))
    }
}

/// The backing is server-selected and pinned, not inferred from legacy-detail availability.
struct ProfileActivitySocialCommentsSheet: View {
    let row: AccountActivityFeedRow
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @EnvironmentObject private var storage: HealthAccountStorageController
    @Environment(\.scenePhase) private var scene
    @Environment(\.dismiss) private var dismiss
    @State private var adapter: ProfileActivitySocialAdapter?
    @State private var receipt: ProfileActivitySocialReceipt?
    @State private var rows: [ProfileActivitySocialComment] = []
    @State private var cursor: ProfileActivitySocialCursor?
    @State private var pending: [ProfileActivitySocialPending] = []
    @State private var earlierPending = false
    @State private var identities = ProfileSocialPresentationIdentity()
    @State private var identityScope: String?
    @State private var loadedKey: String?
    @State private var requestID: UUID?
    @State private var writing = false
    @State private var error: String?
    private var key: String { "\(row.cardID):\(row.revision):\(safety.accountGeneration):\(safety.revision):\(scene == .active):\(storage.scopeID)" }
    private var isVisible: Bool { loadedKey == key && scene == .active && safety.canUseSocial }
    private var comments: [FeedComment] { guard isVisible, let viewer = safety.viewerID else { return [] }; return rows.filter { !$0.is_deleted }.compactMap { value in
        guard let id = identities.existingID(for: value.sourceKey), let raw = try? value.display(viewer: viewer) else { return nil }
        return FeedComment(id: id, authorId: raw.authorId, body: raw.body, createdAt: raw.createdAt, isViewerAuthor: raw.isViewerAuthor, profile: raw.profile, parentCommentID: value.parentKey.flatMap { identities.existingID(for: $0) }, isDeleted: false)
    } }
    private var tombstones: [FeedCommentTombstone] {
        guard isVisible else { return [] }
        return rows.filter(\.is_deleted).compactMap { r in
            identities.existingID(for: r.sourceKey).flatMap { id in ProfileActivitySocialAdapter.date(r.created_at).map { .init(id: id, createdAt: $0, parentID: r.parentKey.flatMap { identities.existingID(for: $0) }) } }
        }
    }
    private var references: [UUID: [FeedMentionReference]] {
        guard isVisible else { return [:] }
        return Dictionary(uniqueKeysWithValues: rows.compactMap { value -> (UUID, [FeedMentionReference])? in
            guard let id = identities.existingID(for: value.sourceKey) else { return nil }; return (id, value.mentions.map { .init(userID: $0.userID, handle: $0.handle) })
        })
    }
    var body: some View {
        SocialAccessBoundary {
            NavigationStack {
                VStack(spacing: 0) {
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red).padding()
                        Button("댓글 다시 확인") { Task { await load(reset: true) } }.disabled(writing || requestID != nil)
                    }
                    if earlierPending {
                        Text("이전 버전에서 전송한 댓글의 결과 확인이 필요해요. 기존 요청을 보존하고 새 댓글 전송을 중지했어요.")
                            .font(.caption).padding()
                    }
                    if !pending.isEmpty {
                        Text("전송 결과가 확정되지 않은 요청이 있어요. 새 요청 대신 기존 요청을 확인합니다.").font(.caption).padding()
                        Button("기존 요청 확인 및 재시도") { Task { await resolve() } }.disabled(writing || requestID != nil)
                            .accessibilityIdentifier("feed.profileSocial.recover")
                    }
                    if cursor != nil && isVisible {
                        Button("댓글 더 보기") { Task { await load(reset: false) } }.disabled(writing || requestID != nil)
                    }
                    FeedCommentListView(comments: comments, tombstones: tombstones, nativeReferences: references,
                        scopedMentionSearch: { term in try await searchMentions(term) },
                        isLoading: !isVisible || requestID != nil || writing || error != nil || earlierPending || !pending.isEmpty,
                        onSubmit: { text in try await submit(text, parent: nil, mentions: []) },
                        onDelete: { comment in try await delete(comment) },
                        onAtomicSubmit: { text, parent, mentions in try await submit(text, parent: parent, mentions: mentions) })
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("feed.profileSocial.comments")
                .accessibilityValue(qaTrace)
                .task(id: key) { await load(reset: true) }
                .toolbar {
                    #if DEBUG && targetEnvironment(simulator)
                    if ProcessInfo.processInfo.environment["SOOM_PROFILE_SOCIAL_BOUNDARY_QA"] == "1" && ReviewDemoMode.isActive {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("권한 철회 시험") {
                                ProfileActivitySocialUIFixture.shared(row: row).available = false
                                rows = []; receipt = nil; loadedKey = nil
                                Task { await load(reset: true) }
                            }.accessibilityIdentifier("feed.profileSocial.qa.revoke")
                        }
                    }
                    #endif
                }
                .onChange(of: safety.accountGeneration) { _, _ in rows = []; receipt = nil; adapter = nil; dismiss() }
            }
        }.independentFeedReturnScope().presentationDetents([.fraction(0.72), .large]).presentationDragIndicator(.visible)
    }
    private var qaTrace: String {
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_PROFILE_SOCIAL_QA"] == "1" {
            return ProfileActivitySocialUIFixture.shared(row: row).trace
        }
        #endif
        return ""
    }
    @MainActor private func configure() -> ProfileActivitySocialAdapter? {
        if let adapter { return adapter }
        let value = ProfileActivitySocialAdapter.live(row: row, context: {
            .init(viewerID: safety.canUseSocial && scene == .active ? safety.viewerID : nil,
                  generation: safety.accountGeneration, safetyRevision: safety.revision, storageScopeID: storage.scopeID)
        })
        adapter = value; return value
    }
    @MainActor private func load(reset: Bool) async {
        if !reset && (requestID != nil || writing) { return }
        let expected = key, token = UUID(); requestID = token
        defer { if requestID == token { requestID = nil } }
        if reset { rows = []; receipt = nil; cursor = nil; loadedKey = nil; pending = []; earlierPending = false; error = nil }
        guard scene == .active, safety.canUseSocial, let adapter = configure() else { return }
        do {
            let target: ProfileActivitySocialReceipt
            if reset { target = try await adapter.status(row: row).receipt }
            else if let receipt { target = receipt }
            else { throw ProfileActivitySocialError.changed }
            let page = try await adapter.comments(row: row, receipt: target, after: reset ? nil : cursor)
            let pendingRequests = try adapter.pending(row: row)
            let oldPending = try adapter.hasEarlierPending(row: row, receipt: target)
            guard !Task.isCancelled, key == expected, requestID == token else { return }
            let scope = expected + ":" + (target.source_revision ?? "missing")
            if identityScope != scope { identities.reset(); identityScope = scope }
            for value in page.parents + page.rows {
                _ = identities.presentationID(for: value.sourceKey)
                if let key = value.parentKey { _ = identities.presentationID(for: key) }
                if let key = value.replyKey { _ = identities.presentationID(for: key) }
            }
            var byID = Dictionary(uniqueKeysWithValues: (reset ? [] : rows).map { ($0.sourceKey, $0) })
            for value in page.parents + page.rows { byID[value.sourceKey] = value }
            rows = byID.values.sorted { a, b in
                let ad = ProfileActivitySocialAdapter.date(a.created_at) ?? .distantPast, bd = ProfileActivitySocialAdapter.date(b.created_at) ?? .distantPast
                return ad == bd ? ((a.source_kind ?? "") == (b.source_kind ?? "") ? a.id.uuidString < b.id.uuidString : (a.source_kind ?? "") < (b.source_kind ?? "")) : ad < bd
            }
            receipt = target; cursor = page.next_cursor; pending = pendingRequests; earlierPending = oldPending; loadedKey = expected; error = nil
        } catch {
            guard key == expected, requestID == token, !Task.isCancelled else { return }
            rows = []; receipt = nil; loadedKey = nil
            self.error = "댓글 접근을 확인하지 못했어요. 다른 대화로 전환하지 않고 기존 내용을 보존했어요."
        }
    }
    @MainActor private func searchMentions(_ term: String) async throws -> [FeedProfileDTO] {
        guard isVisible, let adapter, let receipt else { throw ProfileActivitySocialError.changed }
        let expected = key
        let result = try await adapter.mentions(row: row, receipt: receipt, query: term)
        guard isVisible, expected == key else { throw ProfileActivitySocialError.changed }
        return result
    }
    @MainActor private func submit(_ text: String, parent: FeedComment?, mentions: [FeedMentionDraft.Selection]) async throws {
        guard isVisible, !writing, requestID == nil, !earlierPending, pending.isEmpty, let adapter, let receipt else { throw ProfileActivitySocialError.pendingWrite }
        let expected = key; writing = true
        do {
            let parentKey = parent.flatMap { identities.sourceKey(for: $0.id) }
            guard parent == nil || (parentKey != nil && rows.contains(where: { $0.sourceKey == parentKey && !$0.is_deleted })) else { throw ProfileActivitySocialError.changed }
            try await adapter.addComment(row: row, receipt: receipt, body: text, parentID: parentKey?.id, mentions: mentions, parentSource: parentKey?.source_kind)
            writing = false
            guard expected == key else { throw ProfileActivitySocialError.accountChanged }
            await load(reset: true)
        } catch {
            writing = false
            if expected == key { pending = (try? adapter.pending(row: row)) ?? pending }
            throw error
        }
    }
    @MainActor private func delete(_ comment: FeedComment) async throws {
        guard isVisible, !writing, requestID == nil, !earlierPending, pending.isEmpty, let adapter, let receipt,
              let sourceKey = identities.sourceKey(for: comment.id), let raw = rows.first(where: { $0.sourceKey == sourceKey }), raw.author_id == safety.viewerID else { throw ProfileActivitySocialError.invalidRequest }
        let expected = key; writing = true
        do {
            try await adapter.deleteComment(row: row, receipt: receipt, comment: raw)
            writing = false
            guard expected == key else { throw ProfileActivitySocialError.accountChanged }
            await load(reset: true)
        } catch {
            writing = false
            if expected == key { pending = (try? adapter.pending(row: row)) ?? pending }
            throw error
        }
    }
    @MainActor private func resolve() async {
        guard isVisible, !writing, let adapter, let request = pending.first else { return }
        let expected = key; writing = true
        do {
            _ = try await adapter.resolve(row: row, request: request, retryIfAbsent: true)
            writing = false
            guard expected == key else { return }
            await load(reset: true)
        } catch {
            writing = false
            if expected == key { self.error = "기존 요청의 결과를 확인하지 못했어요. 요청을 보존했으며 새로운 요청은 보내지 않았어요." }
        }
    }
}

struct ProfileActivitySocialCheersSheet: View {
    let row: AccountActivityFeedRow
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @EnvironmentObject private var storage: HealthAccountStorageController
    @Environment(\.scenePhase) private var scene
    @State private var people: [ProfileActivitySocialReaction] = []
    @State private var receipt: ProfileActivitySocialReceipt?
    @State private var cursor: ProfileActivitySocialCursor?
    @State private var verified: String?
    @State private var requestID: UUID?
    @State private var error: String?
    private var key: String { "\(row.cardID):\(row.revision):\(safety.accountGeneration):\(safety.revision):\(scene == .active):\(storage.scopeID)" }
    var body: some View {
        SocialAccessBoundary {
            NavigationStack {
                List {
                    if let error { Text(error); Button("다시 확인") { Task { await load(reset: true) } } }
                    if verified == key && scene == .active {
                        ForEach(people, id: \.user_id) { person in
                            if let profile = person.author_profile, !safety.isBlocked(person.user_id) {
                                SOOMProfileLink(userID: person.user_id) {
                                    HStack { SOOMAvatarView(userID: person.user_id, avatarPath: profile.avatarPath, size: 36); Text(profile.displayName) }
                                }
                            }
                        }
                        if cursor != nil { Button("더 보기") { Task { await load(reset: false) } }.disabled(requestID != nil) }
                    } else if error == nil { ProgressView("응원 확인 중") }
                }.navigationTitle("응원").task(id: key) { await load(reset: true) }
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() } } }
                    .accessibilityIdentifier("feed.profileSocial.cheers")
            }
        }.soomProfileModalHandoff().independentFeedReturnScope().presentationDetents([.medium, .large])
    }
    @MainActor private func load(reset: Bool) async {
        if !reset && requestID != nil { return }
        let expected = key, token = UUID(); requestID = token
        defer { if requestID == token { requestID = nil } }
        if reset { people = []; receipt = nil; cursor = nil; verified = nil; error = nil }
        guard scene == .active, let adapter = ProfileActivitySocialAdapter.live(row: row, context: {
            .init(viewerID: safety.canUseSocial && scene == .active ? safety.viewerID : nil,
                  generation: safety.accountGeneration, safetyRevision: safety.revision, storageScopeID: storage.scopeID)
        }) else { return }
        do {
            let target: ProfileActivitySocialReceipt
            if reset { target = try await adapter.status(row: row).receipt }
            else if let receipt { target = receipt }
            else { throw ProfileActivitySocialError.changed }
            let page = try await adapter.reactions(row: row, receipt: target, after: reset ? nil : cursor)
            guard !Task.isCancelled, key == expected, requestID == token else { return }
            let known = Set(people.map(\.user_id)); guard page.rows.allSatisfy({ !known.contains($0.user_id) }) else { throw ProfileActivitySocialError.malformed }; people += page.rows
            receipt = target; cursor = page.next_cursor; verified = expected; error = nil
        } catch {
            guard !Task.isCancelled, key == expected, requestID == token else { return }
            people = []; verified = nil; self.error = "응원 목록을 확인하지 못했어요."
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Synthetic UI fixture only. Never invokes a server or reads real comment content.
@MainActor private final class ProfileActivitySocialUIFixture: ProfileActivitySocialTransport {
    static var stores: [UUID: ProfileActivitySocialUIFixture] = [:]
    static func shared(row: AccountActivityFeedRow) -> ProfileActivitySocialUIFixture {
        if let store = stores[row.cardID] { return store }
        let store = ProfileActivitySocialUIFixture(row: row); stores[row.cardID] = store; return store
    }
    let row: AccountActivityFeedRow
    let journal = MemoryProfileActivitySocialJournal()
    private var comments: [[String: Any]] = []
    private var cheered = false
    private var writes: [UUID: Data] = [:]
    var available = true
    private var mixedQA: Bool { ProcessInfo.processInfo.environment["SOOM_PROFILE_SOCIAL_MIXED_QA"] == "1" }
    private var mutationCalls = 0
    private var statusCalls = 0
    private var requestIDs = Set<UUID>()
    private var timedOut = false
    var trace: String { "mutations \(mutationCalls), status \(statusCalls), requests \(requestIDs.count)" }
    private let participant = UUID(uuidString: "00000000-0000-4000-8000-000000000157")!
    private let initialComment = UUID(uuidString: "00000000-0000-4000-8000-000000000158")!
    init(row: AccountActivityFeedRow) {
        self.row = row
        comments = [["id":initialComment.uuidString,"card_id":row.cardID.uuidString,"author_id":participant.uuidString,
                     "body":"함께 응원해요", "created_at":ISO8601DateFormatter().string(from:Date().addingTimeInterval(-60)),
                     "parent_id":NSNull(),"reply_to_id":NSNull(),"is_deleted":false,"mentions":[],
                     "author_profile":profile(participant, name:"테스트 친구", handle:"soom_test")]]
        if mixedQA {
            comments[0]["source_kind"] = "legacy"
            var native = comments[0]; native["source_kind"] = "native"; native["body"] = "원본 native 대화"
            native["author_id"] = ReviewDemoMode.userID.uuidString
            native["author_profile"] = profile(ReviewDemoMode.userID,name:"나",handle:"my_test")
            comments.append(native)
        }
    }
    private func timestamp() -> String {
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.string(from: Date().addingTimeInterval(Double(comments.count) / 1000))
    }
    private func profile(_ id: UUID, name: String, handle: String) -> [String:Any] {
        ["id":id.uuidString,"display_name":name,"handle":handle,"avatar_path":NSNull()]
    }
    private var receipt: ProfileActivitySocialReceipt {
        var value = ProfileActivitySocialReceipt(version:2,viewer_id:ReviewDemoMode.userID,card_id:row.cardID,owner_id:row.ownerID,canonical_id:row.canonicalID,
              projection_revision:row.revision,profile_revision:1,
              backing:ProcessInfo.processInfo.environment["SOOM_PROFILE_SOCIAL_NATIVE_QA"] == "1" ? "native" : "legacy",
              source_id:ProcessInfo.processInfo.environment["SOOM_PROFILE_SOCIAL_NATIVE_QA"] == "1" ? row.cardID : row.canonicalID,release_ready:false)
        value.write_backing = value.backing
        value.read_sources = [.init(source_kind: value.backing, source_id: value.source_id)]
        value.source_revision = String(repeating: "a", count: 32)
        if mixedQA {
            return .init(version:value.version,viewer_id:value.viewer_id,card_id:value.card_id,owner_id:value.owner_id,canonical_id:value.canonical_id,
                projection_revision:value.projection_revision,profile_revision:value.profile_revision,backing:"mixed",source_id:row.canonicalID,release_ready:false,
                write_backing:"legacy",read_sources:[.init(source_kind:"legacy",source_id:row.canonicalID),.init(source_kind:"native",source_id:row.cardID)],source_revision:value.source_revision)
        }
        return value
    }
    private func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) }
    private func response(_ fields: [String:Any]) throws -> Data {
        var value = fields; value["receipt"] = try object(receipt)
        let source = receipt.write_backing!
        if let items = value["rows"] as? [[String: Any]] {
            value["rows"] = items.map { item -> [String: Any] in
                var row = item
                if row["body"] != nil {
                    let actualSource = row["source_kind"] as? String ?? source
                    row["source_kind"] = actualSource
                    row["parent_source"] = row["parent_id"] is String ? actualSource : NSNull()
                    row["reply_to_source"] = row["reply_to_id"] is String ? actualSource : NSNull()
                } else if row["reaction_type"] != nil {
                    row["source_kind"] = source
                    row["provenance"] = [["source_kind": source, "id": row["id"]!]]
                }
                return row
            }
        }
        if var result = value["result"] as? [String: Any], result["comment_id"] != nil {
            if result["source_kind"] == nil { result["source_kind"] = source }; value["result"] = result
        }
        return try JSONSerialization.data(withJSONObject:value)
    }
    func call(_ name: String, params p: ProfileActivitySocialParameters) async throws -> Data {
        guard available else { throw ProfileActivitySocialError.changed }
        guard p.p_card_id == row.cardID else { throw ProfileActivitySocialError.changed }
        if name.contains("_status_") && !name.contains("request_status") {
            let live = comments.filter { ($0["is_deleted"] as? Bool) == false }
            return try response(["state":"ready","comment_count":live.count,"latest_comment_at":live.last?["created_at"] ?? NSNull(),"cheer_count":cheered ? 1 : 0,"viewer_has_cheered":cheered])
        }
        guard p.p_expected == receipt.expected else { throw ProfileActivitySocialError.changed }
        if name.contains("_comments_") {
            return try response(["rows":p.p_after_id == nil ? comments : [],"parents":[],"next_cursor":NSNull()])
        }
        if name.contains("_reactions_") {
            let rows: [[String:Any]] = cheered ? [["id":initialComment.uuidString,"card_id":row.cardID.uuidString,"user_id":ReviewDemoMode.userID.uuidString,
                "reaction_type":"cheer","created_at":"2026-11-14T00:00:00Z","author_profile":profile(ReviewDemoMode.userID,name:"나",handle:"my_test")]] : []
            return try response(["rows":rows,"next_cursor":NSNull()])
        }
        if name.contains("_mentions_") { return try response(["rows":[profile(participant,name:"테스트 친구",handle:"soom_test")]]) }
        guard let id = p.p_request_id, let operation = p.p_operation, let payload = p.p_payload else { throw ProfileActivitySocialError.invalidRequest }
        requestIDs.insert(id)
        if name.contains("request_status") { statusCalls += 1 } else if name.contains("_mutate_") { mutationCalls += 1 }
        if let written = writes[id] { return written }
        if name.contains("request_status") {
            return try response(["request_id":id.uuidString,"operation":operation,"payload":object(payload),"state":"absent","result":NSNull()])
        }
        guard name.contains("_mutate_") else { throw ProfileActivitySocialError.invalidRequest }
        let result: [String:Any]
        switch operation {
        case "cheer_set":
            guard let desired = payload.desired else { throw ProfileActivitySocialError.invalidRequest }
            cheered = desired; result = ["desired":desired]
        case "comment_add":
            guard let commentID = payload.comment_id, let body = payload.body, receipt.permits(source: payload.source_kind) else { throw ProfileActivitySocialError.invalidRequest }
            comments.append(["id":commentID.uuidString,"card_id":row.cardID.uuidString,"author_id":ReviewDemoMode.userID.uuidString,
                "source_kind":payload.source_kind!,"body":body,"created_at":timestamp(),"parent_id":payload.parent_comment_id?.uuidString as Any? ?? NSNull(),
                "reply_to_id":payload.parent_comment_id?.uuidString as Any? ?? NSNull(),"is_deleted":false,"mentions":try object(payload.mentions ?? []),
                "author_profile":profile(ReviewDemoMode.userID,name:"나",handle:"my_test")])
            result = ["comment_id":commentID.uuidString,"source_kind":payload.source_kind!]
        case "comment_delete":
            guard let commentID = payload.comment_id, let index = comments.firstIndex(where: { $0["id"] as? String == commentID.uuidString && ($0["source_kind"] as? String ?? receipt.write_backing) == payload.source_kind }),
                  comments[index]["author_id"] as? String == ReviewDemoMode.userID.uuidString else { throw ProfileActivitySocialError.invalidRequest }
            comments[index]["is_deleted"] = true; comments[index]["author_id"] = NSNull(); comments[index]["author_profile"] = NSNull()
            comments[index]["body"] = ""; comments[index]["mentions"] = []
            result = ["comment_id":commentID.uuidString,"source_kind":payload.source_kind!,"deleted":true]
        default: throw ProfileActivitySocialError.invalidRequest
        }
        let value = try response(["request_id":id.uuidString,"operation":operation,"payload":object(payload),"state":"found","result":result])
        writes[id] = value
        if ProcessInfo.processInfo.environment["SOOM_PROFILE_SOCIAL_TIMEOUT_QA"] == "1", !timedOut {
            timedOut = true; throw URLError(.timedOut)
        }
        return value
    }
}
#endif
