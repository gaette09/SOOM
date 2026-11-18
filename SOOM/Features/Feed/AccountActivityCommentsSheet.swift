import SwiftUI
import Supabase

/// Native projection identities are never passed into legacy moderation/photo/comment APIs.
struct AccountActivityCommentsSheet: View {
    let row: AccountActivityFeedRow
    var preview: Bool = false
    @EnvironmentObject private var storage: HealthAccountStorageController
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var adapter: AccountActivityInteractionAdapter?
    @State private var comments: [FeedComment] = []
    @State private var references: [UUID: [FeedMentionReference]] = [:]
    @State private var cursor: AccountActivityCommentCursor?
    @State private var hasMore = false
    @State private var busy = false
    @State private var error: String?
    @State private var pending: [AccountActivityCommentRequest] = []
    private var target: AccountActivityInteractionTarget { .native(cardID: row.cardID, ownerID: row.ownerID) }
    var body: some View {
        SocialAccessBoundary(allowActivityPreview: preview) {
            NavigationStack {
                VStack(spacing: 0) {
                    if let error { Text(error).font(.caption).foregroundStyle(.red).padding(); Button("댓글 다시 확인") { Task { await load(reset: true) } }.disabled(busy) }
                    if !pending.isEmpty {
                        Text("전송 결과 확인이 필요한 댓글이 있어요. 새 댓글 대신 기존 요청을 확인합니다.").font(.caption).padding()
                        Button("같은 댓글 전송 결과 확인") { Task { await resolvePending() } }.disabled(busy)
                        Button("미전송 확인 후 원고 취소", role: .destructive) { Task { await discardPending() } }.disabled(busy)
                    }
                    if hasMore { Button("댓글 더 보기") { Task { await load(reset: false) } }.disabled(busy) }
                    FeedCommentListView(comments: comments, nativeReferences: references, nativeActivityPreview: preview, isLoading: busy || error != nil,
                        onSubmit: { text in try await submit(text, parent: nil, selections: []) },
                        onDelete: { comment in
                            guard let adapter else { throw AccountActivityInteractionError.disabled }
                            try await adapter.delete(target, commentID: comment.id, authorID: comment.authorId)
                            await load(reset: true)
                        }, onAtomicSubmit: { text, parent, selections in
                            try await submit(text, parent: parent, selections: selections)
                        })
                }.task { configure(); await load(reset: true) }
                .onChange(of: safety.accountGeneration) { _, _ in comments = []; references = [:]; dismiss() }
                .onChange(of: safety.revision) { _, _ in comments = []; references = [:]; Task { await load(reset: true) } }
            }
        }.presentationDetents([.fraction(0.72), .large]).presentationDragIndicator(.visible)
    }
    @MainActor private func configure() {
        #if DEBUG && targetEnvironment(simulator)
        if adapter == nil, ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_NATIVE_COMMENT_QA"] == "1" {
            adapter = .localFixture(transport: AccountActivityCommentUIFixture.shared(card: row.cardID), context: {
                .init(viewerID: ReviewDemoMode.userID, generation: safety.accountGeneration,
                      safetyRevision: safety.revision, storageScopeID: ReviewDemoMode.userID.uuidString.lowercased())
            })
            return
        }
        #endif
        guard adapter == nil, ((preview && row.readPolicy == .approvedFollowersV1) || row.readPolicy.interactionsProductionReady),
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { return }
        adapter = AccountActivityInteractionAdapter(transport: SupabaseAccountActivityInteractionTransport(client: client, preview: preview, readPolicy: row.readPolicy), context: {
            .init(viewerID: (safety.canUseSocial || (preview && safety.canUseActivityPreview)) ? client.auth.currentSession?.user.id : nil,
                  generation: safety.accountGeneration, safetyRevision: safety.revision, storageScopeID: storage.scopeID)
        }, preview: preview)
    }
    @MainActor private func load(reset: Bool) async {
        guard !busy else { return }
        guard let adapter else { error = "댓글 연결을 검증 중입니다."; return }
        busy = true; defer { busy = false }
        let generation = safety.accountGeneration, revision = safety.revision
        if reset { comments = []; references = [:]; cursor = nil; hasMore = false }
        do {
            let rows = try await adapter.loadComments(target, after: reset ? nil : cursor)
            guard generation == safety.accountGeneration, revision == safety.revision, !Task.isCancelled else { return }
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallback = ISO8601DateFormatter()
            let next = try rows.map { value -> FeedComment in
                guard let date = formatter.date(from: value.created_at) ?? fallback.date(from: value.created_at) else { throw AccountActivityInteractionError.invalidResponse }
                return FeedComment(id: value.id, authorId: value.author_id, body: value.body, createdAt: date,
                    isViewerAuthor: value.author_id == safety.viewerID, parentCommentID: value.parent_id, isDeleted: value.is_deleted)
            }
            let existing = Set(comments.map(\.id))
            comments += next.filter { !existing.contains($0.id) }
            for value in rows { references[value.id] = value.mentions.map { .init(userID: $0.user_id, handle: $0.handle) } }
            if let last = rows.last { cursor = .init(createdAt: last.created_at, id: last.id) }
            hasMore = rows.count == 50; pending = try adapter.pendingRequests(target); error = nil
        } catch { comments = []; references = [:]; self.error = "댓글을 확인할 수 없어요. 공개 범위와 연결 상태를 다시 확인해 주세요." }
    }
    @MainActor private func submit(_ text: String, parent: FeedComment?, selections: [FeedMentionDraft.Selection]) async throws {
        guard let adapter, !busy else { throw AccountActivityInteractionError.disabled }
        pending = try adapter.pendingRequests(target)
        guard pending.isEmpty else { throw AccountActivityInteractionError.uncertainWrite }
        let request = AccountActivityCommentRequest(id: UUID(), body: text,
            mentions: selections.map { .init(user_id: $0.userID, handle: $0.handle) }, parentID: parent?.id)
        do { _ = try await adapter.submit(target, request: request) }
        catch { pending = (try? adapter.pendingRequests(target)) ?? []; throw error }
        await load(reset: true)
    }
    @MainActor private func discardPending() async {
        guard !busy, let adapter, let first = pending.first else { return }
        busy = true
        do { let result = try await adapter.discardConfirmedAbsent(target, request: first); error = result == .unavailable ? "미전송을 확인하지 못해 원고를 보관했습니다." : nil }
        catch { self.error = "미전송을 확인하지 못해 원고를 보관했습니다. 새 댓글은 보내지 않았습니다." }
        pending = (try? adapter.pendingRequests(target)) ?? pending
        busy = false
        if pending.isEmpty { await load(reset: true) }
    }
    @MainActor private func resolvePending() async {
        guard !busy, let adapter, let first = pending.first else { return }
        busy = true
        do { _ = try await adapter.retryConfirmedAbsent(target, request: first); error = nil }
        catch { self.error = "기존 댓글 결과가 아직 확정되지 않았어요. 새 댓글은 보내지 않았습니다." }
        pending = (try? adapter.pendingRequests(target)) ?? pending
        busy = false
        if pending.isEmpty { await load(reset: true) }
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor final class AccountActivityCommentUIFixture: AccountActivityInteractionTransport {
    private static var fixtures: [UUID: AccountActivityCommentUIFixture] = [:]
    static func shared(card: UUID) -> AccountActivityCommentUIFixture {
        if let existing = fixtures[card] { return existing }
        let fixture = AccountActivityCommentUIFixture(card: card)
        fixtures[card] = fixture; return fixture
    }
    let card: UUID
    var rows: [[String: Any]] = []
    init(card: UUID) { self.card = card }
    func call(_ name: String, params: AccountActivityInteractionParameters) async throws -> Data {
        guard ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_NATIVE_COMMENT_QA"] == "1", params.p_card_id == card else { throw AccountActivityInteractionError.disabled }
        var value: Any
        switch name {
        case "soom_activity_interaction_status_candidate_v1":
            value = ["version":1,"card_id":card.uuidString,"backing":"native","state":"native_ready","release_ready":false]
        case "soom_activity_native_comments_candidate_v1":
            value = ["version":1,"backing":"native","rows":rows,"release_ready":false]
        case "soom_activity_native_add_comment_candidate_v1":
            guard let id = params.p_comment_id, let body = params.p_body else { throw AccountActivityInteractionError.invalidRequest }
            if !rows.contains(where: { $0["id"] as? String == id.uuidString }) {
                rows.append(["id":id.uuidString,"card_id":card.uuidString,"author_id":ReviewDemoMode.userID.uuidString,
                    "parent_id":params.p_parent_comment_id.map(\.uuidString) as Any? ?? NSNull(),
                    "reply_to_id":params.p_parent_comment_id.map(\.uuidString) as Any? ?? NSNull(),
                    "created_at":ISO8601DateFormatter().string(from: Date()),"is_deleted":false,"body":body,
                    "mentions":(params.p_mentions ?? []).map { ["user_id":$0.user_id.uuidString,"handle":$0.handle] }])
            }
            return try JSONEncoder().encode(id)
        case "soom_activity_native_delete_comment_candidate_v1":
            rows.removeAll { $0["id"] as? String == params.p_comment_id?.uuidString }; value = true
        default: throw AccountActivityInteractionError.invalidRequest
        }
        return try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    }
}
#endif
