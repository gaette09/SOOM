import SwiftUI
import SwiftData
import Supabase

/// Uses only invented, non-sensitive values in the existing card structure.
/// No workout/profile/photo identity is supplied, so this cannot load content.
struct AccountActivityWorkoutPlaceholder: View {
    var minimumHeight: CGFloat = 0
    var hasKnownMedia: Bool? = nil
    var body: some View {
        VStack(spacing: 0) {
            WorkoutRecordCard(title: "운동 기록", description: nil,
                date: Date(timeIntervalSince1970: 0), sport: .running,
                author: "작성자", device: "기기", location: "지역",
                metrics: [.init(label: "거리", value: "0.00 km"), .init(label: "페이스", value: "0:00/km"), .init(label: "총 시간", value: "00분 0초")],
                photosAreKnown: true, photos: []) { EmptyView() }
                .redacted(reason: .placeholder).accessibilityHidden(true)
            if hasKnownMedia == true {
                Rectangle().fill(Color(uiColor: .tertiarySystemFill)).frame(height: 260)
            }
            HStack {
                Image(soom: SOOMIcon.thumbsUp); Spacer(); Image(soom: SOOMIcon.comment)
            }.frame(minHeight: 48).padding(.horizontal, 16).padding(.vertical, 10)
                .redacted(reason: .placeholder).accessibilityHidden(true)
            Rectangle().fill(SOOMColor.surfaceMuted).frame(height: 6)
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .top)
        .background(SOOMColor.surface)
        .allowsHitTesting(false).disabled(true)
        .accessibilityElement(children: .ignore).accessibilityLabel("공개 범위 확인 중")
        .accessibilityIdentifier("feed.workout.placeholder")
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}

/// Loading participates in layout. An overlay on the 224-point initial slot
/// can paint its taller skeleton over neighboring lazy rows.
struct AccountActivityPendingCard: View {
    let minimumHeight: CGFloat
    var reservedHeight: CGFloat? = nil
    var hasKnownMedia: Bool? = nil
    let unavailable: Bool
    let retry: () -> Void
    var body: some View {
        Group {
            if let reservedHeight {
                // Keep only the verified geometry, never the previous content.
                SOOMColor.surfaceMuted.opacity(0.25).frame(height: reservedHeight).overlay {
                    if unavailable {
                        Button("다시 시도", action: retry).frame(minHeight: 44)
                            .accessibilityLabel("운동 요약을 확인할 수 없어요. 다시 시도")
                            .accessibilityIdentifier("feed.projection.retry")
                    } else {
                        // Authorization is still required, but a routine return
                        // must not look like a privacy error or a blank screen.
                        AccountActivityWorkoutPlaceholder(hasKnownMedia: hasKnownMedia)
                            .frame(height: reservedHeight, alignment: .top)
                            .accessibilityLabel("운동 기록 불러오는 중")
                    }
                }.clipped()
            } else if unavailable {
                VStack(spacing: 8) {
                    Text("운동 요약을 확인할 수 없어요").font(.headline)
                    Text("공개 범위가 변경됐거나 기록을 불러오지 못했어요.").font(.caption).foregroundStyle(.secondary)
                    Button("다시 시도", action: retry).frame(minHeight: 44).accessibilityIdentifier("feed.projection.retry")
                }.padding(24)
            } else {
                AccountActivityWorkoutPlaceholder(minimumHeight: minimumHeight, hasKnownMedia: hasKnownMedia)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight)
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor final class ProjectionVerificationProbe: ObservableObject {
    static let shared = ProjectionVerificationProbe()
    @Published private(set) var counts: [UUID: Int] = [:]
    func begin(_ id: UUID) { counts[id, default: 0] += 1 }
    static func trace(_ message: String) {
        guard ProcessInfo.processInfo.environment["SOOM_PROJECTION_DEEP_QA"] == "1" else { return }
        let line = "\(Date().timeIntervalSince1970) pid=\(ProcessInfo.processInfo.processIdentifier) SOOM54 \(message)\n"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("soom54-trace.log")
        if !FileManager.default.fileExists(atPath: url.path) { try? Data().write(to: url) }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd(); try? handle.write(contentsOf: Data(line.utf8))
        }
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
@MainActor enum Feed61CardLifecycleProbe {
    static var isEnabled: Bool { ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_FEED_MIXED_REUSE_QA"] == "1" }
    private static var lifetimes: Set<UUID> = []
    private(set) static var ownLifetimeCount = 0
    private(set) static var foreignLifetimeCount = 0
    private(set) static var ownPlaceholderBranchAppearances = 0
    private(set) static var foreignPlaceholderBranchAppearances = 0
    private(set) static var ownImmediateReadyAppearances = 0
    static func appeared(lifetime: UUID, own: Bool, immediateReady: Bool) {
        guard isEnabled else { return }
        if own && immediateReady { ownImmediateReadyAppearances += 1 }
        guard !lifetimes.contains(lifetime), lifetimes.count < 1024 else { return }
        lifetimes.insert(lifetime)
        if own { ownLifetimeCount += 1 } else { foreignLifetimeCount += 1 }
    }
    /// Pending branch appearance, including SwiftUI prefetch; not evidence of onscreen visibility.
    static func placeholderBranchAppeared(own: Bool) {
        guard isEnabled else { return }
        if own { ownPlaceholderBranchAppearances += 1 } else { foreignPlaceholderBranchAppearances += 1 }
    }
}
#endif

enum AccountActivityReturnBatchPolicy {
    static func verifiedViewer(sessionID: UUID?, safetyViewerID: UUID?) -> UUID? {
        guard let sessionID, sessionID == safetyViewerID else { return nil }; return sessionID
    }
    static func access(source: AccountActivityFeedRow, batch: FeedReturnBatchPresentation?, viewerID: UUID?,
                       generation: Int, safetyRevision: Int, returnEpoch: Int) -> FeedReturnAccess<FeedReturnCardGrant>? {
        guard let batch else { return nil }
        guard source.readPolicy == .profileOnlyV2,
              batch.context.matches(viewerID: viewerID, accountGeneration: generation, safetyRevision: safetyRevision, returnEpoch: returnEpoch) else { return .denied }
        let access = batch.cardAccess(rowID: source.cardID)
        if case .authorized(let grant) = access {
            guard grant.row.cardID == source.cardID, grant.row.ownerID == source.ownerID,
                  grant.row.canonicalID == source.canonicalID, grant.row.readPolicy == .profileOnlyV2 else { return .denied }
        }
        return access
    }
}
extension View {
    /// Child profiles/details own their authorization; never inherit a home viewport grant.
    func independentFeedReturnScope() -> some View {
        environment(\.soomFeedReturnBatch, nil).environment(\.soomFeedVisibleCardRegistration, nil).environment(\.soomFeedReturnRetry, nil)
            .environment(\.soomFeedLinkedCardStore, nil).environment(\.soomFeedCardGrantIsCurrent, nil)
            .environment(\.soomFeedRoutePlaybackHistory, nil)
            .environment(\.soomFeedSocialPresentationStore, nil)
    }
}

/// A projection is not a feed_posts row. Never route its ID into reactions,
/// comments, photos, deletion, or the legacy detail lookup.
struct AccountActivitySummaryCard: View {
    private struct VerifiedGeometry: Equatable { let size: CGSize; let contentRevision: String }
    private let sourceRow: AccountActivityFeedRow
    var currentProfileID: UUID? = nil
    @Query private var observedOwnRecords: [UnifiedWorkoutRecord]
    init(row: AccountActivityFeedRow, currentProfileID: UUID? = nil, localViewerID: UUID? = nil) {
        sourceRow = row; self.currentProfileID = currentProfileID
        let id = row.canonicalID, owned = localViewerID == row.ownerID
        // Observe the exact local source once. Foreign cards never select a
        // local record, and body/authorization reads never issue manual fetches.
        _observedOwnRecords = Query(filter: #Predicate<UnifiedWorkoutRecord> { $0.id == id && owned })
    }
    private var row: AccountActivityFeedRow {
        if case .authorized(let grant)? = returnAccess { return grant.row }
        return sourceRow
    }
    #if DEBUG && targetEnvironment(simulator)
    @ObservedObject private var verificationProbe = ProjectionVerificationProbe.shared
    @State private var qaLifetime = UUID()
    #endif
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var storage: HealthAccountStorageController
    @EnvironmentObject private var auth: AuthViewModel
    @State private var showSummaryDetail = false
    @State private var summaryOpeningGeneration: Int?
    @State private var summaryDetailAuthor: FeedProfileDTO?
    @State private var ownDetail: UnifiedWorkout?
    @State private var ownDetailKey: String?
    @State private var ownDetailScope: String?
    @State private var ownCardWorkout: UnifiedWorkout?
    @State private var ownCardLoadedKey: String?
    @State private var ownCardResolvedKey: String?
    @Environment(\.soomActivityPreview) private var preview
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @ObservedObject private var staleSummaryCache = FeedStaleSummaryCache.shared
    @Environment(\.locale) private var cacheLocale
    @Environment(\.layoutDirection) private var cacheDirection
    @Environment(\.legibilityWeight) private var cacheWeight
    @Environment(\.soomFeedRevalidationRevision) private var revision
    @Environment(\.soomFeedIsActive) private var active
    @Environment(\.soomFeedReturnRetry) private var retryReturnBatch
    @Environment(\.soomFeedReturnBatch) private var returnBatch
    @Environment(\.soomFeedBatchIsCurrent) private var batchIsCurrent
    @Environment(\.soomFeedLinkedCardStore) private var linkedCardStore
    @Environment(\.soomFeedCardGrantIsCurrent) private var cardGrantIsCurrent
    @Environment(\.soomFeedSocialPresentationStore) private var socialPresentationStore
    @Environment(\.soomFeedSocialPresentationRevision) private var socialPresentationRevision
    @Environment(\.soomFeedVisibleCardRegistration) private var registerVisibleCard
    private var returnAccess: FeedReturnAccess<FeedReturnCardGrant>? {
        if let batch = returnBatch, batch.phase == .ready, batchIsCurrent?(batch.id) != true { return .pending }
        let access = AccountActivityReturnBatchPolicy.access(source: sourceRow, batch: returnBatch, viewerID: AccountActivityReturnBatchPolicy.verifiedViewer(sessionID: auth.session.currentUser?.id, safetyViewerID: safety.viewerID),
            generation: safety.accountGeneration, safetyRevision: safety.revision, returnEpoch: revision)
        if let batch = returnBatch, case .authorized(let grant)? = access {
            let authority = FeedLinkedCardAuthority(context: batch.context, batchID: batch.id, grantID: grant.id, row: grant.row)
            guard cardGrantIsCurrent?(authority) == true else { return .pending }
        }
        return access
    }
    private var batchKey: String {
        guard let batch = returnBatch else { return "independent" }
        switch returnAccess {
        case .authorized(let grant)?: return "\(batch.id):\(grant.id)"
        case .denied?: return "\(batch.id):denied"
        default: return "\(batch.id):pending"
        }
    }
    @Environment(\.scenePhase) private var scene
    @Environment(\.soomScrollViewportWidth) private var viewportWidth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var lastVerifiedMedia: Bool?
    @State private var mediaKnowledgeKey: String?
    @State private var heightReservation = SOOMFeedCardLayoutReservation<DynamicTypeSize>()
    @Environment(\.soomFeedCardGeometryStore) private var cardGeometry
    private var geometryScope: FeedCardGeometryScope {
        .init(viewerID: safety.viewerID, generation: safety.accountGeneration, safetyRevision: safety.revision)
    }
    private var geometryKey: FeedCardGeometryKey? {
        guard let width = viewportWidth, width.isFinite, width > 0 else { return nil }
        return .init(cardID: sourceRow.cardID, width: width, font: String(describing: dynamicTypeSize), kind: "projection")
    }
    private var reservedHeight: CGFloat? {
        guard let geometryKey else { return nil }
        return cardGeometry?.height(for: geometryKey, scope: geometryScope)
    }
    @State private var verifiedKey: String?
    @State private var unavailable = false
    @State private var author: FeedProfileDTO?
    private struct ProfilePresentation: Identifiable {
        let id: UUID
        let generation: Int
    }
    @State private var showComments = false
    @State private var commentBadge = AccountActivityCommentBadge()
    @State private var socialLegacyItem: FeedItem?
    @State private var profileSocialStatus: ProfileActivitySocialStatus?
    @State private var profileSocialPending = false
    @State private var socialBatchAppliedKey: String?
    @State private var showProfileCheers = false
    private var usesProfileSocial: Bool {
        guard !preview, row.readPolicy == .profileOnlyV2, ProfileActivitySocialReleaseGate.productionReady else { return false }
        if ReviewDemoMode.isActive {
            #if DEBUG && targetEnvironment(simulator)
            return ProcessInfo.processInfo.environment["SOOM_PROFILE_SOCIAL_QA"] == "1"
            #else
            return false
            #endif
        }
        return true
    }
    private var socialOverride: Feed60SocialPresentationStore.Override? {
        _ = socialPresentationRevision
        guard let authority = linkedAuthority else { return nil }
        return socialPresentationStore?.resident(authority, isCurrent: { cardGrantIsCurrent?(authority) == true })
    }
    private var displayedSocialStatus: ProfileActivitySocialStatus? {
        if let value = socialOverride {
            switch value { case .unknown: return nil; case .ready(let status): return status }
        }
        // A locally refreshed, mutated or failed state must never fall back to
        // the older batch value. Only an uninitialized lazy row uses its grant.
        return verifiedKey == key ? profileSocialStatus : synchronousGrant?.socialStatus
    }
    private var socialStateKnown: Bool { !usesProfileSocial || displayedSocialStatus != nil }
    private var viewerHasCheered: Bool { usesProfileSocial ? displayedSocialStatus?.viewer_has_cheered == true : socialLegacyItem?.viewerHasCheered == true }
    private var hasComments: Bool { usesProfileSocial ? (displayedSocialStatus?.comment_count ?? 0) > 0 : commentBadge.count > 0 }
    private func hasRecentComments(now: Date) -> Bool { usesProfileSocial ? displayedSocialStatus?.hasRecentComment(now: now) == true : commentBadge.isRecent(now: now) }
    @State private var socialRefresh = 0
    @State private var socialRead = AccountActivitySocialReadReceipt()
    @State private var socialReadRequestID: UUID?
    @State private var cheerNeedsRefresh = false
    private var socialKey: String { "\(key):\(socialRefresh)" }
    @State private var cheerBusy = false
    @State private var photos: [WorkoutPhotoReference] = []
    @State private var legacyAvailable = false
    @State private var legacyBusy = false
    @State private var legacyError: String?
    @State private var linkedPresentation: FeedLinkedCardPresentation?
    @State private var legacyEnrichmentRead = AccountActivitySocialReadReceipt()
    @State private var legacyEnrichmentRequestID: UUID?
    @State private var verifiedLegacyItem: FeedItem?
    @State private var legacyDetail: FeedItem?
    @State private var legacyOpeningGeneration: Int?
    @State private var legacyDetailAuthor: FeedProfileDTO?
    @State private var legacyComments: FeedItem?
    private var rowKey: String { "\(row.ownerID):\(row.canonicalID):\(row.sport):\(row.activityAt):\(row.durationSeconds):\(String(describing: row.distanceMeters))" }
    private var key: String { "\(row.cardID):\(row.revision):\(safety.accountGeneration):\(safety.revision):\(revision):\(active):\(scene == .active):\(preview):\(row.readPolicy.rawValue):\(rowKey):\(batchKey)" }
    private var synchronousGrant: FeedReturnCardGrant? {
        guard active, scene == .active, safety.canUseSocial,
              case .authorized(let grant)? = returnAccess else { return nil }
        return grant
    }
    private var linkedAuthority: FeedLinkedCardAuthority? {
        guard let batch = returnBatch, let grant = synchronousGrant else { return nil }
        return .init(context: batch.context, batchID: batch.id, grantID: grant.id, row: grant.row)
    }
    private var displayedLinkedPresentation: FeedLinkedCardPresentation? {
        if let grant = synchronousGrant, grant.hasBatchCardPreview { return grant.batchCardPreview }
        if legacyEnrichmentRead.isVerified(for: key) { return linkedPresentation }
        guard let authority = linkedAuthority else { return nil }
        return linkedCardStore?.resident(authority, isCurrent: { cardGrantIsCurrent?(authority) == true })?.presentation
    }
    private var displayedAuthor: FeedProfileDTO? { verifiedKey == key ? author : synchronousGrant?.author }
    private var displayedPhotos: [WorkoutPhotoReference] {
        if verifiedKey == key { return photos }
        guard let grant = synchronousGrant, grant.photosAvailable else { return [] }
        return grant.photos
    }
    private func hasVerifiedPresentation(ownResolution: Feed61OwnLocalRecordReader.Result?) -> Bool {
        guard active, scene == .active else { return false }
        if returnBatch != nil && synchronousGrant == nil { return false }
        if let ownResolution { return ownResolution.isResolved }
        // Local owner materialization has an additional container/source check;
        // never flash a remote summary in place of that authoritative card.
        if ownCardAccessAllowed && ownCardResolvedKey != ownCardLoadKey { return false }
        return verifiedKey == key || (synchronousGrant != nil && row.ownerID != safety.viewerID)
    }
    private func cachedReservedHeight(_ snapshot: FeedStaleSummarySnapshot) -> CGFloat? {
        if let reservedHeight { return reservedHeight }
        guard let viewportWidth else { return nil }
        let environment = FeedStaleSummaryLayout.environment(locale: cacheLocale.identifier,
            direction: String(describing: cacheDirection), weight: String(describing: cacheWeight))
        guard let height = snapshot.layout?.height(width: Double(viewportWidth),
            dynamicType: String(describing: dynamicTypeSize), environment: environment,
            contentRevision: snapshot.layoutRevision) else { return nil }
        return CGFloat(height)
    }

    var body: some View {
        let ownResolution = currentFeedOwnResolution
        Group {
            if hasVerifiedPresentation(ownResolution: ownResolution), let date = row.cursor?.activityAt {
                VStack(spacing: 0) {
                    if let ownWorkout = ownResolution?.workout {
                        immediateOwnCard(ownWorkout)
                    } else if ownResolution == nil, let ownWorkout = permittedOwnWorkout {
                        WorkoutManagementHost(workout: ownWorkout) { current, management in
                            OwnedWorkoutRecordCard(workout: current, showsManagement: true, enrichRegion: false,
                                isAuthorized: { ownCardAccessAllowed && ownCardLoadedKey == ownCardLoadKey },
                                onOpen: { Task { await openWorkout() } }) {
                                WorkoutManagementButtons(model: management, includesBookmark: false)
                            }
                        }
                    } else {
                    WorkoutRecordCard(title: displayedLinkedPresentation.flatMap { $0.title.isEmpty ? nil : $0.title } ?? presentation.title,
                        description: displayedLinkedPresentation?.caption, date: date, sport: presentation.sport,
                        author: displayedAuthor?.displayName ?? "작성자 정보 확인 불가",
                        authorID: displayedAuthor?.id, showsManagement: row.ownerID == safety.viewerID,
                        avatarPath: displayedAuthor?.avatarPath, device: displayedLinkedPresentation?.device,
                        location: displayedLinkedPresentation == nil ? "지역 정보 미표시" : FeedCardFormatting.region(displayedLinkedPresentation?.location,
                            hasRoute: permittedRoute != nil), metrics: presentation.metrics,
                        route: permittedRoute, routePrivacyAlreadyApplied: permittedRoute != nil,
                        photosAreKnown: true, photos: displayedPhotos,
                        onOpen: { Task {
                            if ownResolution != nil { await openImmediateOwnWorkout(requiresLocalRecord: false) }
                            else { await openWorkout() }
                        } },
                        onOpenAuthor: nil) {
                            AccountActivityOwnerEditMenu(ownerID: row.ownerID, canonicalID: row.canonicalID)
                        }
                    }
                    if interactionsAvailable {
                        HStack {
                            Button { Task { await toggleCheer() } } label: {
                                Image(soom: viewerHasCheered ? "hand.thumbsup.fill" : SOOMIcon.thumbsUp)
                                    .font(.system(size: 25)).frame(maxWidth: .infinity, minHeight: 48)
                                    .opacity(socialStateKnown ? 1 : 0.25)
                                    .overlay {
                                        if !socialStateKnown {
                                            if cheerNeedsRefresh { Image(systemName: "questionmark.circle").font(.system(size: 18)) }
                                            else { ProgressView().controlSize(.mini) }
                                        }
                                    }
                            }
                            .disabled(!canCheer || cheerBusy || legacyBusy)
                            .accessibilityLabel(socialStateKnown ? (viewerHasCheered ? "응원 취소" : "응원") : (cheerNeedsRefresh ? "응원 상태 확인 필요" : "응원 상태 확인 중"))
                            .accessibilityHint(canCheer ? "" : "이 기록은 아직 응원을 지원하지 않아요")
                            .accessibilityIdentifier("feed.projection.cheer")
                            .contextMenu {
                                if usesProfileSocial, profileSocialStatus != nil {
                                    Button("응원한 사람 보기") { showProfileCheers = true }
                                }
                            }
                            Button { Task { await openComments() } } label: {
                                TimelineView(.periodic(from: .now, by: 60)) { context in
                                    Image(soom: SOOMIcon.comment).font(.system(size: 25))
                                        .overlay(alignment: .topTrailing) {
                                            if hasComments {
                                                let isNew = hasRecentComments(now: context.date)
                                                Circle().fill(SOOMColor.accent)
                                                    .frame(width: isNew ? 15 : 8, height: isNew ? 15 : 8)
                                                    .overlay {
                                                        if isNew { Text("n").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
                                                    }.offset(x: 7, y: -5)
                                                    .accessibilityIdentifier("feed.projection.commentBadge")
                                            }
                                        }
                                }.frame(maxWidth: .infinity, minHeight: 48)
                            }.disabled(legacyBusy || cheerBusy || !socialStateKnown)
                                .accessibilityLabel("댓글 보기")
                                .accessibilityValue(!socialStateKnown ? "댓글 상태 확인 중" : (hasRecentComments(now: Date()) ? "최근 댓글 있음" : (hasComments ? "댓글 있음" : "")))
                                .accessibilityIdentifier("feed.projection.comments")
                        }.buttonStyle(.plain).foregroundStyle(SOOMColor.ink)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                    }
                    if let legacyError {
                        Text(legacyError).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                    }
                    if cheerNeedsRefresh {
                        Button(profileSocialPending ? "기존 요청 확인 및 재시도" : "응원 상태 다시 확인") {
                            if usesProfileSocial && profileSocialPending { Task { await recoverProfileSocial() } }
                            else { socialRefresh += 1 }
                        }
                            .disabled(cheerBusy || legacyBusy || socialReadRequestID != nil)
                            .frame(minHeight: 44).accessibilityHint("응원을 다시 보내지 않고 저장된 상태만 확인합니다")
                    }
                    Rectangle().fill(SOOMColor.surfaceMuted).frame(height: 6)
                }
                .onPreferenceChange(WorkoutCardMediaPresenceKey.self) { value in
                    guard verifiedKey == key, active, scene == .active else { return }
                    lastVerifiedMedia = value; mediaKnowledgeKey = ownDestinationKey
                }
                .onGeometryChange(for: VerifiedGeometry.self) {
                    .init(size: $0.size, contentRevision: "\(row.revision):\(displayedPhotos.count)")
                } action: { measured in
                    let size = measured.size
                    guard hasVerifiedPresentation(ownResolution: ownResolution) else { return }
                    var next = heightReservation
                    if next.record(size, viewportWidth: viewportWidth, layoutToken: dynamicTypeSize) { heightReservation = next }
                    if let geometryKey { cardGeometry?.record(size.height, for: geometryKey, scope: geometryScope) }
                    if let batch = returnBatch, synchronousGrant != nil {
                        staleSummaryCache.captureLayout(cardID: sourceRow.cardID, scope: FeedStaleSummaryCache.scope(batch.context),
                            width: Double(size.width), height: Double(size.height), dynamicType: String(describing: dynamicTypeSize),
                            environment: FeedStaleSummaryLayout.environment(locale: cacheLocale.identifier,
                                direction: String(describing: cacheDirection), weight: String(describing: cacheWeight)))
                    }
                }
                .background(SOOMColor.surface)
                .padding(.horizontal, -SOOMLayout.screenPadding)
            } else if let local = pendingOwnWorkout {
                // Local owner records have their own account/container/journal
                // authority. This is not a lease for remote photos or social data.
                OwnedWorkoutRecordCard(workout: local, showsManagement: false, enrichRegion: false,
                    ownedPhotoPresentation: .unavailable, ownedAuthorPresentation: .localOwner,
                    isAuthorized: { pendingOwnWorkout == local }) { EmptyView() }
                    .frame(minHeight: reservedHeight ?? pendingHeight, alignment: .top)
                    .background(SOOMColor.surface)
                    .padding(.horizontal, -SOOMLayout.screenPadding)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("feed.own.localPending.\(row.cardID)")
            } else {
                Group {
                if staleSummaryCache.enabled {
                Group {
                    if active, scene == .active, safety.canUseSocial,
                       let viewer = auth.session.currentUser?.id, viewer == safety.viewerID,
                       let cached = staleSummaryCache.snapshot(cardID: sourceRow.cardID,
                        scope: .init(viewerID: viewer, generation: safety.accountGeneration,
                            safetyRevision: safety.revision, policyVersion: 1), now: Date()),
                       cached.ownerID == sourceRow.ownerID, !safety.isBlocked(cached.ownerID),
                       let cachedHeight = cachedReservedHeight(cached) {
                        FeedStaleSummaryView(snapshot: cached)
                            .frame(height: cachedHeight, alignment: .top).clipped()
                            #if DEBUG && targetEnvironment(simulator)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                staleSummaryCache.recordPresentedHeight(cardID: cached.id, height: Double($0))
                            }
                            #endif
                    } else {
                        AccountActivityPendingCard(minimumHeight: reservedHeight ?? pendingHeight, reservedHeight: reservedHeight,
                            hasKnownMedia: mediaKnowledgeKey == ownDestinationKey ? lastVerifiedMedia : nil, unavailable: unavailable) {
                            if returnBatch != nil { retryReturnBatch?(sourceRow.cardID) } else { Task { await verify() } }
                        }
                    }
                }
                } else {
                    AccountActivityPendingCard(minimumHeight: reservedHeight ?? pendingHeight, reservedHeight: reservedHeight,
                        hasKnownMedia: mediaKnowledgeKey == ownDestinationKey ? lastVerifiedMedia : nil, unavailable: unavailable) {
                        if returnBatch != nil { retryReturnBatch?(sourceRow.cardID) } else { Task { await verify() } }
                    }
                }
                }.padding(.horizontal, -SOOMLayout.screenPadding)
                 .accessibilityElement(children: .contain)
                 .accessibilityIdentifier("feed.projection.pending.\(row.cardID)")
                 #if DEBUG && targetEnvironment(simulator)
                 .onAppear {
                     Feed61CardLifecycleProbe.placeholderBranchAppeared(own: row.ownerID == safety.viewerID)
                 }
                 #endif
            }
        }
        .animation(nil, value: verifiedKey)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.projection.summary.\(row.cardID)")
        #if DEBUG && targetEnvironment(simulator)
        .accessibilityValue((ProcessInfo.processInfo.environment["SOOM_PROJECTION_LOADING_QA"] == "1" || ProcessInfo.processInfo.environment["SOOM_PROJECTION_DEEP_QA"] == "1") ? "검증 요청 \(verificationProbe.counts[row.cardID, default: 0])" : "")
        #endif
        #if DEBUG && targetEnvironment(simulator)
        .onAppear {
            qaTrace("appear")
            if Feed61CardLifecycleProbe.isEnabled {
                Feed61CardLifecycleProbe.appeared(lifetime: qaLifetime, own: row.ownerID == safety.viewerID,
                    immediateReady: currentFeedOwnResolution?.workout != nil)
            }
        }
        .onDisappear { qaTrace("disappear") }
        #endif
        .onAppear { registerVisibleCard?(sourceRow.cardID, true) }
        .onDisappear { registerVisibleCard?(sourceRow.cardID, false) }
        .onChange(of: socialPresentationRevision) { _, _ in recoverUnknownSocialPresentation() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            if usesProfileSocial, verifiedKey == key {
                profileSocialStatus = nil; socialRead.invalidate(); cheerNeedsRefresh = true
                legacyError = "응원 상태를 다시 확인해 주세요."
            }
        }
        .task(id: key) { await verify() }
        .task(id: ownCardLoadKey + ":\(verifiedKey ?? "pending")") { await loadOwnCard() }
        .task(id: "\(verifiedKey ?? "pending"):\(socialRefresh)") { await refreshSocial() }
        .task(id: "legacy-enrichment:\(verifiedKey ?? "pending")") { await enrichLegacyDetail() }
        .sheet(isPresented: $showComments, onDismiss: { socialRefresh += 1 }) {
            if verifiedKey == key {
                if usesProfileSocial { ProfileActivitySocialCommentsSheet(row: row).independentFeedReturnScope() }
                else { AccountActivityCommentsSheet(row: row, preview: preview).independentFeedReturnScope() }
            }
        }
        .sheet(isPresented: $showProfileCheers) { if verifiedKey == key && usesProfileSocial { ProfileActivitySocialCheersSheet(row: row).independentFeedReturnScope() } }
        .sheet(item: $legacyComments, onDismiss: { socialRefresh += 1 }) { item in
            if verifiedKey == key { FeedCommentsSheet(item: item).independentFeedReturnScope() }
        }
        .navigationDestination(isPresented: Binding(get: { legacyDetail != nil || ownDetail != nil || showSummaryDetail }, set: { if !$0 { legacyDetail = nil; ownDetail = nil; showSummaryDetail = false } })) {
            Group {
                if let workout = ownDetail, ownDetailKey == ownDestinationKey, ownDetailScope == storage.scopeID,
                   ownDestinationAllowed, ownRecordStillExists(workout.id) {
                    OwnWorkoutDetailDestination(workout: workout)
                } else if showSummaryDetail, summaryOpeningGeneration == safety.accountGeneration {
                    AccountActivitySummaryDetailDestination(row: row, author: summaryDetailAuthor)
                } else if let item = legacyDetail, legacyOpeningGeneration == safety.accountGeneration {
                    AccountActivitySummaryDetailDestination(row: row, author: legacyDetailAuthor, legacyItem: item)
                }
            }.environment(\.soomProfileOnlyDetailPresentation, row.readPolicy == .profileOnlyV2)
                .environment(\.soomFeedPhotoPresentationID, nil)
                .independentFeedReturnScope()
        }
    }
    #if DEBUG && targetEnvironment(simulator)
    private func qaTrace(_ event: String) {
        guard ProcessInfo.processInfo.environment["SOOM_PROJECTION_DEEP_QA"] == "1" else { return }
        ProjectionVerificationProbe.trace("row=\(row.cardID) life=\(qaLifetime) event=\(event) rev=\(revision) safety=\(safety.revision) generation=\(safety.accountGeneration) active=\(active) scene=\(scene == .active) verified=\(verifiedKey == key) cancelled=\(Task.isCancelled)")
    }
    #endif
    private var pendingOwnLocalAllowed: Bool {
        guard let batch = returnBatch else { return false }
        return FeedPendingOwnRecordPolicy.allows(ownerID: sourceRow.ownerID,
            authOwnerID: auth.session.currentUser?.id, viewerID: safety.viewerID,
            storageOwnerID: storage.userID, context: batch.context,
            generation: safety.accountGeneration, safetyRevision: safety.revision,
            returnEpoch: revision, pending: batch.phase == .pending,
            active: active && scene == .active && UIApplication.shared.applicationState == .active,
            socialAllowed: safety.canUseSocial,
            sameContainer: storage.container === modelContext.container,
            retired: AccountDeletionWriteFence.shared.isRetired(sourceRow.ownerID))
    }
    private var pendingOwnWorkout: UnifiedWorkout? {
        guard pendingOwnLocalAllowed else { return nil }
        return Feed61OwnLocalRecordReader.readObserved(record: observedOwnRecords.first, canonicalID: sourceRow.canonicalID, context: modelContext,
            storageContainer: storage.container, ownerID: sourceRow.ownerID,
            authOwnerID: auth.session.currentUser?.id, viewerID: safety.viewerID, storageOwnerID: storage.userID,
            isCurrent: { pendingOwnLocalAllowed }).workout
    }

    /// Only the feed's exact current grant admits this row. Local content has
    /// separate ownership/container/journal checks; a summary is never a local
    /// health or GPS permission. No page-owned health-data cache is introduced.
    private var currentFeedOwnResolution: Feed61OwnLocalRecordReader.Result? {
        guard returnBatch != nil, row.ownerID == safety.viewerID else { return nil }
        guard let authority = linkedAuthority else { return .unavailable }
        return Feed61OwnLocalRecordReader.readObserved(record: observedOwnRecords.first, canonicalID: row.canonicalID, context: modelContext,
            storageContainer: storage.container, ownerID: row.ownerID,
            authOwnerID: auth.session.currentUser?.id, viewerID: safety.viewerID, storageOwnerID: storage.userID,
            isCurrent: { active && scene == .active && safety.canUseSocial &&
                auth.session.currentUser?.id == row.ownerID && safety.viewerID == row.ownerID &&
                storage.userID == row.ownerID && storage.container === modelContext.container &&
                cardGrantIsCurrent?(authority) == true && !AccountDeletionWriteFence.shared.isRetired(row.ownerID) })
    }
    @ViewBuilder private func immediateOwnCard(_ initial: UnifiedWorkout) -> some View {
        WorkoutManagementHost(workout: initial) { current, management in
            // The existing host observes @Query deletion/update. Re-read after
            // that observation too: unchanged timestamps and replaced records
            // must not display the host model's older source snapshot.
            if let live = currentFeedOwnResolution?.workout, let grant = synchronousGrant {
                let photoPresentation: Feed61OwnedPhotoPresentation = grant.photosAvailable ? .authorized(grant.photos) : .unavailable
                let displayed = live == management.workout ? current : live
                OwnedWorkoutRecordCard(workout: displayed, showsManagement: true, enrichRegion: false,
                    ownedPhotoPresentation: photoPresentation,
                    ownedAuthorPresentation: grant.author.map(Feed61OwnedAuthorPresentation.authorized) ?? .unavailable,
                    isAuthorized: { currentFeedOwnResolution?.workout == live },
                    onOpen: { Task { await openImmediateOwnWorkout(requiresLocalRecord: true) } }) {
                    WorkoutManagementButtons(model: management, includesBookmark: false)
                        .disabled(management.workout != live)
                }
                .onChange(of: live, initial: true) { _, latest in
                    if Feed61OwnLocalRecordReader.shouldAdopt(current: management.workout, source: latest, isWorking: management.isWorking) { management.adopt(latest) }
                }
                .onChange(of: management.isWorking) { _, working in
                    if Feed61OwnLocalRecordReader.shouldAdopt(current: management.workout, source: live, isWorking: working) { management.adopt(live) }
                }
            } else {
                AccountActivityWorkoutPlaceholder()
            }
        }
    }
    /// A synchronous presentation must not expose a dead first tap while the
    /// normal row verification task is still queued. Reuse the existing verifier
    /// and detail gate rather than promoting a display receipt into permission.
    @MainActor private func openImmediateOwnWorkout(requiresLocalRecord: Bool) async {
        guard !Task.isCancelled, let authority = linkedAuthority,
              let resolution = currentFeedOwnResolution, resolution.isResolved,
              !requiresLocalRecord || resolution.workout != nil else { return }
        let expectedKey = key, expectedScope = storage.scopeID
        await verify() // A current authorized batch completes without a network suspension.
        guard let current = currentFeedOwnResolution,
              Feed61OwnLocalRecordReader.canOpen(current, requiresLocalRecord: requiresLocalRecord,
                expectedKey: expectedKey, currentKey: key, expectedScope: expectedScope, currentScope: storage.scopeID,
                verified: verifiedKey == key, liveGrantCurrent: cardGrantIsCurrent?(authority) == true,
                cancelled: Task.isCancelled) else { return }
        await openWorkout()
    }
    private var ownCardAccessAllowed: Bool {
        AccountActivityOwnRecordAccess.allowsLocalCard(ownerID: row.ownerID, authOwnerID: auth.session.currentUser?.id,
            journalOwnerID: HealthCloudJournal.accountID(for: modelContext), recordAccessAllowed: ownRecordAccessAllowed)
    }
    private var ownCardLoadKey: String { "\(ownDestinationKey):\(storage.dataRevision):\(revision):\(auth.session.currentUser?.id.uuidString ?? "signed-out")" }
    private var permittedOwnWorkout: UnifiedWorkout? {
        guard ownCardAccessAllowed, ownCardLoadedKey == ownCardLoadKey else { return nil }
        return ownCardWorkout
    }
    @MainActor private func loadOwnCard() async {
        if returnBatch != nil { return }
        guard ownCardAccessAllowed else {
            ownCardWorkout = nil; ownCardLoadedKey = nil; ownCardResolvedKey = nil
            return
        }
        let expected = ownCardLoadKey
        if ownCardResolvedKey == expected { return }
        ownCardWorkout = nil; ownCardLoadedKey = nil; ownCardResolvedKey = nil
        let id = row.canonicalID
        var query = FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 1
        guard let record = try? modelContext.fetch(query).first,
              AccountActivityOwnRecordAccess.matches(canonicalID: id, recordID: record.id) else {
            if !Task.isCancelled, ownCardAccessAllowed, ownCardLoadKey == expected { ownCardResolvedKey = expected }
            return
        }
        let workout = UnifiedWorkoutPersistenceMapper().makeWorkout(from: record)
        guard !Task.isCancelled, ownCardAccessAllowed, ownCardLoadKey == expected else { return }
        ownCardWorkout = workout; ownCardLoadedKey = expected; ownCardResolvedKey = expected
    }
    private var ownDestinationKey: String { "\(row.cardID):\(row.revision):\(safety.accountGeneration):\(storage.scopeID)" }
    private var ownDestinationAllowed: Bool {
        AccountActivityOwnRecordAccess.allows(ownerID: row.ownerID, viewerID: safety.viewerID,
            storageOwnerID: storage.userID, verified: ownDetailKey == ownDestinationKey,
            sameContainer: storage.container === modelContext.container, retired: HealthCloudJournal.isRetired(modelContext))
    }
    private var ownRecordAccessAllowed: Bool {
        AccountActivityOwnRecordAccess.allows(ownerID: row.ownerID, viewerID: safety.viewerID,
            storageOwnerID: storage.userID, verified: verifiedKey == key && active && scene == .active,
            sameContainer: storage.container === modelContext.container,
            retired: HealthCloudJournal.isRetired(modelContext))
    }
    private func ownRecordStillExists(_ id: UUID) -> Bool {
        guard ownDestinationAllowed, id == row.canonicalID else { return false }
        var query = FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 1
        guard let record = try? modelContext.fetch(query).first, !record.isDeleted else { return false }
        return AccountActivityOwnRecordAccess.matches(canonicalID: row.canonicalID, recordID: record.id)
    }
    @MainActor private func openWorkout() async {
        guard verifiedKey == key, active, scene == .active else { return }
        // Never even query local records for somebody else's social card.
        if ownRecordAccessAllowed {
            let canonicalID = row.canonicalID
            let requestKey = key, requestScope = storage.scopeID
            var query = FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.id == canonicalID })
            query.fetchLimit = 1
            if let record = try? modelContext.fetch(query).first, !record.isDeleted,
               AccountActivityOwnRecordAccess.matches(canonicalID: canonicalID, recordID: record.id), requestKey == key, requestScope == storage.scopeID, ownRecordAccessAllowed {
                ownDetailKey = ownDestinationKey; ownDetailScope = requestScope
                ownDetail = UnifiedWorkoutPersistenceMapper().makeWorkout(from: record)
                return
            }
        }
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_PROJECTION_UNLINKED_DETAIL_QA"] == "1" {
            await openLegacy(comments: false); return
        }
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_PROJECTION_LEGACY_NO_DETAIL_QA"] == "1" {
            let post = FeedPostDTO(id: UUID(uuidString: "A9110000-0000-4000-8000-000000000778")!, userId: row.ownerID,
                sport: presentation.sport, title: presentation.title, distanceMeters: row.distanceMeters,
                durationSeconds: row.durationSeconds, createdAt: row.cursor?.activityAt ?? .distantPast)
            legacyDetail = FeedPostBundleDTO(post: post).makeFeedItem(currentUserId: row.ownerID)
            legacyDetailAuthor = author; legacyOpeningGeneration = safety.accountGeneration; return
        }
        #endif
        let batchHasLegacySource = synchronousGrant.map {
            $0.hasBatchCardPreview && $0.socialStatus?.receipt.permits(source: "legacy") == true
        } ?? false
        if legacyAvailable || batchHasLegacySource { await openLegacy(comments: false) }
        else { summaryDetailAuthor = author; summaryOpeningGeneration = safety.accountGeneration; showSummaryDetail = true }
    }
    private var pendingHeight: CGFloat {
        if cardGeometry != nil { return reservedHeight ?? SOOMContentHeightReservation.initialHeight(hasKnownMedia: false) }
        return heightReservation.height(forViewportWidth: viewportWidth, layoutToken: dynamicTypeSize)
            ?? SOOMContentHeightReservation.initialHeight(hasKnownMedia: false)
    }
    private var interactionsAvailable: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_NATIVE_COMMENT_QA"] == "1" { return true }
        #endif
        return (preview && row.readPolicy == .approvedFollowersV1) || row.readPolicy.interactionsProductionReady
    }
    private var presentation: AccountActivityWorkoutCardPresentation { .init(row: row) }
    /// Only an independently authorized historical detail may supply a route.
    /// A summary's canonical ID is never used to read a local/legacy route.
    private var permittedRoute: WorkoutRoute? {
        displayedLinkedPresentation?.route
    }
    private func validatedCard(_ receipt: AccountActivityCardEnvelope, expectedCardID: UUID, requestViewerID: UUID,
        currentViewerID: UUID?, requestGeneration: Int, currentGeneration: Int, latestPermittedDate: Date, expectedOwnerID: UUID) throws -> AccountActivityFeedRow? {
        guard receipt.releaseReady == !preview else { throw AccountActivityContractError.unreleased }
        if preview {
            return try receipt.validateCandidate(expectedCardID: expectedCardID, requestViewerID: requestViewerID,
                currentViewerID: currentViewerID, requestGeneration: requestGeneration, currentGeneration: currentGeneration,
                latestPermittedDate: latestPermittedDate, expectedOwnerID: expectedOwnerID, expectedPolicy: row.readPolicy)
        }
        return try receipt.validateForProduction(expectedCardID: expectedCardID, requestViewerID: requestViewerID,
            currentViewerID: currentViewerID, requestGeneration: requestGeneration, currentGeneration: currentGeneration,
            latestPermittedDate: latestPermittedDate, expectedOwnerID: expectedOwnerID, expectedPolicy: row.readPolicy)
    }
    @MainActor private func openComments() async {
        guard !legacyBusy, verifiedKey == key else { return }
        if usesProfileSocial { showComments = true; return }
        guard row.readPolicy == .profileOnlyV2 else { showComments = true; return }
        guard let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { return }
        let expected = key
        legacyBusy = true; legacyError = nil
        defer { legacyBusy = false }
        let remote = SupabaseFeedRemoteClient(client: client)
        let repository = SupabaseFeedRepository(clientProvider: SupabaseClientProvider(environment: AuthEnvironmentLoader().load()), remoteFetcher: remote, profileFetcher: remote)
        let transport = SupabaseAccountActivityFeedTransport(client: client, legacyRepository: repository, readPolicy: row.readPolicy)
        do {
            let item = try await AccountActivityLinkedLegacyDetailAdapter(transport: transport).loadIfLinked(row: row)
            guard key == expected, verifiedKey == expected, !Task.isCancelled else { return }
            if let item { legacyComments = item } else { showComments = true }
        } catch { if key == expected { legacyError = "댓글을 열지 못했어요. 잠시 후 다시 시도해 주세요." } }
    }
    @MainActor private func openLegacy(comments: Bool) async {
        guard !legacyBusy, verifiedKey == key, row.readPolicy == .profileOnlyV2 else { return }
        let readLinked: () async throws -> FeedItem?
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_PROJECTION_UNLINKED_DETAIL_QA"] == "1" {
            precondition(!AuthEnvironmentLoader().load().isSupabaseConfigured)
            readLinked = { nil } // Transport seam only; actual tap, fences and destination remain production.
        } else {
            guard let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { return }
            let adapter = linkedReader(client)
            readLinked = { try await adapter.loadIfLinked(row: row) }
        }
        #else
        guard let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { return }
        let adapter = linkedReader(client)
        readLinked = { try await adapter.loadIfLinked(row: row) }
        #endif
        let expected = key
        legacyBusy = true; legacyError = nil
        defer { legacyBusy = false }
        do {
            if comments {
                guard let item = try await readLinked() else { throw AccountActivityAdapterError.unlinkedProjection }
                guard key == expected, verifiedKey == expected, !Task.isCancelled else { return }
                legacyComments = item
            } else {
                try await AccountActivityDetailNavigation.perform(
                    loadIfLinked: readLinked,
                    isCurrent: { key == expected && verifiedKey == expected && active && scene == .active },
                    openLegacy: { item in
                        legacyDetailAuthor = author; legacyOpeningGeneration = safety.accountGeneration; legacyDetail = item
                    },
                    openSummary: {
                        summaryDetailAuthor = author; summaryOpeningGeneration = safety.accountGeneration; showSummaryDetail = true
                    })
            }
        } catch { if key == expected { legacyError = "운동 상세를 열지 못했어요. 잠시 후 다시 시도해 주세요." } }
    }
    private var canCheer: Bool {
        if usesProfileSocial {
            return safety.canUseSocial && socialReadRequestID == nil && displayedSocialStatus != nil && !profileSocialPending
        }
        return !preview && safety.canUseSocial && socialReadRequestID == nil && socialLegacyItem.map {
            $0.authorId == row.ownerID && $0.activityProjection == nil && !$0.isLocalDraft && $0.previewLegacyReadContext == nil
        } == true
    }
    private func linkedReader(_ client: SupabaseClient) -> AccountActivityLinkedLegacyDetailAdapter {
        let remote = SupabaseFeedRemoteClient(client: client)
        let repository = SupabaseFeedRepository(clientProvider: SupabaseClientProvider(environment: AuthEnvironmentLoader().load()), remoteFetcher: remote, profileFetcher: remote)
        return AccountActivityLinkedLegacyDetailAdapter(transport: SupabaseAccountActivityFeedTransport(client: client, legacyRepository: repository, readPolicy: row.readPolicy))
    }
    @MainActor private func recoverUnknownSocialPresentation() {
        guard usesProfileSocial, verifiedKey == key, active, scene == .active,
              socialReadRequestID == nil, !cheerBusy, case .unknown? = socialOverride else { return }
        // Eviction/purge is not a confirmed unlike and must not leave an
        // endless spinner. Explicit retry performs a new source-scoped read.
        profileSocialStatus = nil; socialRead.invalidate(); cheerNeedsRefresh = true
        legacyError = "응원 상태를 다시 확인해 주세요."
    }
    @MainActor private func refreshSocial() async {
        guard verifiedKey == key, interactionsAvailable, active, scene == .active,
              !socialRead.isVerified(for: socialKey), !Task.isCancelled else { return }
        let expected = key, requestKey = socialKey, requestID = UUID()
        socialReadRequestID = requestID
        defer { if socialReadRequestID == requestID { socialReadRequestID = nil; recoverUnknownSocialPresentation() } }
        func isCurrent() -> Bool {
            verifiedKey == expected && key == expected && socialReadRequestID == requestID &&
                AccountActivitySocialReadReceipt.accepts(requestKey: requestKey, currentKey: socialKey, cancelled: Task.isCancelled)
        }
        func commit(_ badge: AccountActivityCommentBadge, legacy: FeedItem?) {
            guard isCurrent() else { return }
            commentBadge = badge; socialLegacyItem = legacy
            socialRead.recordSuccess(requestKey: requestKey, currentKey: socialKey, cancelled: Task.isCancelled)
            if cheerNeedsRefresh { cheerNeedsRefresh = false; legacyError = nil }
        }
        if usesProfileSocial {
            guard let adapter = profileSocialAdapter() else { return }
            let authority = linkedAuthority
            let previousOverride = socialOverride
            let batchStatus = socialBatchAppliedKey == requestKey && returnBatch != nil ? profileSocialStatus : nil
            // Valid batch/ready override needs only local journal inspection.
            // Unknown/explicit refresh performs a fresh source-scoped read.
            let reusable: ProfileActivitySocialStatus?
            if socialRefresh == 0 {
                switch previousOverride {
                case .ready(let status)?: reusable = status
                case .unknown?: reusable = nil
                case nil: reusable = batchStatus
                }
            } else { reusable = nil }
            let token = authority.flatMap { a in socialPresentationStore?.begin(a, isCurrent: { cardGrantIsCurrent?(a) == true }) }
            do {
                let status: ProfileActivitySocialStatus
                if let reusable { status = reusable } else { status = try await adapter.status(row: row) }
                let hasPending = !(try adapter.pending(row: row)).isEmpty
                let oldPending = try adapter.hasEarlierPending(row: row, receipt: status.receipt)
                let pending = hasPending || oldPending
                guard isCurrent() else { return }
                if let authority, let token {
                    guard socialPresentationStore?.finish(authority, requestID: token, status: status,
                        isCurrent: { cardGrantIsCurrent?(authority) == true }) == true else { return }
                }
                profileSocialStatus = status; profileSocialPending = pending
                socialRead.recordSuccess(requestKey: requestKey, currentKey: socialKey, cancelled: Task.isCancelled)
                cheerNeedsRefresh = pending; legacyError = nil
            } catch {
                guard isCurrent() else { return }
                if let authority, let token { _ = socialPresentationStore?.finish(authority, requestID: token, status: nil,
                    isCurrent: { cardGrantIsCurrent?(authority) == true }) }
                profileSocialStatus = nil; cheerNeedsRefresh = true
                legacyError = "댓글과 응원 접근을 확인하지 못했어요."
            }
            return
        }
        // Initial legacy metadata was already independently authorized by verify().
        if socialRefresh == 0, let item = socialLegacyItem {
            commit(.init(comments: item.comments), legacy: item); return
        }
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_NATIVE_COMMENT_QA"] == "1" {
            let adapter = AccountActivityInteractionAdapter.localFixture(transport: AccountActivityCommentUIFixture.shared(card: row.cardID), context: {
                .init(viewerID: ReviewDemoMode.userID, generation: safety.accountGeneration,
                    safetyRevision: safety.revision, storageScopeID: ReviewDemoMode.userID.uuidString.lowercased())
            })
            if let badge = try? await AccountActivityCommentBadge.load(adapter: adapter, target: .native(cardID: row.cardID, ownerID: row.ownerID)) {
                commit(badge, legacy: nil)
            }
            return
        }
        #endif
        guard let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
              let viewer = safety.viewerID, client.auth.currentSession?.user.id == viewer else { return }
        do {
            if row.readPolicy == .profileOnlyV2 && socialRefresh > 0 {
                let item = try await linkedReader(client).loadIfLinked(row: row)
                guard isCurrent() else { return }
                if let item { commit(.init(comments: item.comments), legacy: item); return }
            }
            let adapter = AccountActivityInteractionAdapter(transport: SupabaseAccountActivityInteractionTransport(client: client, preview: preview, readPolicy: row.readPolicy), context: {
                .init(viewerID: (safety.canUseSocial || (preview && safety.canUseActivityPreview)) ? client.auth.currentSession?.user.id : nil,
                    generation: safety.accountGeneration, safetyRevision: safety.revision, storageScopeID: storage.scopeID)
            }, preview: preview)
            let badge = try await AccountActivityCommentBadge.load(adapter: adapter, target: .native(cardID: row.cardID, ownerID: row.ownerID))
            commit(badge, legacy: nil)
        } catch {
            guard isCurrent() else { return }
            commentBadge = .init()
            if socialRefresh > 0 { socialLegacyItem = nil }
            if cheerNeedsRefresh { legacyError = "응원 상태를 확인하지 못했어요. 다시 확인해 주세요." }
            // Failure is not a successful receipt; a later appearance may retry.
        }
    }
    @MainActor private func toggleCheer() async {
        if usesProfileSocial { await toggleProfileCheer(); return }
        guard canCheer, !cheerBusy, !legacyBusy, verifiedKey == key,
              let original = socialLegacyItem,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
              client.auth.currentSession?.user.id == safety.viewerID else { return }
        let expected = key, requestSocialKey = socialKey
        cheerBusy = true; legacyError = nil
        defer { cheerBusy = false }
        do {
            let reader = linkedReader(client)
            let current = try await reader.load(row: row)
            guard !Task.isCancelled, key == expected, verifiedKey == expected, socialKey == requestSocialKey, canCheer,
                  current.id == original.id, current.previewLegacyReadContext == nil else { return }
            let desired = !current.viewerHasCheered
            let remote = SupabaseFeedRemoteClient(client: client)
            if desired { try await remote.addReaction(postId: current.id, reactionType: "cheer") }
            else { try await remote.removeReaction(postId: current.id, reactionType: "cheer") }
            let refreshed = try await reader.load(row: row)
            guard !Task.isCancelled, key == expected, verifiedKey == expected, socialKey == requestSocialKey else { return }
            guard refreshed.id == current.id, refreshed.viewerHasCheered == desired else { throw FeedPostManagementError.changeNotConfirmed }
            socialLegacyItem = refreshed; commentBadge = .init(comments: refreshed.comments)
            socialRead.recordSuccess(requestKey: requestSocialKey, currentKey: socialKey, cancelled: Task.isCancelled)
            cheerNeedsRefresh = false
        } catch {
            if !Task.isCancelled, key == expected, verifiedKey == expected, socialKey == requestSocialKey {
                socialLegacyItem = nil; socialRead.invalidate(); cheerNeedsRefresh = true
                legacyError = "응원 결과를 확인하지 못했어요. 저장된 상태를 다시 확인해 주세요."
            }
        }
    }
    @MainActor private func profileSocialAdapter() -> ProfileActivitySocialAdapter? {
        ProfileActivitySocialAdapter.live(row: row, context: {
            .init(viewerID: safety.canUseSocial && active && scene == .active ? safety.viewerID : nil,
                  generation: safety.accountGeneration, safetyRevision: safety.revision, storageScopeID: storage.scopeID)
        })
    }
    @MainActor private func toggleProfileCheer() async {
        guard canCheer, !cheerBusy, verifiedKey == key, let original = displayedSocialStatus,
              let adapter = profileSocialAdapter() else { return }
        let expected = key; cheerBusy = true; legacyError = nil
        let authority = linkedAuthority
        let token = authority.flatMap { a in socialPresentationStore?.begin(a, isCurrent: { cardGrantIsCurrent?(a) == true }) }
        defer { cheerBusy = false; recoverUnknownSocialPresentation() }
        do {
            let current = try await adapter.status(row: row)
            guard current.receipt == original.receipt, expected == key, verifiedKey == expected, !Task.isCancelled else { throw ProfileActivitySocialError.changed }
            try await adapter.setCheer(row: row, receipt: current.receipt, desired: !original.viewer_has_cheered)
            let fresh = try await adapter.status(row: row)
            guard expected == key, verifiedKey == expected, !Task.isCancelled else { return }
            if let authority, let token {
                guard socialPresentationStore?.finish(authority, requestID: token, status: fresh,
                    isCurrent: { cardGrantIsCurrent?(authority) == true }) == true else { return }
            }
            profileSocialStatus = fresh; profileSocialPending = false; cheerNeedsRefresh = false
        } catch {
            guard expected == key, !Task.isCancelled else { return }
            if let authority, let token { _ = socialPresentationStore?.finish(authority, requestID: token, status: nil,
                isCurrent: { cardGrantIsCurrent?(authority) == true }) }
            profileSocialStatus = nil; socialRead.invalidate(); cheerNeedsRefresh = true
            profileSocialPending = (try? adapter.pending(row: row).isEmpty) == false
            legacyError = "응원 결과를 확인하지 못했어요. 기존 요청을 먼저 확인해 주세요."
        }
    }
    @MainActor private func recoverProfileSocial() async {
        guard !cheerBusy, verifiedKey == key, let adapter = profileSocialAdapter() else { return }
        let expected = key; cheerBusy = true
        if let authority = linkedAuthority { _ = socialPresentationStore?.markUnknown(authority,
            isCurrent: { cardGrantIsCurrent?(authority) == true }) }
        defer { cheerBusy = false }
        do {
            if let request = try adapter.pending(row: row).first {
                _ = try await adapter.resolve(row: row, request: request, retryIfAbsent: true)
            }
            guard expected == key, !Task.isCancelled else { return }
            socialRefresh += 1
        } catch {
            if expected == key { legacyError = "기존 요청의 결과를 아직 확인하지 못했어요. 새로운 요청은 보내지 않았어요." }
        }
    }
    /// Summary authorization and legacy detail authorization remain distinct.
    /// Completion (including a confirmed absence) survives lazy reconstruction
    /// only inside the same exact current page/grant context.
    @MainActor private func enrichLegacyDetail() async {
        // v3 supplies card presentation in the live grant itself. A denied or
        // absent preview is final for this grant; do not launch legacy detail.
        if synchronousGrant?.hasBatchCardPreview == true { return }
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_FEED_ENRICHMENT_QA"] == "1" {
            await enrichSyntheticLegacyDetail(); return
        }
        #endif
        guard row.readPolicy == .profileOnlyV2, !preview, verifiedKey == key, active, scene == .active,
              !legacyEnrichmentRead.isVerified(for: key), !Task.isCancelled,
              let date = row.cursor?.activityAt, !ReviewDemoMode.isActive,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
              client.auth.currentSession?.user.id == safety.viewerID else { return }
        let expected = key, requestID = UUID(), requestRow = row
        legacyEnrichmentRequestID = requestID
        defer { if legacyEnrichmentRequestID == requestID { legacyEnrichmentRequestID = nil } }
        do {
            let value: FeedLinkedCardPresentation?
            var independentLegacyItem: FeedItem?
            if let authority = linkedAuthority, let store = linkedCardStore, let fence = cardGrantIsCurrent {
                let reader = linkedReader(client)
                let completion = try await store.load(authority, isCurrent: {
                    fence(authority) && client.auth.currentSession?.user.id == authority.context.viewerID
                }, operation: {
                    try await reader.loadCardPreview(row: requestRow) { postID, opening in
                        try await SupabaseFeedCardPreviewReader(client: client).load(postID: postID,
                            ownerID: requestRow.ownerID, date: date, isCurrent: {
                                fence(authority) && expected == key && active && scene == .active &&
                                client.auth.currentSession?.user.id == opening.viewerID &&
                                safety.accountGeneration == opening.generation && safety.revision == opening.safetyRevision
                            })
                    }
                })
                value = completion.presentation
            } else {
                let item = try await linkedReader(client).loadIfLinked(row: requestRow)
                independentLegacyItem = item
                value = item.map { FeedLinkedCardPresentation(item: $0, date: date) }
            }
            guard expected == key, verifiedKey == expected, legacyEnrichmentRequestID == requestID,
                  !Task.isCancelled, active, scene == .active,
                  client.auth.currentSession?.user.id == safety.viewerID,
                  returnBatch == nil || synchronousGrant != nil else { return }
            linkedPresentation = value; legacyAvailable = value != nil
            if !usesProfileSocial && returnBatch == nil {
                socialLegacyItem = independentLegacyItem; socialRead.invalidate(); socialRefresh += 1
            }
            legacyEnrichmentRead.recordSuccess(requestKey: expected, currentKey: key, cancelled: Task.isCancelled)
        } catch {
            // A failed optional read must not overwrite a successfully rendered
            // title/route with fabricated defaults or mark absence as verified.
        }
    }
    #if DEBUG && targetEnvironment(simulator)
    @MainActor private func enrichSyntheticLegacyDetail() async {
        guard verifiedKey == key, active, scene == .active,
              !legacyEnrichmentRead.isVerified(for: key), let authority = linkedAuthority,
              let store = linkedCardStore, let fence = cardGrantIsCurrent else { return }
        let expected = key, requestID = UUID()
        legacyEnrichmentRequestID = requestID
        defer { if legacyEnrichmentRequestID == requestID { legacyEnrichmentRequestID = nil } }
        do {
            let value = try await store.load(authority, isCurrent: { fence(authority) }) {
                try await Task.sleep(for: .milliseconds(250))
                let points = (0..<20).map { index in WorkoutRouteCoordinate(latitude: 37.5 + Double(index) * 0.0001,
                    longitude: 127.0 + Double(index) * 0.0001) }
                let postID = authority.row.canonicalID
                let metadata = FeedCardPreviewMetadata(id: postID, ownerID: authority.row.ownerID,
                    title: "합성 대회 기록", body: nil,
                    routeSummary: FeedRouteSummaryDTO(routeExists: true, deviceName: "합성 기기", locationName: "합성 장소"),
                    updatedAt: nil, detailRevision: 1)
                let geometry = FeedCardPreviewGeometry(postID: postID, ownerID: authority.row.ownerID, revision: 1,
                    points: points.map { .init(latitude: $0.latitude, longitude: $0.longitude, segment: $0.segmentIndex) })
                return try SupabaseFeedCardPreviewReader.validated(metadata: metadata, geometry: [geometry],
                    postID: postID, ownerID: authority.row.ownerID, date: Date(timeIntervalSince1970: 0)).presentation
            }
            guard !Task.isCancelled, key == expected, verifiedKey == expected,
                  legacyEnrichmentRequestID == requestID, fence(authority) else { return }
            linkedPresentation = value.presentation; legacyAvailable = false
            legacyEnrichmentRead.recordSuccess(requestKey: expected, currentKey: key, cancelled: false)
        } catch { }
    }
    #endif
    @MainActor private func verify() async {
        // A lazy row reappearance is not a new permission epoch.
        if verifiedKey == key, active, scene == .active {
            #if DEBUG && targetEnvironment(simulator)
            qaTrace("reuse")
            #endif
            return
        }
        #if DEBUG && targetEnvironment(simulator)
        qaTrace("verify-start")
        defer { qaTrace("verify-end") }
        #endif
        if summaryOpeningGeneration != safety.accountGeneration { showSummaryDetail = false; summaryDetailAuthor = nil }
        if !ownDestinationAllowed { ownDetail = nil; ownDetailKey = nil; ownDetailScope = nil }
        if legacyOpeningGeneration != safety.accountGeneration { legacyDetail = nil }
        commentBadge = .init(); socialLegacyItem = nil; profileSocialStatus = nil; profileSocialPending = false; socialBatchAppliedKey = nil; showProfileCheers = false; socialRead.invalidate(); socialReadRequestID = nil; cheerNeedsRefresh = false
        legacyEnrichmentRead.invalidate(); legacyEnrichmentRequestID = nil; linkedPresentation = nil
        verifiedKey = nil; unavailable = false; author = nil; showComments = false; photos = []; legacyAvailable = false; legacyError = nil; verifiedLegacyItem = nil; legacyComments = nil
        let expected = key
        guard active, scene == .active, (safety.canUseSocial || (preview && safety.canUseActivityPreview)), let viewer = safety.viewerID else { unavailable = true; return }
        if let access = returnAccess {
            switch access {
            case .pending: return
            case .denied: unavailable = true; return
            case .authorized(let grant):
                guard grant.row == row, key == expected, !Task.isCancelled else { return }
                author = grant.author
                photos = grant.photosAvailable ? grant.photos : []
                if usesProfileSocial {
                    switch socialOverride {
                    case .ready(let status)?: profileSocialStatus = status
                    case .unknown?: profileSocialStatus = nil
                    case nil: profileSocialStatus = grant.socialStatus
                    }
                } else { profileSocialStatus = nil }
                socialBatchAppliedKey = socialKey
                verifiedKey = expected
                return
            }
        }
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_PROJECTION_SUMMARY_QA"] == "1" {
            if ProcessInfo.processInfo.environment["SOOM_PROJECTION_DEEP_QA"] == "1" {
                verificationProbe.begin(row.cardID)
                let milliseconds = Int(ProcessInfo.processInfo.environment["SOOM_PROJECTION_DELAY_MS"] ?? "0") ?? 0
                for stage in 0..<4 {
                    qaTrace("stage-\(stage)-start")
                    if milliseconds > 0 { try? await Task.sleep(for: .milliseconds(milliseconds)) }
                    guard !Task.isCancelled, key == expected else { return }
                    qaTrace("stage-\(stage)-finish")
                }
            }
            if ProcessInfo.processInfo.environment["SOOM_PROJECTION_LOADING_QA"] == "1" {
                verificationProbe.begin(row.cardID)
                if row.cardID.uuidString.hasSuffix("778") || row.cardID.uuidString.hasSuffix("779") {
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled, key == expected else { return }
                }
            }
            author = .init(id: row.ownerID, displayName: "데모 운동 기록", handle: nil)
            if ProcessInfo.processInfo.environment["SOOM_PROFILE_PHOTO_QA"] == "1" {
                photos = (try? await ReviewDemoPhotoStore.shared.seedProfilePhotoFixture(row: row, context:
                    .init(viewerID: viewer, generation: safety.accountGeneration, safetyRevision: safety.revision,
                        storageScopeID: viewer.uuidString.lowercased()))) ?? []
                guard !Task.isCancelled, key == expected else { return }
            } else { photos = ReviewDemoPhotoStore.shared.seedNativeFixture(cardID: row.cardID) }
            verifiedKey = expected; return
        }
        #endif
        guard (!preview || row.readPolicy == .approvedFollowersV1), (preview || row.readPolicy.productionReady),
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(), client.auth.currentSession?.user.id == viewer else { unavailable = true; return }
        struct Params: Encodable { let p_card_id: UUID }
        let generation = safety.accountGeneration
        do {
            if preview {
                guard try await AccountActivityPreviewService(client: client, owner: viewer).capability().enabled else { unavailable = true; return }
            }
            let receipt: AccountActivityCardEnvelope = try await client.rpc(try row.readPolicy.cardRPC(preview: preview), params: Params(p_card_id: row.cardID)).execute().value
            guard !Task.isCancelled, key == expected, client.auth.currentSession?.user.id == viewer else { return }
            let current = try validatedCard(receipt, expectedCardID: row.cardID, requestViewerID: viewer,
                currentViewerID: safety.viewerID, requestGeneration: generation, currentGeneration: safety.accountGeneration,
                latestPermittedDate: Date(), expectedOwnerID: row.ownerID)
            guard current == row else { unavailable = true; return }
            let profiles = try? await SupabaseFeedRemoteClient(client: client).fetchProfiles(ids: [row.ownerID])
            guard !Task.isCancelled, key == expected, client.auth.currentSession?.user.id == viewer else { return }
            let media = try await AccountActivityCardMediaLoader.load(ownerID: row.ownerID,
                linked: { nil
                }, native: {
                    guard row.readPolicy != .profileOnlyV2, row.readPolicy.interactionsProductionReady else { return [] }
                    let reader = AccountActivityInteractionAdapter(transport: SupabaseAccountActivityInteractionTransport(client: client, readPolicy: row.readPolicy), context: {
                        .init(viewerID: safety.canUseSocial ? client.auth.currentSession?.user.id : nil, generation: safety.accountGeneration,
                              safetyRevision: safety.revision, storageScopeID: viewer.uuidString.lowercased())
                    })
                    return try await reader.loadPhotos(.native(cardID: row.cardID, ownerID: row.ownerID)).map {
                        .init(id: $0.id, storagePath: $0.storage_path, nativeCardID: row.cardID)
                    }
                }, isCurrent: { !Task.isCancelled && key == expected && client.auth.currentSession?.user.id == viewer })
            let profilePhotos: [WorkoutPhotoReference]?
            if row.readPolicy == .profileOnlyV2 {
                profilePhotos = try? await AccountActivityProfilePhotoAdapter(client: client, context: {
                    .init(viewerID: safety.canUseSocial && scene == .active ? client.auth.currentSession?.user.id : nil,
                        generation: safety.accountGeneration, safetyRevision: safety.revision,
                        storageScopeID: viewer.uuidString.lowercased())
                }).load(row: row)
                guard !Task.isCancelled, key == expected, client.auth.currentSession?.user.id == viewer else { return }
            } else { profilePhotos = nil }
            photos = row.readPolicy == .profileOnlyV2 ? (profilePhotos ?? []) : media.photos
            verifiedLegacyItem = media.linked; legacyAvailable = media.linked != nil
            if let item = media.linked, let date = row.cursor?.activityAt {
                linkedPresentation = .init(item: item, date: date)
                legacyEnrichmentRead.recordSuccess(requestKey: expected, currentKey: key, cancelled: Task.isCancelled)
            }
            socialLegacyItem = media.linked
            guard !Task.isCancelled, key == expected, client.auth.currentSession?.user.id == viewer else { return }
            if preview {
                guard try await AccountActivityPreviewService(client: client, owner: viewer).capability().enabled else { unavailable = true; return }
            }
            let finalReceipt: AccountActivityCardEnvelope = try await client.rpc(try row.readPolicy.cardRPC(preview: preview), params: Params(p_card_id: row.cardID)).execute().value
            guard !Task.isCancelled, key == expected, client.auth.currentSession?.user.id == viewer else { return }
            let finalRow = try validatedCard(finalReceipt, expectedCardID: row.cardID, requestViewerID: viewer,
                currentViewerID: safety.viewerID, requestGeneration: generation, currentGeneration: safety.accountGeneration,
                latestPermittedDate: Date(), expectedOwnerID: row.ownerID)
            guard finalRow == row else { unavailable = true; return }
            // Author metadata is optional; never invent an identity or profile target.
            author = profiles?.first(where: { $0.id == row.ownerID && !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            verifiedKey = expected
        } catch { if key == expected { unavailable = true } }
    }
}

