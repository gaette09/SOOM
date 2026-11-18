import SwiftUI
import Supabase

/// One conversation surface: workout context, every comment, and an inline
/// composer that stays above the keyboard. No map or second compose sheet.
struct FeedCommentTombstone: Identifiable {
    let id: UUID
    let createdAt: Date
    let parentID: UUID?
}

struct FeedCommentListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.feedCommentProfileRouter) private var profileRouter
    @State private var requestedProfile: UUID?
    @Environment(\.soomCurrentProfileID) private var currentProfileID
    let comments: [FeedComment]
    var tombstones: [FeedCommentTombstone] = []
    var item: FeedItem? = nil
    var nativeReferences: [UUID: [FeedMentionReference]]? = nil
    var nativeActivityPreview = false
    var scopedMentionSearch: ((String) async throws -> [FeedProfileDTO])? = nil
    var isLoading = false
    var onSubmit: ((String) async throws -> Void)? = nil
    var onDelete: ((FeedComment) async throws -> Void)? = nil
    var onReply: ((String, FeedComment) async throws -> Void)? = nil
    var onAtomicSubmit: ((String, FeedComment?, [FeedMentionDraft.Selection]) async throws -> Void)? = nil
    @ObservedObject private var safetyStore = CommunitySafetyStore.shared
    @StateObject private var composer = FeedCommentComposeViewModel()
    @FocusState private var isFocused: Bool
    @State private var mentionDraft = FeedMentionDraft()
    @State private var replyingTo: FeedComment?
    @State private var pendingDelete: FeedComment?
    @State private var isConfirmingDelete = false
    @State private var deletingID: UUID?
    @State private var deletionError: String?
    @State private var deletedIDs: Set<UUID> = []

    private var hasNativePreviewAccess: Bool {
        nativeActivityPreview && nativeReferences != nil && item == nil && safetyStore.canUseActivityPreview
    }
    private var hasCommentAccess: Bool { safetyStore.canUseSocial || hasNativePreviewAccess }
    private var visibleComments: [FeedComment] { comments.filter { !safetyStore.isBlocked($0.authorId) && !deletedIDs.contains($0.id) } }

    private enum ConversationRow: Identifiable {
        case comment(FeedComment), tombstone(FeedCommentTombstone)
        var id: UUID { switch self { case .comment(let c): c.id; case .tombstone(let t): t.id } }
        var parentID: UUID? { switch self { case .comment(let c): c.parentCommentID; case .tombstone(let t): t.parentID } }
        var date: Date { switch self { case .comment(let c): c.createdAt; case .tombstone(let t): t.createdAt } }
    }
    private var visibleRows: [ConversationRow] {
        guard !tombstones.isEmpty else { return visibleComments.map(ConversationRow.comment) }
        return (visibleComments.map(ConversationRow.comment) + tombstones.map(ConversationRow.tombstone)).sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
    }
    @ViewBuilder private func conversationRow(_ row: ConversationRow) -> some View {
        switch row {
        case .comment(let comment): commentRow(comment)
        case .tombstone:
            Text("삭제된 댓글입니다").font(.subheadline).foregroundStyle(SOOMColor.tertiaryInk)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        // Keep the conversation foregrounded, matching the supplied comment-sheet reference.
                        if isLoading && visibleRows.isEmpty { SOOMSkeleton(layout: .list, label: "댓글 불러오는 중") }
                        if visibleRows.isEmpty && !isLoading {
                            VStack(spacing: 8) {
                                Text("아직 댓글이 없어요").font(.subheadline.weight(.bold))
                                Text("첫 댓글을 남겨보세요.").font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                            }.frame(maxWidth: .infinity).padding(.vertical, 30)
                        }
                        ForEach(visibleRows.filter { $0.parentID == nil }) { comment in
                            conversationRow(comment).id(comment.id)
                            ForEach(visibleRows.filter { $0.parentID == comment.id }) { reply in
                                conversationRow(reply).padding(.leading, 44).id(reply.id)
                            }
                        }
                        // A missing/deleted parent must not hide surviving replies.
                        ForEach(visibleRows.filter { child in
                            child.parentID != nil && !visibleRows.contains(where: { $0.id == child.parentID })
                        }) { reply in conversationRow(reply).id(reply.id) }
                        Color.clear.frame(height: 1).id("conversation-bottom")
                    }.padding(.horizontal, SOOMLayout.screenPadding).padding(.vertical, 20)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { isFocused = false })
                .scrollDismissesKeyboard(.immediately)
                    .onChange(of: visibleComments.count) { old, new in
                        if new > old, isFocused { withAnimation { proxy.scrollTo("conversation-bottom", anchor: .bottom) } }
                    }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if onSubmit != nil { inlineComposer }
        }
        .background(SOOMColor.background)
        .environment(\.feedCommentOpenProfile, { userID in openProfile(userID, profile: nil) })
        .navigationTitle("댓글")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() }.disabled(composer.isSubmitting) }
        }
        .interactiveDismissDisabled(composer.isSubmitting || deletingID != nil)
        .confirmationDialog("이 댓글을 삭제할까요?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            if let comment = pendingDelete {
                Button("댓글 삭제", role: .destructive) { Task { await deleteConfirmed(comment) } }
                    .accessibilityIdentifier("feed.comment.delete.confirm")
            }
            Button("취소") { pendingDelete = nil; isConfirmingDelete = false }
        } message: { Text("삭제한 댓글은 되돌릴 수 없어요.") }
        .alert("댓글을 삭제하지 못했어요", isPresented: Binding(
            get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
            Button("확인", role: .cancel) { deletionError = nil }
        } message: { Text(deletionError ?? "") }
        .onChange(of: safetyStore.accountGeneration) { _, _ in requestedProfile = nil; dismiss() }
        .onChange(of: safetyStore.revision) { _, _ in requestedProfile = nil; profileRouter?.cancel() }
        .onDisappear {
            if let requestedProfile { profileRouter?.commentsDidDismiss(requestID: requestedProfile, context: profileContext) }
        }
    }
    private var profileContext: AccountActivityReadContext? {
        guard safetyStore.canUseSocial, let viewer = safetyStore.viewerID else { return nil }
        return .init(viewerID: viewer, generation: safetyStore.accountGeneration, safetyRevision: safetyStore.revision)
    }
    private func openProfile(_ userID: UUID, profile: FeedProfileDTO?) {
        if userID == currentProfileID { isFocused = false; dismiss(); return }
        guard !composer.isSubmitting, deletingID == nil, !safetyStore.isBlocked(userID),
              let profileRouter, let request = profileRouter.request(userID: userID, profile: profile, context: profileContext) else { return }
        requestedProfile = request; isFocused = false; dismiss()
    }

    private func workoutContext(_ item: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.recordTitle).font(.title3.weight(.bold)).foregroundStyle(SOOMColor.ink)
            HStack(spacing: 8) {
                Button { openProfile(item.authorId, profile: FeedProfileDTO(
                    id: item.authorId, displayName: item.authorName, handle: item.authorHandle, avatarPath: item.avatarPath)) } label: {
                    HStack(spacing: 7) {
                        SOOMAvatarView(userID: item.authorId, avatarPath: item.avatarPath, size: 26)
                        Text(item.authorHandle.map { $0.hasPrefix("@") ? $0 : "@\($0)" } ?? item.authorName).lineLimit(1)
                    }
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
                Text((item.activityDate ?? item.createdAt).formatted(date: .abbreviated, time: .omitted))
            }.font(.caption).foregroundStyle(SOOMColor.secondaryInk)
            HStack(spacing: 7) {
                SOOMSportIconView(name: item.recordSportIcon, size: 18)
                Text(item.recordSport)
                Text("·")
                Text(item.recordMetrics.first(where: { $0.label == "거리" })?.value ?? "—")
            }.font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            Divider().padding(.top, 8)
        }
    }

    private var inlineComposer: some View {
        VStack(spacing: 6) {
            Divider()
            if let error = composer.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("feed.comment.error")
            }
            if scopedMentionSearch != nil || FeedMentionPicker.isPreviewEnabled || FeedReplyReleaseGate.productionReady || (nativeReferences != nil && AccountActivityInteractionReleaseGate.productionReady) {
                FeedMentionPicker(text: $composer.text, draft: $mentionDraft, limit: 500, scopedSearch: scopedMentionSearch)
            }
            if let target = replyingTo {
                HStack {
                    Text("\(target.profile?.displayName ?? "사용자")님에게 답글 작성 중").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { replyingTo = nil } label: { Image(systemName: "xmark").font(.caption).frame(width: 44, height: 44) }
                        .accessibilityLabel("답글 취소")
                }
            }
            HStack(spacing: 0) {
                ForEach(["❤️", "🙌", "🔥", "👏", "😢", "😍", "😮", "😂"], id: \.self) { emoji in
                    Button {
                        guard composer.text.count + emoji.count <= 500 else { return }
                        composer.text += emoji; isFocused = true
                    } label: { Text(emoji).font(.system(size: 24)).frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.plain).disabled(composer.isSubmitting)
                    .accessibilityLabel("\(emoji) 입력")
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                if let viewer = safetyStore.viewerID {
                    SOOMAvatarView(userID: viewer, avatarPath: nil, size: 36)
                        .accessibilityHidden(true).padding(.bottom, 4)
                }
                TextField("대화에 참여하세요…", text: $composer.text, axis: .vertical)
                    .font(.body).lineLimit(1...4).focused($isFocused).disabled(composer.isSubmitting)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 14)
                    .background(Capsule().stroke(SOOMColor.surfaceMuted, lineWidth: 1))
                    .accessibilityIdentifier("feed.comment.input")
                Button {
                    Task {
                        guard hasCommentAccess, let onSubmit else { return }
                        let target = replyingTo
                        let submit: (String) async throws -> Void = { text in
                            if let onAtomicSubmit { try await onAtomicSubmit(text, target, mentionDraft.retainedSelections(in: text)) }
                            else if let target, let onReply { try await onReply(text, target) }
                            else { try await onSubmit(text) }
                        }
                        if await composer.submit(using: submit) { composer.text = ""; replyingTo = nil; mentionDraft.reset() }
                    }
                } label: {
                    if composer.isSubmitting { ProgressView().frame(width: 44, height: 44) }
                    else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 28)).frame(width: 44, height: 44) }
                }.accessibilityLabel("댓글 보내기").disabled(!hasCommentAccess || !composer.canSubmit || isLoading || (onAtomicSubmit == nil && !mentionDraft.retainedSelections(in: composer.text).isEmpty)).foregroundStyle(composer.canSubmit ? SOOMColor.accent : SOOMColor.tertiaryInk)
            }
            if composer.trimmedText.count > 450 {
                Text("\(composer.trimmedText.count)/500").font(.caption2)
                    .foregroundStyle(composer.trimmedText.count > 500 ? .red : SOOMColor.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }.padding(.horizontal, SOOMLayout.screenPadding).padding(.bottom, 8).background(SOOMColor.background)
    }

    private func canDelete(_ comment: FeedComment) -> Bool {
        !comment.isDeleted && onDelete != nil && FeedCommentDeletePolicy.allows(viewerID: safetyStore.viewerID,
            commentAuthorID: comment.authorId, postAuthorID: item?.authorId,
            canUseSocial: hasCommentAccess)
    }

    @MainActor private func deleteConfirmed(_ comment: FeedComment) async {
        pendingDelete = nil
        isConfirmingDelete = false
        guard deletingID == nil, canDelete(comment), let onDelete else { return }
        let generation = safetyStore.accountGeneration
        deletingID = comment.id
        defer { deletingID = nil }
        do {
            try await onDelete(comment)
            guard generation == safetyStore.accountGeneration else { return }
            deletedIDs.insert(comment.id)
        } catch {
            guard generation == safetyStore.accountGeneration else { return }
            deletionError = "삭제 결과를 확인하지 못했어요. 목록을 다시 확인한 뒤 시도해 주세요."
        }
    }

    @ViewBuilder private func commentRow(_ comment: FeedComment) -> some View {
        if comment.isDeleted {
            Text("삭제된 댓글입니다").font(.subheadline).foregroundStyle(SOOMColor.tertiaryInk)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
        } else {
        HStack(alignment: .top, spacing: 12) {
            Button { openProfile(comment.authorId, profile: comment.profile) } label: {
                SOOMAvatarView(userID: comment.authorId, avatarPath: comment.profile?.avatarPath, size: 40)
            }.buttonStyle(.plain).disabled(!safetyStore.canUseSocial || profileRouter == nil).accessibilityLabel("댓글 작성자 프로필")
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button { openProfile(comment.authorId, profile: comment.profile) } label: {
                        Text(comment.profile?.handle ?? comment.profile?.displayName ?? (comment.isViewerAuthor ? "나" : "SOOM 사용자"))
                            .font(.subheadline.weight(.bold)).foregroundStyle(SOOMColor.ink)
                            .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                    }.buttonStyle(.plain).disabled(!safetyStore.canUseSocial)
                    Text(SOOMKoreanRelativeTime.text(comment.createdAt)).font(.caption2).foregroundStyle(SOOMColor.tertiaryInk).lineLimit(1)
                    Spacer(minLength: 0)
                    if canDelete(comment) {
                        Button { isFocused = false; pendingDelete = comment; isConfirmingDelete = true } label: {
                            Group {
                                if deletingID == comment.id { ProgressView().controlSize(.small) }
                                else { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                            }
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .foregroundStyle(SOOMColor.tertiaryInk).buttonStyle(.plain)
                        .disabled(deletingID != nil || composer.isSubmitting)
                        .accessibilityLabel("댓글 삭제")
                        .accessibilityHint("삭제 확인 창을 엽니다")
                        .accessibilityIdentifier("feed.comment.delete.\(comment.id.uuidString)")
                    }
                    if nativeReferences == nil && !comment.isViewerAuthor && comment.authorId != safetyStore.viewerID {
                        CommunitySafetyMenu(target: CommunityReportTarget(kind: .comment, id: comment.id),
                            authorID: comment.authorId, authorName: comment.profile?.displayName ?? "SOOM 사용자")
                    }
                }
                Group {
                    if let nativeReferences {
                        FeedMentionBody(bodyText: comment.body, references: nativeReferences[comment.id] ?? []).disabled(!safetyStore.canUseSocial)
                    } else if FeedMentionPicker.isPreviewEnabled || FeedReplyReleaseGate.productionReady {
                        // Only persisted server-authorized identities become links,
                        // including third-party selections in replies. Never infer
                        // mention identity from the current root author's handle.
                        FeedMentionRemoteBody(bodyText: comment.body, sourceKind: "comment", sourceID: comment.id)
                    } else {
                        Text(comment.body)
                    }
                }.font(.body).foregroundStyle(SOOMColor.ink).fixedSize(horizontal: false, vertical: true)
                if onReply != nil || onAtomicSubmit != nil {
                    Button("답글 달기") {
                        replyingTo = comment
                        if composer.text.isEmpty, let handle = comment.profile?.handle, !handle.isEmpty {
                            composer.text = "@\(handle.hasPrefix("@") ? String(handle.dropFirst()) : handle) "
                        }
                        isFocused = true
                    }.font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                        .frame(minHeight: 44).buttonStyle(.plain).disabled(composer.isSubmitting)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .contain)
        }
    }
}

struct FeedCommentsSheet: View {
    let onSubmit: ((String) async throws -> Void)?
    @StateObject private var management: FeedPostManagement
    @State private var atomicComments: [FeedComment]?
    @State private var atomicReadError: String?
    @State private var atomicWriteError: String?
    @State private var pendingRequest: FeedCommentPendingRequest?
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.dismiss) private var dismiss

    init(item: FeedItem, onSubmit: ((String) async throws -> Void)? = nil) {
        self.onSubmit = onSubmit
        _management = StateObject(wrappedValue: FeedPostManagement(item: item, loadAllComments: true))
    }
    var body: some View {
        SocialAccessBoundary {
        NavigationStack {
            Group {
                if management.hasLoaded && !management.isAvailable && !management.isWorking {
                    ContentUnavailableView("댓글을 표시할 수 없어요", soomIcon: "bubble.left",
                        description: Text(management.errorMessage ?? "게시물의 공개 범위를 확인해 주세요."))
                        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() } } }
                } else {
                    VStack(spacing: 0) {
                    if let error = atomicReadError ?? atomicWriteError {
                        VStack {
                            Text(error).font(.caption).foregroundStyle(.red)
                            if atomicReadError != nil { Button("댓글 다시 불러오기") { Task { await refreshAtomicComments() } } }
                        }.padding()
                    }
                    FeedCommentListView(comments: FeedReplyReleaseGate.productionReady && !ReviewDemoMode.isActive ? (atomicComments ?? []) : management.item.comments, item: management.item,
                        isLoading: !management.hasLoaded || management.isWorking || (FeedReplyReleaseGate.productionReady && !ReviewDemoMode.isActive && (atomicComments == nil || atomicReadError != nil)),
                        onSubmit: { body in
                            guard management.isAvailable else { throw FeedPostManagementError.contentUnavailable }
                            if let onSubmit { try await onSubmit(body) }
                            else { try await submitComment(body) }
                            await management.refresh()
                        }, onDelete: { comment in
                            try await deleteComment(comment)
                        }, onReply: ReviewDemoMode.isActive ? { text, target in
                            try await ReviewDemoCommunityStore.shared.addReply(postId: management.item.id, body: text, parent: target)
                            await management.refresh()
                            NotificationCenter.default.post(name: FeedPostManagement.didChange, object: ReviewDemoMode.userID)
                        } : nil, onAtomicSubmit: FeedReplyReleaseGate.productionReady && !ReviewDemoMode.isActive ? { body, parent, mentions in
                            try await submitAtomicComment(body, parent: parent, mentions: mentions)
                        } : nil)
                    }
                }
            }
            .task { await management.refresh(); await refreshAtomicComments() }
            .onChange(of: safety.accountGeneration) { _, _ in dismiss() }
            .onChange(of: safety.revision) { _, _ in Task { atomicComments = nil; await management.refresh(); await refreshAtomicComments() } }
        }

        }
        .presentationDetents([.fraction(0.72), .large])
        .presentationDragIndicator(.visible)
    }

    @MainActor private func deleteComment(_ comment: FeedComment) async throws {
        let postID = management.item.id
        guard FeedCommentDeletePolicy.allows(viewerID: safety.viewerID, commentAuthorID: comment.authorId,
            postAuthorID: management.item.authorId, canUseSocial: safety.canUseSocial), !comment.isDeleted else { throw FeedPostManagementError.contentUnavailable }
        if ReviewDemoMode.isActive {
            try await ReviewDemoCommunityStore.shared.deleteComment(postId: postID, commentID: comment.id)
            await management.refresh()
            NotificationCenter.default.post(name: FeedPostManagement.didChange, object: ReviewDemoMode.userID)
            return
        }
        guard let viewer = safety.viewerID, safety.canUseSocial,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
              client.auth.currentSession?.user.id == viewer else { throw CommunitySafetyError.signInRequired }
        let generation = safety.accountGeneration
        let remote = SupabaseFeedRemoteClient(client: client, expectedPostingUserID: viewer)
        guard try await remote.fetchFeedPost(id: postID) != nil,
              comment.authorId == viewer,
              generation == safety.accountGeneration, client.auth.currentSession?.user.id == viewer else {
            throw FeedPostManagementError.contentUnavailable
        }
        struct OwnedComment: Decodable { let id: UUID; let user_id: UUID }
        let owned: [OwnedComment] = try await client.from("feed_comments").select("id,user_id")
            .eq("id", value: comment.id).eq("post_id", value: postID).eq("user_id", value: viewer).limit(1).execute().value
        guard owned.first?.id == comment.id, owned.first?.user_id == viewer,
              generation == safety.accountGeneration, safety.viewerID == viewer,
              client.auth.currentSession?.user.id == viewer else { throw FeedPostManagementError.contentUnavailable }
        if FeedReplyReleaseGate.productionReady {
            let api = FeedReplyCandidateClient(client: client, expectedViewer: viewer, generation: generation)
            do {
                try await api.delete(commentID: comment.id)
                atomicComments = try await api.read(postID: postID)
                await management.refresh()
                NotificationCenter.default.post(name: FeedPostManagement.didChange, object: nil, userInfo: ["postID": postID])
            } catch { await refreshAtomicComments(); throw error }
            return
        }
        struct Deleted: Decodable { let id: UUID }
        do {
            let rows: [Deleted] = try await client.from("feed_comments").delete()
                .eq("id", value: comment.id).eq("post_id", value: postID)
                .eq("user_id", value: viewer).select("id").execute().value
            guard generation == safety.accountGeneration, client.auth.currentSession?.user.id == viewer else {
                throw CommunitySafetyError.accountChanged
            }
            guard rows.contains(where: { $0.id == comment.id }) else { throw FeedPostManagementError.contentUnavailable }
            NotificationCenter.default.post(name: FeedPostManagement.didChange, object: nil, userInfo: ["postID": postID])
            await management.refresh()
        } catch {
            // No blind retry or optimistic removal after an uncertain response.
            await management.refresh()
            throw error
        }
    }

    @MainActor private func refreshAtomicComments() async {
        guard FeedReplyReleaseGate.productionReady, !ReviewDemoMode.isActive,
              let viewer = safety.viewerID, safety.canUseSocial,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { return }
        let api = FeedReplyCandidateClient(client: client, expectedViewer: viewer, generation: safety.accountGeneration)
        do { atomicComments = try await api.read(postID: management.item.id); atomicReadError = nil }
        catch {
            atomicComments = nil // never fall back to the old flat/physical-delete contract
            atomicReadError = "댓글을 불러오지 못했어요. 다시 불러온 뒤 작성해 주세요."
        }
    }

    @MainActor private func submitAtomicComment(_ text: String, parent: FeedComment?, mentions: [FeedMentionDraft.Selection]) async throws {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FeedReplyReleaseGate.productionReady, !body.isEmpty, body.count <= 500,
              let viewer = safety.viewerID, safety.canUseSocial,
              !management.item.isLocalDraft,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else {
            throw FeedPostManagementError.contentUnavailable
        }
        let postID = management.item.id
        let api = FeedReplyCandidateClient(client: client, expectedViewer: viewer, generation: safety.accountGeneration)
        if pendingRequest == nil { pendingRequest = try FeedCommentPendingStore.read(viewer: viewer, post: postID) }
        let isRetry = pendingRequest != nil
        atomicWriteError = nil
        // Locked UUID status is independent of list pagination. Only explicit
        // authorized absence permits the same frozen UUID to be retried.
        if let pending = pendingRequest {
            let status = try await api.requestStatus(postID: postID, requestID: pending.id)
            if status.state == .found, let receipt = status.receipt {
                if receipt.is_deleted || receipt.matches(pending) {
                    pendingRequest = nil
                    FeedCommentPendingStore.clear(viewer: viewer, post: postID)
                    await refreshAtomicComments()
                    guard !receipt.is_deleted, pending.matches(postID: postID, viewerID: viewer, body: body, parentID: parent?.id, mentions: mentions) else {
                        atomicWriteError = "이전 요청은 처리됐어요. 현재 내용을 확인한 뒤 다시 보내 주세요."
                        throw FeedPostManagementError.contentUnavailable
                    }
                    return
                }
                atomicWriteError = "이전 요청과 서버 내용이 달라 전송을 멈췄어요. 확인이 필요합니다."
                throw FeedPostManagementError.contentUnavailable
            }
            guard status.state.permitsRetry(pending, postID: postID, viewerID: viewer,
                body: body, parentID: parent?.id, mentions: mentions) else {
                atomicWriteError = "이전 요청을 아직 확인할 수 없거나 내용이 변경됐어요. 새 댓글은 보내지 않았습니다."
                throw FeedPostManagementError.contentUnavailable
            }
            // Locked, authorized absence: retry this same persisted UUID and
            // frozen payload exactly once for this explicit submit action.
        }
        let request = pendingRequest ?? FeedCommentPendingRequest(postID: postID, viewerID: viewer, body: body, parentID: parent?.id, mentions: mentions)
        pendingRequest = request
        try FeedCommentPendingStore.save(request)
        do {
            _ = try await api.create(requestID: request.id, postID: postID, body: request.body, parentID: request.parentID, mentions: request.mentions)
        } catch {
            // Only a first attempt's explicit SQL rollback is definitive. A
            // later/transport failure cannot prove an earlier request absent.
            if !isRetry, let server = error as? PostgrestError,
               FeedCommentFailurePolicy.isDefinitiveFirstRejection(code: server.code) {
                pendingRequest = nil
                FeedCommentPendingStore.clear(viewer: viewer, post: postID)
                atomicWriteError = "서버가 댓글을 저장하지 않았어요. 멘션이나 답글 대상을 수정한 뒤 다시 보내 주세요."
            } else {
                atomicWriteError = "전송 결과가 불확실해 요청을 보관했어요. 다시 누르면 먼저 결과를 확인합니다."
            }
            throw error
        }
        pendingRequest = nil
        FeedCommentPendingStore.clear(viewer: viewer, post: postID)
        await management.refresh()
        await refreshAtomicComments()
        NotificationCenter.default.post(name: FeedPostManagement.didChange, object: nil, userInfo: ["postID": postID])
    }

    @MainActor private func submitComment(_ text: String) async throws {
        if ReviewDemoMode.isActive {
            try await ReviewDemoCommunityStore.shared.addComment(postId: management.item.id, body: text)
            NotificationCenter.default.post(name: FeedPostManagement.didChange, object: ReviewDemoMode.userID)
            return
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 500,
              let viewer = safety.viewerID,
              !management.item.isLocalDraft, !safety.isBlocked(management.item.authorId),
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
              client.auth.currentSession?.user.id == viewer else { throw CommunitySafetyError.signInRequired }
        let generation = safety.accountGeneration
        let postID = management.item.id
        let authorID = management.item.authorId
        let remote = SupabaseFeedRemoteClient(client: client, expectedPostingUserID: viewer)
        guard let current = try await remote.fetchFeedPost(id: postID), current.post.userId == authorID,
              generation == safety.accountGeneration, client.auth.currentSession?.user.id == viewer else {
            throw FeedPostManagementError.contentUnavailable
        }
        // Capture the writer in the payload; a token switch cannot write as
        // another account because INSERT RLS rejects the original user_id.
        try await client.from("feed_comments").insert(FeedCommentInsertDTO(postId: postID, userId: viewer, body: value)).execute()
        guard generation == safety.accountGeneration, client.auth.currentSession?.user.id == viewer else {
            throw CommunitySafetyError.accountChanged
        }
        NotificationCenter.default.post(name: FeedPostManagement.didChange, object: nil, userInfo: ["postID": postID])
    }
}

