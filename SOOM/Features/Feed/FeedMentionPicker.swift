import SwiftUI
import Supabase

/// Reuses the existing authenticated, block-filtered profile search. This local
/// preview stays gated until the atomic mention write/read RPC is deployed.
enum FeedReplyReleaseGate {
    // Enable only after the v3 server contract and grants are verified in production.
    static let productionReady = false
}

struct FeedMentionPicker: View {
    @Binding var text: String
    @Binding var draft: FeedMentionDraft
    let limit: Int
    /// When supplied, only the card-authorized server search may produce candidates.
    var scopedSearch: ((String) async throws -> [FeedProfileDTO])? = nil
    @State private var scopedRows: [FeedProfileDTO] = []
    @State private var scopedBusy = false
    @State private var scopedError: String?
    @State private var query = ""
    @StateObject private var search = ProfileSearchModel()
    @ObservedObject private var safety = CommunitySafetyStore.shared

    static var isPreviewEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SOOM_MENTION_PREVIEW"] == "1"
        #else
        return false
        #endif
    }

    private var displayedRows: [FeedProfileDTO] {
        if scopedSearch != nil { return Array(scopedRows.prefix(5)) }
        return Array(search.rows.prefix(5)).map(\.profile)
    }
    private var isSearching: Bool { scopedSearch != nil ? scopedBusy : search.busy }
    private var searchError: String? { scopedSearch != nil ? scopedError : search.error }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("@ 사용자 이름으로 검색", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("feed.mention.search")
            if isSearching { ProgressView("사용자 검색 중") }
            if let error = searchError { Text(error).font(.caption).foregroundStyle(.red) }
            ForEach(displayedRows) { person in
                if let handle = person.handle, !handle.isEmpty, person.id != safety.viewerID {
                    Button {
                        var candidate = draft
                        candidate.select(userID: person.id, handle: handle)
                        guard let selection = candidate.selections.last, selection.userID == person.id else { return }
                        let addition = (text.isEmpty || text.last?.isWhitespace == true ? "" : " ") + "@\(selection.handle) "
                        guard (text + addition).count <= limit else { return }
                        text += addition; draft = candidate; query = ""; search.clear(); scopedRows = []
                    } label: {
                        HStack {
                            Text(person.displayName)
                            Text("@\(handle.hasPrefix("@") ? String(handle.dropFirst()) : handle)").foregroundStyle(.secondary)
                        }.frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
            }
            Text((scopedSearch != nil || FeedReplyReleaseGate.productionReady) ? "검색 결과에서 선택한 사용자만 멘션으로 연결됩니다." : "멘션 미리보기: 서버 연결 전에는 멘션이 포함된 글을 전송하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: query) {
            let term = query.hasPrefix("@") ? String(query.dropFirst()) : query
            if let scopedSearch {
                scopedRows = []; scopedError = nil; scopedBusy = false
                guard term.count >= 2, term.count <= 100, safety.canUseSocial else { return }
                let generation = safety.accountGeneration, revision = safety.revision
                scopedBusy = true
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    let rows = try await scopedSearch(term)
                    guard !Task.isCancelled, generation == safety.accountGeneration, revision == safety.revision else { return }
                    scopedRows = rows.filter { !safety.isBlocked($0.id) }; scopedBusy = false
                } catch {
                    guard !Task.isCancelled, generation == safety.accountGeneration, revision == safety.revision else { return }
                    scopedError = "멘션할 사용자를 확인하지 못했어요."; scopedBusy = false
                }
                return
            }
            guard search.prepareSearch(query: term) else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard !Task.isCancelled else { return }
            await search.load(query: term)
        }
        .onChange(of: safety.accountGeneration) { _, _ in query = ""; search.clear(); scopedRows = []; scopedBusy = false; scopedError = nil; draft.reset() }
        .onChange(of: safety.revision) { _, _ in query = ""; search.clear(); scopedRows = []; scopedBusy = false; scopedError = nil; draft.reset() }
    }
}

/// Candidate renderer. Inputs must come from the access-filtered mentions RPC,
/// not parsing usernames in stored text or client cache.
struct FeedMentionBody: View {
    @Environment(\.feedCommentOpenProfile) private var openCommentProfile
    let bodyText: String
    let references: [FeedMentionReference]
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.soomOpenProfile) private var openRootProfile
    var body: some View {
        Text(FeedMentionText.attributed(bodyText,
            references: references.filter { !safety.isBlocked($0.userID) }))
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "soom-mention", url.host == "profile",
                      let id = UUID(uuidString: String(url.path.dropFirst())),
                      references.contains(where: { $0.userID == id }),
                      safety.canUseSocial, !safety.isBlocked(id) else { return .discarded }
                if let openCommentProfile { openCommentProfile(id) }
                else { openRootProfile?(id, nil) }
                return .handled
            })

    }
}

/// Disabled on production builds until the candidate RPC is reviewed/deployed.
struct FeedMentionRemoteBody: View {
    let bodyText: String
    let sourceKind: String
    let sourceID: UUID
    @State private var references: [FeedMentionReference] = []
    @ObservedObject private var safety = CommunitySafetyStore.shared
    var body: some View {
        FeedMentionBody(bodyText: bodyText, references: references)
            .task(id: bodyText) { await refresh() }
            .onChange(of: safety.accountGeneration) { _, _ in references = [] }
            .onChange(of: safety.revision) { _, _ in references = [] }
    }
    @MainActor private func refresh() async {
        references = []
        guard FeedReplyReleaseGate.productionReady || FeedMentionPicker.isPreviewEnabled, safety.canUseSocial,
              let viewer = safety.viewerID,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
              client.auth.currentSession?.user.id == viewer else { return }
        let generation = safety.accountGeneration, revision = safety.revision
        struct Params: Encodable { let p_kind: String; let p_source: UUID }
        do {
            let rows: [FeedMentionReference] = try await client.rpc("soom_read_mentions_candidate_v1",
                params: Params(p_kind: sourceKind, p_source: sourceID)).execute().value
            guard !Task.isCancelled, safety.viewerID == viewer,
                  generation == safety.accountGeneration, revision == safety.revision,
                  client.auth.currentSession?.user.id == viewer else { return }
            references = rows.filter { !safety.isBlocked($0.userID) }
        } catch {
            // An unavailable/denied RPC must never turn a handle into an identity.
            references = []
        }
    }
}