/// View-local completion receipt only. The full presentation key already
/// contains account, authorization revisions, activity and scene state.
struct AccountActivitySocialReadReceipt: Equatable {
    private(set) var verifiedKey: String?
    func isVerified(for key: String) -> Bool { verifiedKey == key }
    static func accepts(requestKey: String, currentKey: String, cancelled: Bool) -> Bool {
        !cancelled && requestKey == currentKey
    }
    mutating func recordSuccess(requestKey: String, currentKey: String, cancelled: Bool) {
        guard Self.accepts(requestKey: requestKey, currentKey: currentKey, cancelled: cancelled) else { return }
        verifiedKey = requestKey
    }
    mutating func invalidate() { verifiedKey = nil }
}

/// Server timestamps retain the existing 12-hour n/dot behavior. Loading or
/// opening a sheet never resets this window, and no comment bodies are retained.
struct AccountActivityCommentBadge: Equatable {
    private var dates: [Date] = []
    private(set) var isComplete = true
    var count: Int { dates.count }
    init() {}
    init(comments: [FeedComment]) {
        let visible = comments.filter { !$0.isDeleted }
        dates = visible.map(\.createdAt)
    }
    func isRecent(now: Date) -> Bool {
        dates.contains { $0 <= now && now.timeIntervalSince($0) < 12 * 60 * 60 }
    }
    @MainActor static func load(adapter: AccountActivityInteractionAdapter, target: AccountActivityInteractionTarget) async throws -> Self {
        var result = Self(), cursor: AccountActivityCommentCursor?
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        // Comments are oldest-first. Follow the actual cursor rather than
        // mistaking the first page for the entire thread or its newest reply.
        for _ in 0..<5 {
            try Task.checkCancellation()
            let rows = try await adapter.loadComments(target, limit: 100, after: cursor)
            for row in rows where !row.is_deleted {
                guard let date = fractional.date(from: row.created_at) ?? fallback.date(from: row.created_at) else { throw AccountActivityInteractionError.invalidResponse }
                result.dates.append(date)
            }
            guard rows.count == 100, let last = rows.last else { return result }
            // A recent comment already proves the n badge. No exact total is displayed.
            if result.isRecent(now: Date()) { result.isComplete = false; return result }
            cursor = .init(createdAt: last.created_at, id: last.id)
        }
        // Bound background work to 500 rows. A dot remains evidence-based;
        // absence of n is not presented as a complete unread/recency count.
        result.isComplete = false
        return result
    }
}