/// UI affordance only; server RLS and a fresh source read remain authoritative.
enum FeedCommentDeletePolicy {
    static func allows(viewerID: UUID?, commentAuthorID: UUID, postAuthorID: UUID?, canUseSocial: Bool) -> Bool {
        guard canUseSocial, let viewerID else { return false }
        return viewerID == commentAuthorID
    }
}

/// Consistent Korean relative dates regardless of simulator/OS preferred language.
enum SOOMKoreanRelativeTime {
    static func text(_ date: Date, now: Date = Date()) -> String {
        if abs(date.timeIntervalSince(now)) < 60 { return "방금" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}


/// Two-phase handoff: no navigation is published until the comment sheet has
/// disappeared. Each host owns its route, so Back returns to that exact card.
@MainActor final class FeedCommentProfileRouter: ObservableObject {
    struct Request: Identifiable {
        let id: UUID
        let userID: UUID
        let profile: FeedProfileDTO?
        let context: AccountActivityReadContext
    }
    @Published private(set) var destination: Request?
    private var pending: Request?
    @discardableResult func request(userID: UUID, profile: FeedProfileDTO?, context: AccountActivityReadContext?) -> UUID? {
        Self.trace("request pending=\(pending != nil) destination=\(destination != nil) context=\(context != nil)")
        guard pending == nil, destination == nil, let context else { return nil }
        let value = Request(id: UUID(), userID: userID, profile: profile?.id == userID ? profile : nil, context: context)
        pending = value
        return value.id
    }
    func commentsDidDismiss(requestID: UUID, context: AccountActivityReadContext?) {
        Self.trace("dismiss token=\(pending?.id == requestID) context=\(pending?.context == context)")
        guard let pending, pending.id == requestID else { return }
        self.pending = nil
        guard pending.context == context else { return }
        destination = pending
    }
    func cancelPending() { pending = nil }
    func cancel() { Self.trace("cancel pending=\(pending != nil) destination=\(destination != nil)"); pending = nil; destination = nil }
    static func trace(_ message: String) {
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_PROFILE_NAVIGATION_QA"] == "1" { print("[ProfileNavQA] \(message)") }
        #endif
    }
}
private struct FeedCommentOpenProfileKey: EnvironmentKey {
    static let defaultValue: ((UUID) -> Void)? = nil
}
private struct FeedCommentProfileRouterKey: EnvironmentKey {
    static let defaultValue: FeedCommentProfileRouter? = nil
}
extension EnvironmentValues {
    var feedCommentOpenProfile: ((UUID) -> Void)? {
        get { self[FeedCommentOpenProfileKey.self] }
        set { self[FeedCommentOpenProfileKey.self] = newValue }
    }
    var feedCommentProfileRouter: FeedCommentProfileRouter? {
        get { self[FeedCommentProfileRouterKey.self] }
        set { self[FeedCommentProfileRouterKey.self] = newValue }
    }
}
// Installed once inside each stable tab NavigationStack, never on a card or sheet.
private struct SOOMProfileModalLinkKey: EnvironmentKey { static let defaultValue = false }
private struct SOOMOpenProfileKey: EnvironmentKey {
    static let defaultValue: ((UUID, FeedProfileDTO?) -> Void)? = nil
}
extension EnvironmentValues {
    var soomProfileModalLink: Bool {
        get { self[SOOMProfileModalLinkKey.self] }
        set { self[SOOMProfileModalLinkKey.self] = newValue }
    }
    var soomOpenProfile: ((UUID, FeedProfileDTO?) -> Void)? {
        get { self[SOOMOpenProfileKey.self] }
        set { self[SOOMOpenProfileKey.self] = newValue }
    }
}
enum SOOMProfileNavigationPolicy {
    static func sameAccount(_ route: AccountActivityReadContext, _ current: AccountActivityReadContext?) -> Bool {
        guard let current else { return false }
        return route.viewerID == current.viewerID && route.generation == current.generation
    }
    static func canStart(userID: UUID, currentID: UUID?, active: Bool, blocked: Bool, busy: Bool) -> Bool {
        active && !blocked && !busy && userID != currentID
    }
}
private struct SOOMProfileNavigationActiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var soomProfileNavigationIsActive: Bool {
        get { self[SOOMProfileNavigationActiveKey.self] }
        set { self[SOOMProfileNavigationActiveKey.self] = newValue }
    }
}
/// Same native destination for every link, without another NavigationStack.
struct SOOMProfileDestination: View {
    let userID: UUID
    var profile: FeedProfileDTO? = nil
    var initialSection: ProfileSection = .progress
    var body: some View {
        SocialAccessBoundary {
            FeedPublicProfileView(userID: userID, initialProfile: profile, initialSection: initialSection)
        }.independentFeedReturnScope()
            .environment(\.soomFeedPhotoPresentationID, nil)
            .environment(\.soomProfileModalLink, false)
            .modifier(ProfileFinalDenialDismiss())
    }
}
private struct FeedCommentProfileNavigationHost: ViewModifier {
    @StateObject private var router = FeedCommentProfileRouter()
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.scenePhase) private var scene
    @Environment(\.soomProfileNavigationIsActive) private var isActive
    private var context: AccountActivityReadContext? {
        guard safety.canUseSocial, let viewer = safety.viewerID, auth.session.currentUser?.id == viewer else { return nil }
        return .init(viewerID: viewer, generation: safety.accountGeneration, safetyRevision: safety.revision)
    }
    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: Binding(get: { router.destination != nil }, set: { if !$0 { router.cancel() } })) {
                if let target = router.destination {
                    SOOMProfileDestination(userID: target.userID, profile: target.profile)
                        .opacity(SOOMProfileNavigationPolicy.sameAccount(target.context, context) && scene == .active && isActive ? 1 : 0)
                        .allowsHitTesting(SOOMProfileNavigationPolicy.sameAccount(target.context, context) && scene == .active && isActive)
                        .accessibilityHidden(!SOOMProfileNavigationPolicy.sameAccount(target.context, context) || scene != .active || !isActive)
                }
            }
            .environment(\.feedCommentProfileRouter, router)
            .environment(\.soomOpenProfile, { userID, profile in
                guard isActive, scene == .active, !safety.isBlocked(userID),
                      let token = router.request(userID: userID, profile: profile, context: context) else { return }
                router.commentsDidDismiss(requestID: token, context: context)
            })
            .onChange(of: context) { old, new in
                // Keep already-open same-account native route through revalidation.
                router.cancelPending()
                if let old, let new, !SOOMProfileNavigationPolicy.sameAccount(old, new) { router.cancel() }
            }
            .onChange(of: safety.accountGeneration) { _, _ in router.cancel() }
            .onChange(of: auth.session.currentUser?.id) { _, _ in router.cancel() }
            .onChange(of: isActive) { _, active in if !active { router.cancelPending() } }
            .onChange(of: scene) { _, phase in if phase != .active { router.cancelPending() } }
    }
}
struct SOOMProfileLink<Label: View>: View {
    let userID: UUID
    var profile: FeedProfileDTO? = nil
    @ViewBuilder var label: () -> Label
    @Environment(\.soomProfileModalLink) private var modalLink
    @Environment(\.soomOpenProfile) private var openModalProfile
    var body: some View {
        if modalLink {
            Button { openModalProfile?(userID, profile) } label: { label() }
                .disabled(openModalProfile == nil)
        } else {
            NavigationLink { SOOMProfileDestination(userID: userID, profile: profile) } label: { label() }
        }
    }
}
/// For non-comment modal lists (cheers): retain the same token/context handshake.
private struct SOOMProfileModalHandoff: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.feedCommentProfileRouter) private var router
    @Environment(\.soomCurrentProfileID) private var currentProfileID
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.scenePhase) private var scene
    @State private var requestID: UUID?
    private var context: AccountActivityReadContext? {
        guard safety.canUseSocial, let viewer = safety.viewerID else { return nil }
        return .init(viewerID: viewer, generation: safety.accountGeneration, safetyRevision: safety.revision)
    }
    func body(content: Content) -> some View {
        content.environment(\.soomOpenProfile, { userID, profile in
            if userID == currentProfileID { dismiss(); return }
            guard scene == .active, !safety.isBlocked(userID),
                  let token = router?.request(userID: userID, profile: profile, context: context) else { return }
            requestID = token; dismiss()
        })
        .environment(\.soomProfileModalLink, true)
        .onDisappear {
            if let requestID { router?.commentsDidDismiss(requestID: requestID, context: scene == .active ? context : nil) }
        }
    }
}
extension View {
    func soomProfileModalHandoff() -> some View { modifier(SOOMProfileModalHandoff()) }
    func feedCommentProfileNavigationHost() -> some View { modifier(FeedCommentProfileNavigationHost()) }
}
