import SwiftUI
import Supabase

struct NotificationInboxView: View {
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.scenePhase) private var scene
    @State private var profileSocialSelection: ProfileSocialInboxSelection?
    @Environment(\.dismiss) private var dismiss
    let standaloneNavigation: Bool
    let postDestination: ((FeedNotificationRequest) -> AnyView)?
    @State private var legacySelection: FeedNotificationRequest?
    let incomingNativePush: NativeActivityPushPayload?
    @State private var incomingNativeHandled = false
    @State private var incomingNativeFailed = false
    let incomingFollowService:(any IncomingFollowServing)?
    let profileFetcher: (any FeedRemoteProfileFetching)?
    let onSelectPost: (UUID, NotificationKind) -> Void
    let onMarkedAllRead: () -> Void
    @StateObject private var legacyPreview: LegacyInboxPreviewModel
    @StateObject private var model: NotificationInboxModel
    @State private var actorProfiles: [UUID:FeedProfileDTO] = [:]
    @State private var nativeInboxAdapter: AccountActivityNativeInboxAdapter?
    @State private var nativeConfigurationEpoch = UUID()
    @State private var nativePreview = false
    @State private var socialRefreshRevision = 0
    private var usesProfileSocialInbox: Bool {
        guard ProfileActivitySocialReleaseGate.productionReady else { return false }
        if ReviewDemoMode.isActive { return ProfileSocialInboxQA.enabled }
        return true
    }
    @State private var nativeSelection: NativeSelection?
    private struct NativeSelection: Identifiable {
        let row: AccountActivityFeedRow
        let context: AccountActivityReadContext
        let preview: Bool
        var id: UUID { row.cardID }
    }
    private var nativeContext: AccountActivityReadContext? {
        guard safety.canUseSocial || safety.canUseActivityPreview, let viewer = safety.viewerID else { return nil }
        return .init(viewerID: viewer, generation: safety.accountGeneration, safetyRevision: safety.revision)
    }
    init(fetcher:(any NotificationInboxFetching)?, profileFetcher:(any FeedRemoteProfileFetching)?, onSelectPost:@escaping(UUID,NotificationKind)->Void, onMarkedAllRead:@escaping()->Void,incomingFollowService:(any IncomingFollowServing)? = nil, nativeInboxAdapter: AccountActivityNativeInboxAdapter? = nil, incomingNativePush: NativeActivityPushPayload? = nil, standaloneNavigation: Bool = true, postDestination: ((FeedNotificationRequest) -> AnyView)? = nil) {
        self.standaloneNavigation = standaloneNavigation
        self.postDestination = postDestination
        self.incomingNativePush = incomingNativePush
        self.incomingFollowService=incomingFollowService;self.profileFetcher=profileFetcher;self.onSelectPost=onSelectPost;self.onMarkedAllRead=onMarkedAllRead
        _model=StateObject(wrappedValue:NotificationInboxModel(fetcher:fetcher))
        _legacyPreview = StateObject(wrappedValue: LegacyInboxPreviewModel(reader: fetcher as? any LegacyInboxPreviewReading, context: {
            let safety = CommunitySafetyStore.shared
            guard safety.canUseActivityPreview, let owner = safety.viewerID else { return nil }
            return .init(viewerID: owner, generation: safety.accountGeneration, safetyRevision: safety.revision)
        }))
        _nativeInboxAdapter=State(initialValue:nativeInboxAdapter)
    }
    var body: some View {
        SocialAccessBoundary(allowActivityPreview: true) {
            navigationContainer {
                List {
                    if incomingNativeFailed { Text("이 알림을 열 수 없어요. 현재 계정과 공개 상태를 확인해 주세요.") }
                    if safety.canUseSocial {
                        NavigationLink { EventNotificationInboxView() } label: {
                            Label("이벤트 알림", systemImage: "calendar")
                                .font(.subheadline.weight(.medium))
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("notifications.events")
                    }
                    if safety.canUseSocial { Section {
                    if let error = model.error, model.failureContext == .load || model.failureContext == .read || model.failureContext == nil {
                        VStack(alignment: .leading, spacing: SOOMLayout.Spacing.sm) {
                            SOOMActionFeedback(title: model.failureContext == .read ? "읽음 처리 미완료" : "알림을 불러오지 못했어요", message: error, isError: true)
                            if model.failureContext == .read {
                                Button("읽음 처리 다시 시도") { Task { await model.markRead() } }.frame(minHeight: 44)
                            } else {
                                Button("알림 다시 불러오기") { Task { await load() } }.frame(minHeight: 44).disabled(model.isLoading)
                            }
                        }.accessibilityIdentifier("notifications.error")
                    }
                    if model.isLoading && model.items.isEmpty {
                SOOMSkeleton(layout: .list, label: "알림 불러오는 중")
            }
                    if !model.isLoading,model.items.isEmpty,model.error == nil {
                        Text(usesProfileSocialInbox ? "팔로우 알림이 없어요" : "아직 알림이 없어요").font(.headline)
                        Text(usesProfileSocialInbox ? "팔로우 요청과 승인 내역이 여기에 표시돼요." : "응원·댓글·팔로우 요청과 승인 내역이 여기에 표시돼요.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let hidden = model.undoItem {
                        VStack(alignment: .leading, spacing: SOOMLayout.Spacing.sm) {
                            Text("최근 숨긴 알림").font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                            if let error = model.error, model.failureContext == .restore(hidden.id) {
                                SOOMActionFeedback(title: "숨김 취소 미완료", message: error, isError: true)
                            }
                            Button("알림 삭제 취소") { Task { await model.undoHide() } }
                                .frame(minHeight:44).disabled(model.busy.contains(hidden.id)).accessibilityIdentifier("notifications.undo")
                        }
                    }
                    ForEach(orderedItems) { item in
                        VStack(alignment: .leading, spacing: SOOMLayout.Spacing.sm) {
                        if isFirstInPeriod(item) {
                            Text(period(item.createdAt)).font(.subheadline.weight(.semibold)).foregroundStyle(SOOMColor.ink)
                                .padding(.top, 12).padding(.bottom, 2)
                                .accessibilityAddTraits(.isHeader)
                        }
                        Group {
                            switch item.destination {
                            case .post(let id): Button { selectPost(id, kind: item.type) } label: { row(item) }
                            case .requests: NavigationLink { FollowRequestsView(service:incomingFollowService) } label: { row(item) }
                            case .profile(let id): SOOMProfileLink(userID: id) { row(item) }
                            case nil: row(item)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("notifications.open.\(item.id)")
                        if let error = model.error, model.failureContext == .hide(item.id) {
                            SOOMActionFeedback(title: "이 알림을 숨기지 못했어요", message: error, isError: true)
                            Button { Task { await model.hide(item) } } label: {
                                Text("이 알림 다시 숨기기")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                                .disabled(model.busy.contains(item.id))
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("notifications.hideRetry.\(item.id)")
                        }
                        }
                        .swipeActions { Button("삭제",role:.destructive) { Task { await model.hide(item) } }.disabled(model.busy.contains(item.id)) }
                        .contextMenu { Button("알림 삭제",role:.destructive) { Task { await model.hide(item) } }.disabled(model.busy.contains(item.id)) }
                        .accessibilityAction(named:"알림 삭제") { Task { await model.hide(item) } }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("notifications.row.\(item.id)")
                        .accessibilityHint("알림 삭제는 내 목록에서만 숨기며 운동과 댓글은 유지돼요")
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                    }
                    }
                    if !safety.canUseSocial && safety.canUseActivityPreview {
                        Section("기존 알림 · 읽기 전용") {
                            if legacyPreview.loading { ProgressView("기존 알림 확인 중") }
                            if let error = legacyPreview.error { Text(error).font(.caption) }
                            ForEach(legacyPreview.rows) { item in
                                Button {
                                    guard safety.canUseActivityPreview, !safety.canUseSocial,
                                          let postID = legacyPreview.readOnlyPostID(for: item) else { return }
                                    selectPost(postID, kind: item.type)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.type.inboxMessage)
                                        Text(SOOMKoreanRelativeTime.text(item.createdAt)).font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .disabled(legacyPreview.readOnlyPostID(for: item) == nil)
                                .accessibilityIdentifier("notifications.preview.row.\(item.id)")
                                .accessibilityHint("현재 열람 권한을 다시 확인한 뒤 읽기 전용 운동 상세를 엽니다")
                            }
                            if !legacyPreview.loading && legacyPreview.error == nil && legacyPreview.rows.isEmpty { Text("현재 권한으로 확인되는 기존 알림이 없어요.") }
                            Text("최근 100개를 표시합니다. 기존 알림의 읽음 상태는 바꾸지 않아요.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if usesProfileSocialInbox, safety.canUseSocial {
                        ProfileSocialInboxSection(refreshRevision: socialRefreshRevision, onRead: onMarkedAllRead, onSelect: { profileSocialSelection = $0 })
                    }
                    if let nativeInboxAdapter {
                        AccountActivityNativeInboxSection(adapter: nativeInboxAdapter, context: nativeContext, onSelect: { row in
                            // A canonical card is never forwarded to legacy onSelectPost.
                            guard let context = nativeContext else { return }
                            nativeSelection = NativeSelection(row: row, context: context, preview: nativePreview)
                        }, onRead: onMarkedAllRead)
                    }
                    if safety.canUseSocial, let viewer = safety.viewerID {
                        NotificationFollowRecommendationsSection(ownerID: viewer)
                            .id("recommendations-\(viewer)-\(safety.accountGeneration)")
                    }
                }
                .listStyle(.plain).navigationTitle("알림").navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .refreshable { socialRefreshRevision += 1; await configureNativeInbox(); await load() }
                .toolbar {
                    if standaloneNavigation {
                        ToolbarItem(placement:.cancellationAction) { Button("닫기") { dismiss() } }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { NotificationSettingsView() } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("알림 설정").accessibilityIdentifier("notifications.settings")
                    }
                }
                .navigationDestination(isPresented: Binding(get: { legacySelection != nil }, set: { if !$0 { legacySelection = nil } })) {
                    if let request = legacySelection, let postDestination { postDestination(request) }
                }
                .navigationDestination(isPresented: Binding(get: { nativeSelection != nil }, set: { if !$0 { nativeSelection = nil } })) {
                    if let selection = nativeSelection {
                        NativeNotificationCardDestination(row: selection.row, context: selection.context, preview: selection.preview)
                    }
                }
                .task { await configureNativeInbox(); await load(); await openIncomingNative() }
                .onChange(of:model.receiptRevision) { _,_ in onMarkedAllRead() }
            }
        }
        .sheet(item: $profileSocialSelection) { selection in
            if scene == .active, safety.canUseSocial,
               selection.context.viewerID == safety.viewerID,
               selection.context.generation == safety.accountGeneration,
               selection.context.safetyRevision == safety.revision {
                if selection.reaction { ProfileActivitySocialCheersSheet(row: selection.row) }
                else { ProfileActivitySocialCommentsSheet(row: selection.row) }
            }
        }
        .feedCommentProfileNavigationHost()
        .onChange(of: scene) { _, phase in if phase != .active { profileSocialSelection = nil } }
        .onChange(of:safety.revision) { _,_ in
            profileSocialSelection = nil
            resetNative(); model.reset(); actorProfiles=[:]
            if !safety.canUseSocial && !safety.canUseActivityPreview { dismiss() } else { Task { await configureNativeInbox(); await load() } }
        }
        .onChange(of:safety.accountGeneration) { _,_ in profileSocialSelection = nil; resetNative(); model.reset(); actorProfiles=[:]; dismiss() }
    }
    @ViewBuilder private func navigationContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if standaloneNavigation { NavigationStack { content() } } else { content() }
    }
    private func selectPost(_ id: UUID, kind: NotificationKind) {
        if postDestination != nil {
            legacySelection = FeedNotificationRequest(postID: id, opensComments: kind.opensComments && safety.canUseSocial)
        } else { onSelectPost(id, kind) }
    }
    @MainActor private func openIncomingNative() async {
        guard !incomingNativeHandled, let payload=incomingNativePush else { return }
        incomingNativeHandled=true
        guard let adapter=nativeInboxAdapter,let context=nativeContext,payload.recipientID==context.viewerID else { incomingNativeFailed=true;return }
        let epoch=nativeConfigurationEpoch
        do {
            let rows=try await adapter.load(context:context)
            guard let event=rows.first(where:payload.matches) else { throw AccountActivityNativeInboxError.unavailable }
            let row=try await adapter.open(event,context:context)
            guard nativeContext==context,nativeConfigurationEpoch==epoch,!Task.isCancelled else {return}
            nativeSelection=NativeSelection(row:row,context:context,preview:nativePreview)
        } catch { if nativeContext==context,nativeConfigurationEpoch==epoch {incomingNativeFailed=true} }
    }
    @MainActor private func resetNative() {
        legacyPreview.reset()
        legacySelection = nil
        nativeConfigurationEpoch = UUID(); nativeSelection = nil; nativeInboxAdapter = nil; nativePreview = false
    }
    @MainActor private func configureNativeInbox() async {
        #if DEBUG && targetEnvironment(simulator)
        if nativeInboxAdapter == nil, AccountActivityNativeInboxUIFixture.enabled {
            nativeInboxAdapter = AccountActivityNativeInboxAdapter(fixtureTransport: AccountActivityNativeInboxUIFixture(context: {
                let safety = CommunitySafetyStore.shared
                guard safety.canUseSocial, safety.viewerID == ReviewDemoMode.userID else { return nil }
                return .init(viewerID: ReviewDemoMode.userID, generation: safety.accountGeneration, safetyRevision: safety.revision)
            }))
            return
        }
        #endif
        guard nativeInboxAdapter == nil, let initial = nativeContext,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { return }
        let epoch = nativeConfigurationEpoch
        let policy = AccountActivityReadPolicy.deployed
        let production = policy.inboxProductionReady
        if !production {
            guard policy == .approvedFollowersV1 else { return }
            guard let capability = try? await AccountActivityPreviewService(client: client, owner: initial.viewerID).capability(),
                  capability.enabled, nativeContext == initial, nativeConfigurationEpoch == epoch, !Task.isCancelled else { return }
            nativePreview = true
        }
        guard nativeContext == initial, nativeConfigurationEpoch == epoch, !Task.isCancelled else { return }
        nativeInboxAdapter = .makeLive(client: client, context: {
            let current = CommunitySafetyStore.shared
            guard current.canUseSocial || (nativePreview && current.canUseActivityPreview), let viewer = current.viewerID,
                  client.auth.currentSession?.user.id == viewer else { return nil }
            return .init(viewerID: viewer, generation: current.accountGeneration, safetyRevision: current.revision)
        }, preview: nativePreview, readPolicy: policy)
    }
    private var orderedItems: [NotificationDTO] {
        model.items.sorted { $0.createdAt > $1.createdAt }
    }
    private func period(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "오늘" }
        if calendar.isDateInYesterday(date) { return "어제" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        if days < 7 { return "최근 7일" }
        if days < 30 { return "최근 30일" }
        return "이전 활동"
    }
    private func isFirstInPeriod(_ item: NotificationDTO) -> Bool {
        guard let index = orderedItems.firstIndex(where: { $0.id == item.id }) else { return false }
        return index == 0 || period(orderedItems[index - 1].createdAt) != period(item.createdAt)
    }
    private func row(_ item: NotificationDTO) -> some View {
        NotificationInboxRow(item:item,profile:item.actorId.flatMap{actorProfiles[$0]})
    }
    private func load() async {
        guard safety.canUseSocial else {
            model.reset(); actorProfiles = [:]
            if safety.canUseActivityPreview { await legacyPreview.load() } else { legacyPreview.reset() }
            return
        }
        legacyPreview.reset()
        let generation=safety.accountGeneration,revision=safety.revision
        await model.load()
        let ids=Array(Set(model.items.compactMap(\.actorId)))
        if let profileFetcher,!ids.isEmpty,let profiles=try? await profileFetcher.fetchProfiles(ids:ids) {
            guard !Task.isCancelled,safety.canUseSocial,generation==safety.accountGeneration,revision==safety.revision else { return }
            actorProfiles=Dictionary(profiles.map{($0.id,$0)},uniquingKeysWith: {first,_ in first})
        }
    }
}
private struct NotificationInboxRow: View {
    let item: NotificationDTO
    let profile: FeedProfileDTO?
    private var actorName: String { profile?.displayName ?? "사용자" }
    private var message: String { item.type.inboxMessage }
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SOOMAvatarView(userID: item.actorId, avatarPath: profile?.avatarPath, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                (Text(item.type == .unknown ? "" : actorName).fontWeight(.semibold)
                 + Text(message)
                 + Text(" " + SOOMKoreanRelativeTime.text(item.createdAt)).foregroundColor(.secondary))
                    .font(.subheadline)
                    .foregroundStyle(SOOMColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if item.type.showsBodyPreview, let body = item.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if item.type == .followRequest {
                Text("요청 확인").font(.caption.weight(.semibold))
                    .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 10)
                    .background(SOOMColor.accent, in: RoundedRectangle(cornerRadius: 10))
            } else if item.readAt == nil {
                Circle().fill(SOOMColor.accent).frame(width: 7, height: 7)
                    .accessibilityLabel("안읽음")
            }
        }
        .padding(.vertical, 4).frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Explicit synthetic simulator harness. No APNs permission request, SDK login,
/// production token registry, network sender, or real follow mutation is used.
@MainActor
final class NotificationLocalQAStore: ObservableObject,NotificationInboxFetching {
    @Published var failFetchNext=false
    @Published var failReadNext=false
    @Published var failHideNext=false
    let status=PushRegistrationStatus()
    private var hidden=Set<UUID>()
    private var read=Set<UUID>()
    let actor=PrivacyLocalQAService.privateID
    var rows:[NotificationDTO] {
        let kinds: [NotificationKind] = ProcessInfo.processInfo.environment["SOOM_REPLY_MENTION_NOTIFICATION_QA"] == "1"
            ? [.reply, .mention] : [.followRequest, .followApproved, .comment]
        return kinds.enumerated().map { index,kind in
            let id=UUID(uuidString:String(format:"D3500000-0000-4000-8000-%012d",index+1))!
            return .init(id:id,recipientId:ReviewDemoMode.userID,actorId:actor,type:kind,postId:kind.showsBodyPreview ? UUID(uuidString:"D3500000-0000-4000-8000-000000000009")!:nil,body:nil,readAt:read.contains(id) ? Date():nil,createdAt:Date(timeIntervalSinceNow:Double(-index*60)))
        }
    }
    init() { status.state = .failed;status.permission = .denied }
    func fetchNotifications() async throws -> [NotificationDTO] {
        try await Task.sleep(nanoseconds:150_000_000)
        if failFetchNext {failFetchNext=false;throw NotificationInboxError.upgradeRequired}
        return rows.filter{!hidden.contains($0.id)}
    }
    func markAllNotificationsAsRead() async throws { try await markNotificationsAsRead(ids:rows.map(\.id)) }
    func markNotificationsAsRead(ids:[UUID]) async throws {if failReadNext {failReadNext=false;throw NotificationInboxError.upgradeRequired};read.formUnion(ids)}
    func hideNotification(id:UUID) async throws {if failHideNext {failHideNext=false;throw NotificationInboxError.upgradeRequired};hidden.insert(id)}
    func restoreNotification(id:UUID) async throws {hidden.remove(id)}
}
@MainActor
private struct NotificationLocalQARequester:NotificationPermissionRequesting {
    let status:PushRegistrationStatus
    func requestAuthorization() async {status.permission = .allowed}
    func registerForBackgroundUpdates() async {status.state = .registering;try? await Task.sleep(nanoseconds:150_000_000);status.state = .registered}
    func refreshPermissionStatus() async {}
}
struct NotificationLocalQAView:View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store=NotificationLocalQAStore()
    @State private var inbox=false
    private let incoming=PrivacyLocalQAService()
    var body:some View {
        NavigationStack {
            List {
                Text("합성 알림 검증 · 실발송 없음")
                NavigationLink("기기 등록 체험") {
                    ScrollView { PushRegistrationPanel(status:store.status,requester:NotificationLocalQARequester(status:store.status)).padding() }.navigationTitle("기기 등록 체험")
                }.accessibilityIdentifier("notificationQA.registration")
                Button("알림창 보기") {inbox=true}.accessibilityIdentifier("notificationQA.inbox")
                Toggle("다음 조회 실패",isOn:$store.failFetchNext).accessibilityIdentifier("notificationQA.fetchFailure")
                Toggle("다음 읽음 저장 실패",isOn:$store.failReadNext).accessibilityIdentifier("notificationQA.readFailure")
                Toggle("다음 삭제 실패",isOn:$store.failHideNext).accessibilityIdentifier("notificationQA.hideFailure")
                Text("운동·댓글·팔로우 관계 원본은 변경하지 않아요.")
            }.navigationTitle("알림 QA").toolbar {ToolbarItem(placement:.cancellationAction){Button("QA 닫기"){dismiss()}}}
            .sheet(isPresented:$inbox) {
                NotificationInboxView(fetcher:store,profileFetcher:nil,onSelectPost:{_,_ in},onMarkedAllRead:{},incomingFollowService:incoming)
            }
        }
    }
}
#endif


/// Candidates come only from the viewer's authorized follower list, not a new
/// global directory. Dismissal is a view-local preference, never a relationship mutation.
enum NotificationRecommendationPolicy {
    static func candidates(_ people: [SocialPerson], ownerID: UUID,
                           hidden: Set<UUID>, blocked: Set<UUID>) -> [SocialPerson] {
        var seen = Set<UUID>()
        return people.filter {
            $0.id != ownerID && !$0.isFollowing && !hidden.contains($0.id)
                && !blocked.contains($0.id) && seen.insert($0.id).inserted
        }
    }
}

private struct NotificationFollowRecommendationsSection: View {
    let ownerID: UUID
    @StateObject private var model: ProfileSocialModel
    @ObservedObject private var safety = CommunitySafetyStore.shared
    // Scoped by the parent identity to this viewer and account generation.
    @State private var hidden = Set<UUID>()
    init(ownerID: UUID) {
        self.ownerID = ownerID
        _model = StateObject(wrappedValue: ProfileSocialModel(ownerID: ownerID))
    }
    private var candidates: [SocialPerson] {
        guard model.errorMessage == nil, safety.canUseSocial, safety.viewerID == ownerID else { return [] }
        return NotificationRecommendationPolicy.candidates(model.people, ownerID: ownerID,
            hidden: hidden, blocked: Set(model.people.filter { safety.isBlocked($0.id) }.map(\.id)))
    }
    var body: some View {
        Section {
            if let error = model.errorMessage {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
                Button("목록 다시 불러오기") { Task { await model.load(kind: .followers) } }
                    .disabled(model.isLoading || !model.busyIDs.isEmpty)
                    .accessibilityIdentifier("notifications.recommendations.retry")
            } else if model.isLoading && model.people.isEmpty {
                ProgressView("팔로워 확인 중")
            } else if candidates.isEmpty {
                Text("지금 표시할 사람이 없어요.").font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("notifications.recommendations.empty")
            }
            ForEach(candidates) { person in
                HStack(spacing: 12) {
                    SOOMProfileLink(userID: person.id) {
                        HStack(spacing: 12) {
                            SOOMAvatarView(userID: person.id, avatarPath: person.avatarPath, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(person.displayName).font(.subheadline.weight(.semibold))
                                Text("나를 팔로우하고 있어요").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Button(person.actionTitle(viewerID: ownerID) ?? "팔로우") {
                        Task { await model.toggle(person) }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.busyIDs.isEmpty || model.isLoading)
                    .accessibilityIdentifier("notifications.recommendations.follow.\(person.id)")
                    Button { hidden.insert(person.id) } label: {
                        Image(systemName: "xmark").font(.caption)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.borderless)
                        .accessibilityLabel("\(person.displayName) 추천 숨기기")
                        .accessibilityHint("팔로우 관계는 바뀌지 않아요")
                        .accessibilityIdentifier("notifications.recommendations.hide.\(person.id)")
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 8))
                .listRowSeparator(.hidden)
            }
            if model.hasMore {
                Button("더 보기") { Task { await model.load(kind: .followers, reset: false) } }
                    .disabled(model.isLoading || !model.busyIDs.isEmpty)
            }
        } header: {
            Text("팔로우 추천")
                .textCase(nil)
        }
        .task { await model.load(kind: .followers) }
        .onChange(of: safety.revision) { _, _ in
            // toggle owns its final reload. Do not race it with a second page load.
            guard model.busyIDs.isEmpty else { return }
            Task { await model.load(kind: .followers) }
        }
    }
}


/// The notification destination owns the card; dismissing its child comments
/// must not dismiss the card or insert it into the followed home feed.
struct NativeNotificationCardPresentation {
    let row: AccountActivityFeedRow
    let context: AccountActivityReadContext
    private(set) var didPresentInitialComments = false
    var commentsPresented = false
    func permits(_ current: AccountActivityReadContext?) -> Bool { current == context }
    mutating func presentInitialComments(current: AccountActivityReadContext?) {
        guard permits(current), !didPresentInitialComments else { return }
        didPresentInitialComments = true
        commentsPresented = true
    }
}

private struct NativeNotificationCardDestination: View {
    let preview: Bool
    @State private var presentation: NativeNotificationCardPresentation
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scene
    init(row: AccountActivityFeedRow, context: AccountActivityReadContext, preview: Bool) {
        self.preview = preview
        _presentation = State(initialValue: .init(row: row, context: context))
    }
    private var currentContext: AccountActivityReadContext? {
        guard safety.canUseSocial || (preview && safety.canUseActivityPreview), let viewer = safety.viewerID else { return nil }
        return .init(viewerID: viewer, generation: safety.accountGeneration, safetyRevision: safety.revision)
    }
    var body: some View {
        SocialAccessBoundary(allowActivityPreview: preview) {
                ScrollView {
                    if presentation.permits(currentContext) {
                        AccountActivitySummaryCard(row: presentation.row)
                            .environment(\.soomActivityPreview, preview)
                            .environment(\.soomFeedIsActive, scene == .active)
                            .padding(SOOMLayout.screenPadding)
                    }
                }
                .navigationTitle("운동 기록").navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("notifications.native.card.\(presentation.row.cardID)")
                .toolbar(.visible, for: .navigationBar)
                .task { presentation.presentInitialComments(current: currentContext) }
                .sheet(isPresented: $presentation.commentsPresented) {
                    if presentation.permits(currentContext) {
                        AccountActivityCommentsSheet(row: presentation.row, preview: preview)
                    }
                }
                .feedCommentProfileNavigationHost()
        }
        .onChange(of: currentContext) { _, current in
            if !presentation.permits(current) { presentation.commentsPresented = false; dismiss() }
        }
        .onChange(of: scene) { _, phase in
            if phase == .background { presentation.commentsPresented = false; dismiss() }
        }
    }
}