/// Reuses the existing record-edit menu in the profile-side position. No new
/// photo button and no projection ID is passed to legacy post management.
private struct AccountActivityOwnerEditMenu: View {
    let ownerID: UUID
    @Query private var records: [UnifiedWorkoutRecord]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var storage: HealthAccountStorageController
    init(ownerID: UUID, canonicalID: UUID) {
        self.ownerID = ownerID
        _records = Query(filter: #Predicate<UnifiedWorkoutRecord> { $0.id == canonicalID })
    }
    var body: some View {
        if storage.userID == ownerID, context.container === storage.container,
           !HealthCloudJournal.isRetired(context), let record = records.first {
            WorkoutManagementHost(workout: UnifiedWorkoutPersistenceMapper().makeWorkout(from: record)) { _, model in
                WorkoutManagementButtons(model: model, includesBookmark: false)
            }
        }
    }
}

/// Layout-only mapping of the authorized summary. No detail fetch or invented
/// HR, elevation, device, location, title or photo authority is added here.
struct AccountActivityWorkoutCardPresentation {
    let row: AccountActivityFeedRow
    var sport: UnifiedWorkoutType { UnifiedWorkoutType(rawValue: row.sport) ?? .other }
    var title: String { sport.shareDisplayName + " 기록" }
    var metrics: [WorkoutCardMetric] {
        [WorkoutCardMetric(label: "거리", value: FeedCardFormatting.distance(row.distanceMeters, sport: sport)),
         WorkoutCardMetric(label: FeedCardFormatting.movementLabel(sport),
            value: FeedCardFormatting.movement(sport: sport, distance: row.distanceMeters,
                seconds: Double(row.durationSeconds)) ?? "—"),
         WorkoutCardMetric(label: "총 시간", value: FeedCardFormatting.duration(Double(row.durationSeconds)))]
    }
}

/// The local query gate is deliberately independent of legacy post access.
/// Preserve the existing result precedence without fetching native photos that
/// an independently authorized legacy result would immediately replace.
enum AccountActivityCardMediaLoader {
    @MainActor static func load(ownerID: UUID,
        linked: () async throws -> FeedItem?, native: () async throws -> [WorkoutPhotoReference],
        isCurrent: () -> Bool) async throws -> (linked: FeedItem?, photos: [WorkoutPhotoReference]) {
        guard isCurrent() else { throw CancellationError() }
        let item = try? await linked()
        guard isCurrent() else { throw CancellationError() }
        if let item { return (item, AccountActivityLegacyMedia.photos(from: item, ownerID: ownerID)) }
        let photos = (try? await native()) ?? []
        guard isCurrent() else { throw CancellationError() }
        return (nil, photos)
    }
}

/// Current local record resolution; no retained workout/route payload. Only
/// `missing` may fall back to the independently authorized remote summary.
@MainActor enum Feed61OwnLocalRecordReader {
    enum Result {
        case unavailable
        case missing
        case found(UnifiedWorkout)
        var workout: UnifiedWorkout? { if case .found(let value) = self { return value }; return nil }
        var isResolved: Bool { if case .unavailable = self { return false }; return true }
    }
    static func canOpen(_ result: Result, requiresLocalRecord: Bool,
                        expectedKey: String, currentKey: String, expectedScope: String, currentScope: String,
                        verified: Bool, liveGrantCurrent: Bool, cancelled: Bool) -> Bool {
        !cancelled && verified && liveGrantCurrent && expectedKey == currentKey && expectedScope == currentScope &&
            result.isResolved && (!requiresLocalRecord || result.workout != nil)
    }
    static func shouldAdopt(current: UnifiedWorkout, source: UnifiedWorkout, isWorking: Bool) -> Bool {
        !isWorking && current != source
    }
    static func resolve(canonicalID: UUID, isCurrent: () -> Bool,
                        read: () throws -> UnifiedWorkout?) -> Result {
        guard isCurrent() else { return .unavailable }
        do {
            let value = try read()
            guard isCurrent() else { return .unavailable }
            guard let value else { return .missing }
            guard value.id == canonicalID else { return .unavailable }
            return .found(value)
        } catch { return .unavailable }
    }
    static func readObserved(record: UnifiedWorkoutRecord?, canonicalID: UUID,
                     context: ModelContext, storageContainer: ModelContainer,
                     ownerID: UUID, authOwnerID: UUID?, viewerID: UUID?, storageOwnerID: UUID?,
                     isCurrent: () -> Bool) -> Result {
        func permitted() -> Bool {
            isCurrent() && AccountActivityOwnRecordAccess.allowsLocalCard(ownerID: ownerID,
                authOwnerID: authOwnerID, journalOwnerID: HealthCloudJournal.accountID(for: context),
                recordAccessAllowed: AccountActivityOwnRecordAccess.allows(ownerID: ownerID,
                    viewerID: viewerID, storageOwnerID: storageOwnerID, verified: true,
                    sameContainer: storageContainer === context.container,
                    retired: HealthCloudJournal.isRetired(context)))
        }
        guard permitted() else { return .unavailable }
        guard let record, !record.isDeleted else { return .missing }
        guard record.modelContext?.container === context.container, record.id == canonicalID else { return .unavailable }
        // SwiftData observation tracks the actual fields, not only updatedAt.
        // An edit preserving its timestamp therefore cannot reuse a stale value.
        return resolve(canonicalID: canonicalID, isCurrent: permitted) {
            UnifiedWorkoutPersistenceMapper().makeWorkout(from: record)
        }
    }