/// Local candidate transport contract; no automatic activation/fallback inserts.
/// Caller retains requestID across an uncertain outcome and reads before retrying.
@MainActor
struct FeedReplyCandidateClient {
    let client: SupabaseClient
    let expectedViewer: UUID
    let generation: Int
    var safetyRevision = CommunitySafetyStore.shared.revision
    private func validate() throws {
        guard FeedReplyReleaseGate.productionReady,
              CommunitySafetyStore.shared.canUseSocial,
              CommunitySafetyStore.shared.viewerID == expectedViewer,
              CommunitySafetyStore.shared.accountGeneration == generation,
              CommunitySafetyStore.shared.revision == safetyRevision,
              client.auth.currentSession?.user.id == expectedViewer else { throw CommunitySafetyError.accountChanged }
    }
    func create(requestID: UUID, postID: UUID, body: String, parentID: UUID?, mentions: [FeedMentionDraft.Selection]) async throws -> UUID {
        try validate()
        struct Params: Encodable {
            let p_comment_id: UUID; let p_post_id: UUID; let p_body: String
            let p_mentions: [FeedMentionDraft.Selection]; let p_parent_comment_id: UUID?
        }
        let result: UUID = try await client.rpc("soom_add_reply_mentions_candidate_v1", params:
            Params(p_comment_id: requestID, p_post_id: postID, p_body: body, p_mentions: mentions, p_parent_comment_id: parentID)).execute().value
        try validate()
        guard result == requestID else { throw FeedPostManagementError.contentUnavailable }
        return result
    }
    struct Cursor: Codable, Equatable {
        let created_at: Date
        let id: UUID
    }
    struct Page: Decodable {
        let items: [FeedReplyThreadDTO]
        let parents: [FeedReplyThreadDTO]
        let next_cursor: Cursor?
    }
    struct Receipt: Decodable {
        let id: UUID; let post_id: UUID; let user_id: UUID; let body: String?
        let parent_comment_id: UUID?; let reply_to_comment_id: UUID?
        let is_deleted: Bool; let mentions: [FeedMentionDraft.Selection]
        func matches(_ request: FeedCommentPendingRequest) -> Bool {
            id == request.id && post_id == request.postID && user_id == request.viewerID && body == request.body &&
            (reply_to_comment_id ?? parent_comment_id) == request.parentID &&
            mentions.sorted { $0.userID.uuidString < $1.userID.uuidString } == request.mentions.sorted { $0.userID.uuidString < $1.userID.uuidString }
        }
    }
    struct RequestStatus: Decodable {
        let state: FeedCommentRecoveryState
        let receipt: Receipt?
    }
    func requestStatus(postID: UUID, requestID: UUID) async throws -> RequestStatus {
        try validate()
        struct Params: Encodable { let p_post_id: UUID; let p_comment_id: UUID }
        let result: RequestStatus = try await client.rpc("soom_reply_request_status_candidate_v1", params: Params(p_post_id: postID, p_comment_id: requestID)).execute().value
        try validate()
        return result
    }
    func read(postID: UUID) async throws -> [FeedComment] {
        try validate()
        struct Params: Encodable {
            let p_post_id: UUID; let p_limit: Int
            let p_after_created_at: Date?; let p_after_id: UUID?
        }
        var cursor: Cursor?
        var rowsByID: [UUID: FeedReplyThreadDTO] = [:]
        var pages = 0
        repeat {
            try Task.checkCancellation()
            let page: Page = try await client.rpc("soom_read_reply_page_candidate_v1", params: Params(p_post_id: postID, p_limit: 100, p_after_created_at: cursor?.created_at, p_after_id: cursor?.id)).execute().value
            try validate()
            for row in page.parents + page.items { rowsByID[row.id] = row }
            if let next = page.next_cursor, next == cursor { throw FeedPostManagementError.contentUnavailable }
            cursor = page.next_cursor
            pages += 1
            if pages >= 100, cursor != nil { throw FeedPostManagementError.contentUnavailable }
        } while cursor != nil
        let rows = rowsByID.values.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        let ids = Array(Set(rows.compactMap { $0.isDeleted ? nil : $0.userID }))
        let profiles = try await SupabaseFeedRemoteClient(client: client, expectedPostingUserID: expectedViewer).fetchProfiles(ids: ids)
        try validate()
        let byID = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return rows.compactMap { row in
            guard var comment = row.comment(viewerID: expectedViewer) else { return nil }
            if !comment.isDeleted {
                guard !CommunitySafetyStore.shared.isBlocked(comment.authorId) else { return nil }
                comment.profile = byID[comment.authorId]
            }
            return comment
        }
    }
    func delete(commentID: UUID) async throws {
        try validate()
        struct Params: Encodable { let p_comment_id: UUID }
        let removed: Bool = try await client.rpc("soom_delete_reply_candidate_v1", params: Params(p_comment_id: commentID)).execute().value
        try validate()
        guard removed else { throw FeedPostManagementError.contentUnavailable }
    }
}