    static func read(canonicalID: UUID, context: ModelContext, storageContainer: ModelContainer,
                     ownerID: UUID, authOwnerID: UUID?, viewerID: UUID?, storageOwnerID: UUID?,
                     isCurrent: () -> Bool) -> Result {
        func permitted() -> Bool {
            isCurrent() && AccountActivityOwnRecordAccess.allowsLocalCard(ownerID: ownerID,
                authOwnerID: authOwnerID, journalOwnerID: HealthCloudJournal.accountID(for: context),
                recordAccessAllowed: AccountActivityOwnRecordAccess.allows(ownerID: ownerID,
                    viewerID: viewerID, storageOwnerID: storageOwnerID, verified: true,
                    sameContainer: storageContainer === context.container,
                    retired: HealthCloudJournal.isRetired(context)))
        }
        return resolve(canonicalID: canonicalID, isCurrent: permitted) {
            var query = FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.id == canonicalID })
            query.fetchLimit = 1
            guard let record = try context.fetch(query).first, !record.isDeleted else { return nil }
            return UnifiedWorkoutPersistenceMapper().makeWorkout(from: record)
        }
    }
}

enum FeedPendingOwnRecordPolicy {
    static func allows(ownerID: UUID, authOwnerID: UUID?, viewerID: UUID?, storageOwnerID: UUID?,
                       context: FeedReturnBatchContext, generation: Int, safetyRevision: Int, returnEpoch: Int,
                       pending: Bool, active: Bool, socialAllowed: Bool, sameContainer: Bool, retired: Bool) -> Bool {
        pending && active && socialAllowed && sameContainer && !retired &&
            authOwnerID == ownerID && viewerID == ownerID && storageOwnerID == ownerID &&
            context.matches(viewerID: viewerID, accountGeneration: generation,
                safetyRevision: safetyRevision, returnEpoch: returnEpoch)
    }
}

struct AccountActivityOwnRecordAccess {
    static func allowsLocalCard(ownerID: UUID, authOwnerID: UUID?, journalOwnerID: UUID?, recordAccessAllowed: Bool) -> Bool {
        recordAccessAllowed && authOwnerID == ownerID && journalOwnerID == ownerID
    }
    static func matches(canonicalID: UUID, recordID: UUID?) -> Bool { recordID == canonicalID }
    static func allows(ownerID: UUID, viewerID: UUID?, storageOwnerID: UUID?,
        verified: Bool, sameContainer: Bool, retired: Bool) -> Bool {
        verified && viewerID == ownerID && storageOwnerID == ownerID && sameContainer && !retired
    }
}

/// A presentation of the authorized projection, NOT a legacy feed_posts row.
/// No source lookup, permission flag, fabricated post DTO or management action.
struct AccountActivitySummaryDetailPresentation {
    let row: AccountActivityFeedRow
    let author: FeedProfileDTO?
    var photos: [WorkoutPhotoReference] = []
    var authorizedLegacyPhotoPostID: UUID? = nil
    var sharedRecord: WorkoutDetailSharedRecord {
        let presentation = AccountActivityWorkoutCardPresentation(row: row)
        let date = row.cursor?.activityAt ?? .distantPast
        let model = ShareableWorkoutCardModel(id: row.canonicalID, workoutType: presentation.sport,
            title: presentation.title, distanceText: presentation.metrics[0].value,
            durationText: presentation.metrics[2].value, averagePaceText: presentation.metrics[1].value,
            primaryMessage: "", growthMessage: "", recoveryMessage: "", footerText: "SOOM", visibility: .privateOnly,
            staticRoutePreview: StaticRoutePreview(imageURL: nil, bounds: nil, routeExists: false,
                fallbackStyle: StaticRouteFallbackStyle(workoutType: presentation.sport)))
        let item = FeedItem(id: row.cardID, authorName: author?.displayName ?? "작성자 정보 확인 불가", authorHandle: nil,
            authorId: row.ownerID, avatarPath: author?.avatarPath, activityProjection: row,
            createdAt: date, itemType: .workoutSession, visibility: .privateOnly, cardData: .workoutSession(model),
            sourceWorkoutId: nil, caption: nil, photos: photos.filter { photo in
                if let authority = photo.profileAuthority { return authority.permits(photo, cardID: row.cardID, ownerID: row.ownerID, revision: row.revision) }
                if photo.nativeCardID == row.cardID { return photo.storagePath == WorkoutPhotoPolicy.path(ownerID: row.ownerID, postID: row.cardID, photoID: photo.id) }
                guard photo.nativeCardID == nil, let postID = authorizedLegacyPhotoPostID else { return false }
                return photo.storagePath == WorkoutPhotoPolicy.path(ownerID: row.ownerID, postID: postID, photoID: photo.id)
            }, activityContext: "운동 요약",
            activityDate: date, workoutDistanceMeters: row.distanceMeters, workoutDurationSeconds: Double(row.durationSeconds))
        return WorkoutDetailSharedRecord(item: item)
    }
}

/// The existing detail surface displays only fields independently authorized by
/// the current summary RPC. Missing media and measurements remain absent.
struct AccountActivitySummaryDetailDestination: View {
    let row: AccountActivityFeedRow
    let author: FeedProfileDTO?
    var legacyItem: FeedItem? = nil
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var storage: HealthAccountStorageController
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.scenePhase) private var scene
    @Environment(\.soomFeedRevalidationRevision) private var revision
    @State private var photos: [WorkoutPhotoReference] = []
    @State private var verifiedLegacy: FeedItem?
    @State private var verified: String?
    @State private var failed = false
    @State private var openingGeneration = CommunitySafetyStore.shared.accountGeneration
    private var key: String { "\(row.cardID):\(row.revision):\(safety.accountGeneration):\(safety.revision):\(revision):\(scene == .active)" }
    var body: some View {
        SocialAccessBoundary {
            Group {
                if verified == key, scene == .active, safety.accountGeneration == openingGeneration {
                    if let item = verifiedLegacy, AccountActivityDetailFallbackPolicy.usesLegacyDetail(
                        hasAuthorizedSnapshot: item.permittedSharedDetail != nil, hasExactOwnSource: hasExactOwnSource(item)) {
                        FeedItemDetailDestination(item: item).environment(\.feedLegacyPostDeletionAllowed, false)
                    } else {
                        let shared = AccountActivitySummaryDetailPresentation(row: row, author: author, photos: photos, authorizedLegacyPhotoPostID: verifiedLegacy?.id).sharedRecord
                        WorkoutDeepDetailView(workout: shared.layoutIdentity, sharedRecord: shared)
                            .environment(\.workoutManagement, nil)
                            .accessibilityIdentifier("feed.projection.readonlyDetail")
                    }
                } else if failed {
                    ContentUnavailableView("운동을 표시할 수 없어요", soomIcon: "lock",
                        description: Text("공개 범위가 변경됐거나 기록을 불러오지 못했어요."))
                    Button("다시 시도") { Task { await refresh() } }
                } else {
                    ScrollView { SOOMSkeleton(layout: .detail, label: "운동 공개 범위 확인 중").padding(SOOMLayout.screenPadding) }
                }
            }.task(id: key) { await refresh() }
        }.hidesSOOMTabBar().feedCommentProfileNavigationHost()
    }
    private func hasExactOwnSource(_ item: FeedItem) -> Bool {
        guard item.authorId == row.ownerID, row.ownerID == safety.viewerID, storage.userID == row.ownerID,
              safety.accountGeneration == openingGeneration, storage.container === modelContext.container,
              !HealthCloudJournal.isRetired(modelContext), let id = item.sourceWorkoutId else { return false }
        var query = FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.id == id }); query.fetchLimit = 1
        return (try? modelContext.fetch(query).first?.id) == id
    }
    @MainActor private func refresh() async {
        photos = []; verifiedLegacy = nil; verified = nil; failed = false
        let expected = key
        guard scene == .active, safety.canUseSocial, safety.accountGeneration == openingGeneration,
              let viewer = safety.viewerID else { failed = true; return }
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_PROJECTION_SUMMARY_QA"] == "1" {
            if ProcessInfo.processInfo.environment["SOOM_PROFILE_PHOTO_QA"] == "1" {
                photos = (try? await ReviewDemoPhotoStore.shared.seedProfilePhotoFixture(row: row, context:
                    .init(viewerID: viewer, generation: safety.accountGeneration, safetyRevision: safety.revision,
                        storageScopeID: viewer.uuidString.lowercased()))) ?? []
                guard !Task.isCancelled, expected == key else { return }
            } else { photos = ReviewDemoPhotoStore.shared.seedNativeFixture(cardID: row.cardID) }
            verifiedLegacy = legacyItem
            verified = expected; return
        }
        #endif
        guard row.readPolicy == .profileOnlyV2,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
              client.auth.currentSession?.user.id == viewer else { failed = true; return }
        struct Params: Encodable { let p_card_id: UUID }
        do {
            let receipt: AccountActivityCardEnvelope = try await client.rpc("soom_activity_card_candidate_v2", params: Params(p_card_id: row.cardID)).execute().value
            guard !Task.isCancelled, expected == key, client.auth.currentSession?.user.id == viewer else { return }
            let current = try receipt.validateForProduction(expectedCardID: row.cardID, requestViewerID: viewer,
                currentViewerID: safety.viewerID, requestGeneration: openingGeneration, currentGeneration: safety.accountGeneration,
                latestPermittedDate: Date(), expectedOwnerID: row.ownerID, expectedPolicy: .profileOnlyV2)
            guard current == row else { failed = true; return }
            var linked: FeedItem?
            if let legacyItem {
                let remote = SupabaseFeedRemoteClient(client: client)
                let repository = SupabaseFeedRepository(clientProvider: SupabaseClientProvider(environment: AuthEnvironmentLoader().load()), remoteFetcher: remote, profileFetcher: remote)
                let transport = SupabaseAccountActivityFeedTransport(client: client, legacyRepository: repository, readPolicy: row.readPolicy)
                let fresh = try? await AccountActivityLinkedLegacyDetailAdapter(transport: transport).loadIfLinked(row: row)
                guard !Task.isCancelled, expected == key, client.auth.currentSession?.user.id == viewer else { return }
                if let fresh, fresh.id == legacyItem.id, fresh.authorId == row.ownerID { linked = fresh }
            }
            let profilePhotos = (try? await AccountActivityProfilePhotoAdapter(client: client, context: {
                .init(viewerID: safety.canUseSocial && scene == .active ? client.auth.currentSession?.user.id : nil,
                    generation: safety.accountGeneration, safetyRevision: safety.revision,
                    storageScopeID: viewer.uuidString.lowercased())
            }).load(row: row)) ?? []
            guard !Task.isCancelled, expected == key, client.auth.currentSession?.user.id == viewer else { return }
            let final: AccountActivityCardEnvelope = try await client.rpc("soom_activity_card_candidate_v2", params: Params(p_card_id: row.cardID)).execute().value
            guard !Task.isCancelled, expected == key, client.auth.currentSession?.user.id == viewer else { return }
            let finalRow = try final.validateForProduction(expectedCardID: row.cardID, requestViewerID: viewer,
                currentViewerID: safety.viewerID, requestGeneration: openingGeneration, currentGeneration: safety.accountGeneration,
                latestPermittedDate: Date(), expectedOwnerID: row.ownerID, expectedPolicy: .profileOnlyV2)
            guard finalRow == row else { failed = true; return }
            verifiedLegacy = linked
            photos = profilePhotos
            verified = expected
        } catch { if expected == key { failed = true } }
    }
}

private struct SOOMProfileOnlyDetailPresentationKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var soomProfileOnlyDetailPresentation: Bool {
        get { self[SOOMProfileOnlyDetailPresentationKey.self] }
        set { self[SOOMProfileOnlyDetailPresentationKey.self] = newValue }
    }
}
enum AccountActivityDetailFallbackPolicy {
    static func usesLegacyDetail(hasAuthorizedSnapshot: Bool, hasExactOwnSource: Bool) -> Bool {
        hasAuthorizedSnapshot || hasExactOwnSource
    }
    static func headerVisibility(_ original: FeedPostVisibility?, profileOnlyContext: Bool) -> FeedPostVisibility? {
        profileOnlyContext ? nil : original
    }
}
