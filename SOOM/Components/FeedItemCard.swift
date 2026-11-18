import SwiftData
import SwiftUI
import Supabase

struct FeedItemCard: View {
    let item: FeedItem
    var isOwnPost: Bool = false
    var onToggleCheer: () -> Void = {}
    var onToggleSave: () -> Void = {}
    var onSubmitComment: (String) async throws -> Void = { _ in throw CommunitySafetyError.unavailable }
    var onDeletePost: () -> Void = {}
    var onOpen: (() -> Void)? = nil
    var requiresPublicVisibility = false
    var showsSocialActions = true
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @State private var showingComments = false
    @State private var showingCheers = false
    @State private var opening = false

    var body: some View {
        if item.previewLegacySummary {
            PreviewLegacySummaryCard(item: item)
        } else if let row = item.activityProjection {
            AccountActivitySummaryCard(row: row, localViewerID: safety.viewerID)
        } else if onOpen == nil {
            cardContent.navigationDestination(isPresented: $opening) {
                FeedItemDetailDestination(item: item, onSubmitComment: onSubmitComment)
            }
        } else { cardContent }
    }
    private var cardContent: some View {
        VStack(spacing: 0) {
            if !requiresPublicVisibility, WorkoutRecordEditPolicy.owns(item, viewerID: safety.viewerID), let id = item.sourceWorkoutId {
                OwnedFeedWorkoutCard(item: item, sourceID: id, onOpen: openDetail)
            } else {
                RemoteFeedWorkoutCard(item: item, onOpen: openDetail, requiresPublicVisibility: requiresPublicVisibility)
            }
            if !item.isLocalDraft && showsSocialActions {
                if !visibleCheers.isEmpty {
                    Button { showingCheers = true } label: {
                        HStack(spacing: 10) {
                            HStack(spacing: -8) {
                                ForEach(Array(visibleCheers.prefix(3))) { cheer in
                                    SOOMAvatarView(userID: cheer.authorId, avatarPath: cheer.profile?.avatarPath, size: 28)
                                        .overlay(Circle().stroke(SOOMColor.surface, lineWidth: 2))
                                }
                            }
                            Text("\(visibleCheers.count)명이 화이팅하고 있어요")
                                .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).padding(.horizontal, 16).padding(.top, 8)
                    .accessibilityLabel("화이팅한 사람 \(visibleCheers.count)명 보기")
                }
                HStack {
                    Button(action: onToggleCheer) {
                        Image(soom: item.viewerHasCheered ? "hand.thumbsup.fill" : SOOMIcon.thumbsUp)
                            .font(.system(size: 25)).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .disabled(item.previewLegacyReadContext != nil || !safety.canUseSocial)
                    .accessibilityLabel(item.viewerHasCheered ? "응원 취소" : "응원")
                    .accessibilityAddTraits(item.viewerHasCheered ? [.isSelected] : [])
                    Button { showingComments = true } label: {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Image(soom: SOOMIcon.comment).font(.system(size: 25))
                                .overlay(alignment: .topTrailing) {
                                    if !item.comments.isEmpty {
                                        let isNew = item.hasRecentComment(now: context.date)
                                        Circle().fill(SOOMColor.accent)
                                            .frame(width: isNew ? 15 : 8, height: isNew ? 15 : 8)
                                            .overlay {
                                                if isNew { Text("n").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
                                            }.offset(x: 7, y: -5)
                                    }
                                }
                        }.frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .accessibilityLabel("댓글 \(item.comments.count)개")
                    Button(action: onToggleSave) {
                        Image(soom: item.viewerHasSaved ? SOOMIcon.bookmarkFilled : SOOMIcon.bookmark)
                            .font(.system(size: 24)).frame(maxWidth: .infinity, minHeight: 48)
                    }.accessibilityLabel(item.viewerHasSaved ? "저장 취소" : "기록 저장")
                }.buttonStyle(.plain).foregroundStyle(SOOMColor.ink).padding(.horizontal, 16).padding(.vertical, 10)
            }
            Rectangle().fill(SOOMColor.surfaceMuted).frame(height: 6)
        }
        .background(SOOMColor.surface)
        .padding(.horizontal, -SOOMLayout.screenPadding)
        .sheet(isPresented: $showingComments) {
            FeedCommentsSheet(item: item, onSubmit: onSubmitComment)
        }
        .sheet(isPresented: $showingCheers) { FeedCheersSheet(item: item) }
    }
    private var visibleCheers: [FeedReaction] {
        item.orderedCheers.filter { $0.authorId.map { !safety.isBlocked($0) } ?? false }
    }
    private func openDetail() {
        SOOMHaptics.selection()
        if let onOpen { onOpen() } else { opening = true }
    }
}

private struct OwnedFeedWorkoutCard: View {
    let item: FeedItem
    let onOpen: () -> Void
    @Query private var records: [UnifiedWorkoutRecord]
    @Query private var routes: [PersistedWorkoutRoute]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var storage: HealthAccountStorageController
    @State private var achievements: [WorkoutAchievement] = []
    @State private var relatedRoute: WorkoutRoute?
    @State private var routeProjection = WorkoutCardRouteProjection()
    init(item: FeedItem, sourceID: UUID, onOpen: @escaping () -> Void) {
        self.item = item
        self.onOpen = onOpen
        _records = Query(filter: #Predicate<UnifiedWorkoutRecord> { $0.id == sourceID })
        _routes = Query(filter: #Predicate<PersistedWorkoutRoute> { $0.workoutId == sourceID })
    }
    var body: some View {
        if let record = records.first {
            WorkoutManagementHost(workout: UnifiedWorkoutPersistenceMapper().makeWorkout(from: record)) { workout, management in
                FeedWorkoutArticle(item: item, workout: workout,
                    route: displayedRoute,
                    achievements: achievements, onOpen: onOpen) {
                        WorkoutManagementButtons(model: management, includesBookmark: false)
                    }
                    .task(id: WorkoutCardLoadIdentity(account: auth.accountDeletionTarget, scopeID: storage.scopeID,
                        workoutID: workout.id, workoutUpdatedAt: workout.updatedAt, routeUpdatedAt: routes.first?.updatedAt,
                        dataRevision: storage.dataRevision, routeContent: routes.first.map(WorkoutRouteReadSnapshot.init))) {
                        await loadAchievements(workout)
                    }
                    .task(id: WorkoutCardRegionLoadIdentity(account: auth.accountDeletionTarget, scopeID: storage.scopeID,
                        workoutID: workout.id, routeUpdatedAt: routes.first?.updatedAt, locationName: workout.locationName)) {
                        let expectedScope = storage.scopeID
                        let expectedAccount = auth.accountDeletionTarget
                        _ = await WorkoutRegionEnricher.resolveAndPersist(workoutID: workout.id, context: context,
                            scopeID: expectedScope, isCurrent: {
                                storage.scopeID == expectedScope && storage.container === context.container
                                    && auth.accountDeletionTarget == expectedAccount
                            })
                    }
            }
        } else { RemoteFeedWorkoutCard(item: item, onOpen: onOpen) }
    }
    private func loadAchievements(_ workout: UnifiedWorkout) async {
        let expectedScope = storage.scopeID
        let expectedAccount = auth.accountDeletionTarget
        let loadedRoute = try? await WorkoutTelemetryStore(modelContext: context).resolvedRoute(for: workout)
        guard !Task.isCancelled, storage.scopeID == expectedScope,
              storage.container === context.container, auth.accountDeletionTarget == expectedAccount else { return }
        relatedRoute = loadedRoute
        // The primary route does not wait for optional achievement history.
        let loaded = await WorkoutCardAchievementLoader.load(workout: workout,
            route: loadedRoute ?? displayedRoute, context: context)
        guard !Task.isCancelled, storage.scopeID == expectedScope,
              storage.container === context.container, auth.accountDeletionTarget == expectedAccount else { return }
        achievements = loaded
        relatedRoute = loadedRoute
    }
    private var displayedRoute: WorkoutRoute? {
        let own = routeProjection.route(routes.first, context: context)
        return (relatedRoute?.coordinates.count ?? 0) > (own?.coordinates.count ?? 0) ? relatedRoute : own
    }
}

/// Bind a measured article height to the viewport and text layout, rather than
/// comparing an inset article's width with the outer scroll viewport.
/// Geometry only: no content, media, authority or observable publications.
struct FeedCardGeometryScope: Equatable {
    let viewerID: UUID?
    let generation: Int
    let safetyRevision: Int
}
struct FeedCardGeometryKey: Hashable {
    let cardID: UUID
    let width: CGFloat
    let font: String
    let kind: String
}
@MainActor final class FeedCardGeometryStore {
    private struct Entry { let height: CGFloat; let order: UInt64 }
    private var entries: [FeedCardGeometryKey: Entry] = [:]
    private var scope: FeedCardGeometryScope?
    private var sequence: UInt64 = 0
    let maximumCount: Int
    var count: Int { entries.count }
    init(maximumCount: Int = 256) { self.maximumCount = max(0, maximumCount) }
    func reset(to next: FeedCardGeometryScope) {
        guard scope != next else { return }
        entries.removeAll(); scope = next
    }
    func height(for key: FeedCardGeometryKey, scope expected: FeedCardGeometryScope) -> CGFloat? {
        guard scope == expected, key.width.isFinite, key.width > 0 else { return nil }
        return entries[key]?.height
    }
    @discardableResult func record(_ height: CGFloat, for key: FeedCardGeometryKey,
                                  scope expected: FeedCardGeometryScope) -> Bool {
        guard maximumCount > 0, key.width.isFinite, key.width > 0,
              height.isFinite, height >= 44 else { return false }
        // A verified row can be measured before the host's initial onChange.
        // Initialize once only; an old callback can never reset a newer scope.
        if scope == nil { scope = expected }
        guard scope == expected else { return false }
        if let old = entries[key]?.height, abs(old - height) < 0.5 { return false }
        sequence &+= 1
        entries[key] = Entry(height: height, order: sequence)
        while entries.count > maximumCount, let oldest = entries.min(by: { $0.value.order < $1.value.order })?.key {
            entries[oldest] = nil
        }
        return true
    }
}
private struct FeedCardGeometryStoreKey: EnvironmentKey {
    static let defaultValue: FeedCardGeometryStore? = nil
}
extension EnvironmentValues {
    var soomFeedCardGeometryStore: FeedCardGeometryStore? {
        get { self[FeedCardGeometryStoreKey.self] }
        set { self[FeedCardGeometryStoreKey.self] = newValue }
    }
}

struct SOOMFeedCardLayoutReservation<LayoutToken: Equatable>: Equatable {
    private var measured = SOOMContentHeightReservation()
    private var token: LayoutToken?
    mutating func record(_ size: CGSize, viewportWidth: CGFloat?, layoutToken: LayoutToken) -> Bool {
        let width = viewportWidth ?? size.width
        guard size.width.isFinite, size.width > 0, size.height.isFinite, size.height > 0,
              width.isFinite, width > 0 else { return false }
        let changed = measured.record(CGSize(width: width, height: size.height))
        guard changed || (measured.verifiedSize != nil && token != layoutToken) else { return false }
        token = layoutToken
        return true
    }
    func height(forViewportWidth width: CGFloat?, layoutToken: LayoutToken) -> CGFloat? {
        guard token == layoutToken else { return nil }
        return measured.height(forViewportWidth: width)
    }
}

private struct RemoteFeedWorkoutCard: View {
    let item: FeedItem
    let onOpen: () -> Void
    var requiresPublicVisibility = false
    @Environment(\.soomFeedRevalidationRevision) private var revalidationRevision
    @Environment(\.soomFeedIsActive) private var feedIsActive
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @StateObject private var management: FeedPostManagement
    @Environment(\.soomScrollViewportWidth) private var viewportWidth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var heightReservation = SOOMFeedCardLayoutReservation<DynamicTypeSize>()
    @Environment(\.soomFeedCardGeometryStore) private var cardGeometry
    private var geometryScope: FeedCardGeometryScope {
        .init(viewerID: safety.viewerID, generation: safety.accountGeneration, safetyRevision: safety.revision)
    }
    private var geometryKey: FeedCardGeometryKey? {
        guard let width = viewportWidth, width.isFinite, width > 0 else { return nil }
        return .init(cardID: item.id, width: width, font: String(describing: dynamicTypeSize), kind: "legacy")
    }
    private var reservedHeight: CGFloat? {
        guard let geometryKey else { return nil }
        return cardGeometry?.height(for: geometryKey, scope: geometryScope)
    }
    private struct AppearanceKey: Equatable {
        let revision: Int
        let safetyRevision: Int
        let isActive: Bool
    }
    @State private var verifiedAppearanceKey: AppearanceKey?
    #if DEBUG
    @State private var appearanceEvents: [String] = []
    private func recordAppearanceEvent(_ label: String) {
        guard ProcessInfo.processInfo.environment["SOOM_FEED_SCROLL_READ_QA"] == "1" else { return }
        appearanceEvents = Array((appearanceEvents + [label]).suffix(12))
    }
    #endif
    private var appearanceKey: AppearanceKey {
        AppearanceKey(revision: revalidationRevision, safetyRevision: safety.revision, isActive: feedIsActive)
    }
    init(item: FeedItem, onOpen: @escaping () -> Void, requiresPublicVisibility: Bool = false) {
        self.item = item; self.onOpen = onOpen
        self.requiresPublicVisibility = requiresPublicVisibility
        _management = StateObject(wrappedValue: FeedPostManagement(item: item))
    }
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
            Group {
                if (item.isLocalDraft && !requiresPublicVisibility) || management.canRetainArticle {
                    let value = item.isLocalDraft ? item : management.item
                    FeedWorkoutArticle(item: value, onOpen: onOpen) {
                        EmptyView()
                    }
                    // Keep article/photo state during a short access check,
                    // but expose none of it until this appearance is authorized.
                    .opacity(contentPermitted ? 1 : 0)
                    .allowsHitTesting(contentPermitted)
                    .accessibilityHidden(!contentPermitted)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                        guard contentPermitted else { return }
                        var next = heightReservation
                        if next.record(size, viewportWidth: viewportWidth, layoutToken: dynamicTypeSize) { heightReservation = next }
                        if let geometryKey { cardGeometry?.record(size.height, for: geometryKey, scope: geometryScope) }
                    }
                } else {
                    Color.clear.frame(maxWidth: .infinity, minHeight: pendingHeight)
                }
            }
                if !contentPermitted {
                    if let reservedHeight {
                        AccountActivityPendingCard(minimumHeight: reservedHeight, reservedHeight: reservedHeight,
                            unavailable: !management.isWorking && !management.isCheckingAccess && management.hasLoaded && verifiedAppearanceKey == appearanceKey) {
                                Task { await verifyAppearance() }
                            }
                    } else if management.isWorking || management.isCheckingAccess || !management.hasLoaded || verifiedAppearanceKey != appearanceKey {
                        if management.showsAccessProgress { AccountActivityWorkoutPlaceholder(minimumHeight: pendingHeight, hasKnownMedia: !item.photos.isEmpty || item.recordImageURL != nil ? true : nil) }
                    } else {
                        VStack(spacing: 8) {
                            Text("표시할 수 없는 기록입니다.").font(.subheadline).foregroundStyle(.secondary)
                            Button("다시 시도") { Task { await verifyAppearance() } }.frame(minHeight: 44)
                        }
                    }
                }
            }
            .frame(height: contentPermitted ? nil : reservedHeight)
            .animation(nil, value: contentPermitted)
            if let notice = management.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
        }
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_FEED_SCROLL_READ_QA"] == "1" {
                VStack(alignment: .trailing) {
                    Text("access=\(management.appearanceStatistics.accessReads);full=\(management.appearanceStatistics.fullArticleReads);visible=\(contentPermitted)")
                        .accessibilityIdentifier("feed.reads.\(item.id.uuidString)")
                    Text("events=" + appearanceEvents.joined(separator: ","))
                }.font(.system(size: 8)).allowsHitTesting(false)
            }
        }
        #endif
        .task(id: appearanceKey) {
            #if DEBUG
            recordAppearanceEvent("task:r\(revalidationRevision):a\(feedIsActive):f\(management.appearanceStatistics.fullArticleReads)")
            #endif
            if !feedIsActive { management.invalidateAppearanceVerification(); return }
            await verifyAppearance()
        }
        // Lazy row disappearance is not a new feed visit. The active/safety/
        // revalidation key invalidates on real lifecycle or permission changes.
        .onChange(of: item) { old, value in
            management.adoptIfIdle(value)
            if old.serverPostSnapshot != value.serverPostSnapshot
                || old.sharedDetailContractEnabled != value.sharedDetailContractEnabled
                || old.permittedSharedDetail != value.permittedSharedDetail {
                #if DEBUG
                recordAppearanceEvent("item:r\(revalidationRevision):a\(feedIsActive):f\(management.appearanceStatistics.fullArticleReads)")
                #endif
                verifiedAppearanceKey = nil
                management.invalidateAppearanceVerification()
                Task { await verifyAppearance() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: FeedPostManagement.didChange)) { note in
            if note.userInfo?["postID"] as? UUID == item.id {
                verifiedAppearanceKey = nil
                management.invalidateAppearanceVerification()
                Task { await verifyAppearance() }
            }
        }
    }

    private var contentPermitted: Bool {
        (item.isLocalDraft && !requiresPublicVisibility)
            || (verifiedAppearanceKey == appearanceKey && feedIsActive && management.canDisplayContent
                && (!requiresPublicVisibility || management.item.visibility == .publicFeed))
    }

    @MainActor private func verifyAppearance() async {
        guard !item.isLocalDraft, feedIsActive else { return }
        let key = appearanceKey
        await management.refreshForVisiblePresentation(revalidationRevision: key.revision)
        guard !Task.isCancelled, key == appearanceKey else { return }
        // Mark a finished failed check too, so it shows the existing retry UI.
        verifiedAppearanceKey = key
    }

    private var pendingHeight: CGFloat {
        if cardGeometry != nil {
            return reservedHeight ?? SOOMContentHeightReservation.initialHeight(hasKnownMedia: !item.photos.isEmpty || item.recordImageURL != nil)
        }
        return heightReservation.height(forViewportWidth: viewportWidth, layoutToken: dynamicTypeSize)
            ?? SOOMContentHeightReservation.initialHeight(hasKnownMedia: !item.photos.isEmpty || item.recordImageURL != nil)
    }
}

extension FeedItem {
    var recordTitle: String {
        switch cardData {
        case .workoutSession(let card): return card.title
        case .weeklyProgress(let card): return card.weekLabel
        }
    }
    var recordWorkoutType: UnifiedWorkoutType {
        switch cardData { case .workoutSession(let card): return card.workoutType; case .weeklyProgress: return .other }
    }
    var recordSportIcon: String {
        switch recordWorkoutType {
        case .running: return SOOMIcon.run
        case .cycling: return SOOMIcon.bike
        case .swimming: return SOOMIcon.swim
        case .walking, .hiking: return "figure.walk"
        case .strength: return "dumbbell"
        case .yoga: return "figure.mind.and.body"
        case .other: return SOOMIcon.activity
        }
    }
    var recordSport: String {
        switch cardData { case .workoutSession(let card): return card.workoutType.shareDisplayName; case .weeklyProgress: return "주간 운동" }
    }
    var recordImageURL: URL? {
        if case .workoutSession(let card) = cardData { return card.staticRoutePreview?.imageURL }
        return nil
    }
    var recordMetrics: [WorkoutCardMetric] {
        FeedCardFormatting.metrics(self)
    }
}

struct FeedProfileAvatar: View {
    var body: some View {
        Circle()
            .fill(SOOMColor.surfaceMuted)
            .frame(width: 40, height: 40)
            .overlay {
                Image(soom: SOOMIcon.profile)
                    .font(.system(size: SOOMFont.Size.headline, weight: .regular))
                    .foregroundStyle(SOOMColor.tertiaryInk)
            }
            .overlay {
                Circle()
                    .stroke(SOOMColor.black.opacity(0.06), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

struct FeedReferenceMediaPreview: View {
    let routeStyle: StaticRouteFallbackStyle
    let routeExists: Bool
    let distanceText: String
    let routeLabel: String
    let photos: [FeedPhotoPlaceholder]
    let tint: Color

    var body: some View {
        FeedReferenceRoutePreview(
            routeStyle: routeStyle,
            routeExists: routeExists,
            route: FeedPreviewRouteFactory.route(style: routeStyle, distanceText: distanceText),
            distanceText: distanceText,
            routeLabel: routeLabel,
            photoCount: photos.count,
            tint: tint
        )
        .frame(height: mediaHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(photos.isEmpty ? "지도 경로 미리보기" : "지도 경로 미리보기, 사진 \(photos.count)장")
    }

    private var mediaHeight: CGFloat {
        return 216
    }
}

private enum FeedPreviewRouteFactory {
    static func route(style: StaticRouteFallbackStyle, distanceText: String) -> WorkoutRoute? {
        let points = coordinates(for: style)
        guard points.count >= 2 else { return nil }

        return WorkoutRoute(
            workoutId: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            source: .soomLocal,
            coordinates: points.map {
                WorkoutRouteCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            totalDistanceMeters: distanceMeters(from: distanceText),
            totalElevationGain: nil,
            createdAt: Date(timeIntervalSince1970: 1_800_480_000)
        )
    }

    private static func coordinates(for style: StaticRouteFallbackStyle) -> [(latitude: Double, longitude: Double)] {
        switch style {
        case .cycling:
            return [
                (37.5262, 126.9058),
                (37.5314, 126.9189),
                (37.5226, 126.9384),
                (37.5168, 126.9632),
                (37.5228, 126.9850),
                (37.5350, 127.0048),
                (37.5297, 127.0218)
            ]
        case .running:
            return [
                (37.5209, 127.1218),
                (37.5165, 127.1254),
                (37.5116, 127.1216),
                (37.5128, 127.1134),
                (37.5191, 127.1118),
                (37.5232, 127.1168)
            ]
        case .swimming:
            return [
                (37.5105, 127.0982),
                (37.5107, 127.1006),
                (37.5104, 127.1032),
                (37.5108, 127.1058)
            ]
        case .walking:
            return [
                (37.5794, 126.9769),
                (37.5781, 126.9810),
                (37.5752, 126.9836),
                (37.5728, 126.9802),
                (37.5746, 126.9758)
            ]
        case .generic, .indoor:
            return [
                (37.5446, 127.0373),
                (37.5484, 127.0430),
                (37.5450, 127.0502),
                (37.5389, 127.0460),
                (37.5402, 127.0384)
            ]
        }
    }

    private static func distanceMeters(from text: String) -> Double {
        let normalized = text.lowercased().replacingOccurrences(of: ",", with: "")
        let number = normalized
            .split(whereSeparator: { !$0.isNumber && $0 != "." })
            .first
            .flatMap { Double($0) } ?? 0

        if normalized.contains("km") {
            return number * 1_000
        }

        if normalized.contains("m") {
            return number
        }

        return max(number * 1_000, 1_000)
    }
}

private struct FeedReferenceRoutePreview: View {
    let routeStyle: StaticRouteFallbackStyle
    let routeExists: Bool
    let route: WorkoutRoute?
    let distanceText: String
    let routeLabel: String
    let photoCount: Int
    let tint: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            WorkoutDetailMapView(
                route: route,
                fallbackStyle: routeStyle,
                tint: tint
            )
                .allowsHitTesting(false)

            Text(distanceText)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)
                .padding(.horizontal, SOOMLayout.Spacing.md)
                .padding(.vertical, SOOMLayout.Spacing.sm)
                .background(SOOMColor.white.opacity(0.94))
                .clipShape(Capsule())
                .padding(SOOMLayout.Spacing.md)

            if photoCount > 0 {
                HStack {
                    Spacer()

                    Label(photoCountText, soomIcon: "camera")
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.ink.opacity(0.78))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, SOOMLayout.Spacing.md)
                        .padding(.vertical, SOOMLayout.Spacing.sm)
                        .background(SOOMColor.white.opacity(0.90))
                        .clipShape(Capsule())
                        .padding(SOOMLayout.Spacing.md)
                }
            }

            VStack {
                Spacer()
                HStack {
                    Text(trimmedLabel(routeLabel))
                        .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.ink.opacity(0.82))
                        .lineLimit(1)
                        .padding(.horizontal, SOOMLayout.Spacing.sm)
                        .padding(.vertical, SOOMLayout.Spacing.sm)
                        .background(SOOMColor.white.opacity(0.90))
                        .clipShape(Capsule())

                    Spacer(minLength: 0)
                }
                .padding(SOOMLayout.Spacing.md)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous)
                .stroke(SOOMColor.black.opacity(0.06), lineWidth: 1)
        }
    }

    private var routeBackground: LinearGradient {
        LinearGradient(
            colors: [
                SOOMColor.surfaceAmbient,
                SOOMColor.surfaceMuted.opacity(0.78),
                tint.opacity(0.13)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var routeMapCanvas: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)

            var water = Path()
            water.move(to: CGPoint(x: rect.width * 0.62, y: 0))
            water.addCurve(
                to: CGPoint(x: rect.width, y: rect.height * 0.68),
                control1: CGPoint(x: rect.width * 0.92, y: rect.height * 0.12),
                control2: CGPoint(x: rect.width * 0.78, y: rect.height * 0.48)
            )
            water.addLine(to: CGPoint(x: rect.width, y: 0))
            water.closeSubpath()
            context.fill(water, with: .color(SOOMColor.swim.opacity(0.16)))

            [
                CGRect(x: rect.width * 0.06, y: rect.height * 0.10, width: rect.width * 0.30, height: rect.height * 0.18),
                CGRect(x: rect.width * 0.50, y: rect.height * 0.68, width: rect.width * 0.34, height: rect.height * 0.15)
            ].forEach { park in
                context.fill(Path(roundedRect: park, cornerRadius: 18), with: .color(SOOMColor.green.opacity(0.15)))
            }

            let minorRoads: [(CGPoint, CGPoint)] = [
                (CGPoint(x: 0.00, y: 0.36), CGPoint(x: 0.72, y: 0.18)),
                (CGPoint(x: 0.00, y: 0.56), CGPoint(x: 0.76, y: 0.43)),
                (CGPoint(x: 0.12, y: 0.92), CGPoint(x: 1.00, y: 0.62)),
                (CGPoint(x: 0.25, y: 0.00), CGPoint(x: 0.30, y: 1.00)),
                (CGPoint(x: 0.48, y: 0.00), CGPoint(x: 0.56, y: 0.92))
            ]

            minorRoads.forEach { start, end in
                var road = Path()
                road.move(to: CGPoint(x: rect.width * start.x, y: rect.height * start.y))
                road.addLine(to: CGPoint(x: rect.width * end.x, y: rect.height * end.y))
                context.stroke(road, with: .color(SOOMColor.white.opacity(0.82)), lineWidth: 7)
                context.stroke(road, with: .color(SOOMColor.ink.opacity(0.065)), lineWidth: 2)
            }

            [
                CGRect(x: rect.width * 0.10, y: rect.height * 0.42, width: rect.width * 0.13, height: rect.height * 0.08),
                CGRect(x: rect.width * 0.38, y: rect.height * 0.18, width: rect.width * 0.12, height: rect.height * 0.07),
                CGRect(x: rect.width * 0.62, y: rect.height * 0.48, width: rect.width * 0.14, height: rect.height * 0.09)
            ].forEach { block in
                context.fill(Path(roundedRect: block, cornerRadius: 7), with: .color(SOOMColor.ink.opacity(0.055)))
            }
        }
        .accessibilityHidden(true)
    }

    private func routeEndpoint(isStart: Bool) -> some View {
        GeometryReader { proxy in
            Circle()
                .fill(isStart ? SOOMColor.white : tint)
                .frame(width: 11, height: 11)
                .overlay {
                    Circle()
                        .stroke(tint, lineWidth: 1.7)
                }
                .position(endpointPosition(in: proxy.size, isStart: isStart))
        }
        .accessibilityHidden(true)
    }

    private func endpointPosition(in size: CGSize, isStart: Bool) -> CGPoint {
        if isStart {
            return CGPoint(x: size.width * 0.20, y: size.height * 0.70)
        }

        return CGPoint(x: size.width * 0.81, y: size.height * 0.36)
    }

    private func trimmedLabel(_ value: String) -> String {
        guard value.count > 16 else {
            return value
        }
        return "\(value.prefix(16))..."
    }

    private var photoCountText: String {
        if photoCount == 1 {
            return "사진 1"
        }
        return "사진 \(photoCount)"
    }
}

private struct FeedReferenceRouteLine: Shape {
    let style: StaticRouteFallbackStyle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = normalizedPoints.map { point in
            CGPoint(
                x: rect.minX + rect.width * point.x,
                y: rect.minY + rect.height * point.y
            )
        }

        guard let first = points.first else { return path }
        path.move(to: first)

        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        return path
    }

    private var normalizedPoints: [CGPoint] {
        switch style {
        case .running:
            return [
                CGPoint(x: 0.02, y: 0.72),
                CGPoint(x: 0.17, y: 0.50),
                CGPoint(x: 0.34, y: 0.58),
                CGPoint(x: 0.50, y: 0.30),
                CGPoint(x: 0.66, y: 0.46),
                CGPoint(x: 0.82, y: 0.25),
                CGPoint(x: 0.98, y: 0.38)
            ]
        case .cycling:
            return [
                CGPoint(x: 0.02, y: 0.62),
                CGPoint(x: 0.15, y: 0.42),
                CGPoint(x: 0.33, y: 0.40),
                CGPoint(x: 0.48, y: 0.68),
                CGPoint(x: 0.64, y: 0.56),
                CGPoint(x: 0.78, y: 0.34),
                CGPoint(x: 0.98, y: 0.30)
            ]
        case .swimming:
            return [
                CGPoint(x: 0.03, y: 0.55),
                CGPoint(x: 0.20, y: 0.44),
                CGPoint(x: 0.38, y: 0.57),
                CGPoint(x: 0.56, y: 0.44),
                CGPoint(x: 0.74, y: 0.57),
                CGPoint(x: 0.97, y: 0.46)
            ]
        case .walking:
            return [
                CGPoint(x: 0.02, y: 0.66),
                CGPoint(x: 0.22, y: 0.58),
                CGPoint(x: 0.34, y: 0.43),
                CGPoint(x: 0.54, y: 0.51),
                CGPoint(x: 0.72, y: 0.36),
                CGPoint(x: 0.98, y: 0.42)
            ]
        case .generic, .indoor:
            return [
                CGPoint(x: 0.02, y: 0.60),
                CGPoint(x: 0.22, y: 0.44),
                CGPoint(x: 0.40, y: 0.52),
                CGPoint(x: 0.58, y: 0.38),
                CGPoint(x: 0.78, y: 0.50),
                CGPoint(x: 0.98, y: 0.34)
            ]
        }
    }
}

struct FeedReferenceMetric: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

struct FeedReferenceMetricGrid: View {
    let metrics: [FeedReferenceMetric]

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: metrics.count),
            alignment: .leading,
            spacing: 0
        ) {
            ForEach(metrics) { metric in
                VStack(alignment: .center, spacing: 4) {
                    Text(metric.label)
                        .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                        .lineLimit(1)
                        .frame(height: 12, alignment: .bottom)

                    Text(metric.value)
                        .font(SOOMFont.body(15, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(height: 19, alignment: .top)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, SOOMLayout.Spacing.md)
        .padding(.vertical, SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceMuted.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous)
                .stroke(SOOMColor.black.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct FeedReferenceAction: View {
    let icon: String
    let title: String
    var isProminent = false

    var body: some View {
        Label(title, soomIcon: icon)
            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(isProminent ? SOOMColor.ink : SOOMColor.secondaryInk)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, isProminent ? 10 : 0)
            .frame(minHeight: 28)
            .background {
                if isProminent {
                    Capsule(style: .continuous)
                        .fill(SOOMColor.surfaceMuted)
                }
            }
    }
}

extension UnifiedWorkoutType {
    var feedTint: Color {
        switch self {
        case .running:
            return SOOMColor.run
        case .cycling:
            return SOOMColor.bike
        case .swimming:
            return SOOMColor.swim
        case .walking, .hiking, .strength, .yoga, .other:
            return SOOMColor.green
        }
    }

    var feedShortTitle: String {
        switch self {
        case .running:
            return "러닝"
        case .cycling:
            return "라이딩"
        case .swimming:
            return "수영"
        case .walking:
            return "걷기"
        case .hiking:
            return "하이킹"
        case .strength:
            return "근력"
        case .yoga:
            return "요가"
        case .other:
            return "운동"
        }
    }
}

#Preview("FeedItemCard") {
    SOOMScreen {
        FeedItemCard(item: FeedMockData.items[0])
    }
    .preferredColorScheme(.light)
}

private struct PreviewLegacySummaryCard: View {
    let item: FeedItem
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.scenePhase) private var phase
    @Environment(\.soomFeedRevalidationRevision) private var refreshRevision
    @Environment(\.soomFeedIsActive) private var feedActive
    @State private var verified: FeedItem?
    private var refreshKey: String { "\(item.id):\(safety.accountGeneration):\(safety.revision):\(refreshRevision):\(phase == .active):\(feedActive)" }
    private var readable: Bool {
        guard let receipt = item.previewLegacyReadContext else { return false }
        return feedActive && phase == .active && safety.canUseActivityPreview && safety.viewerID == receipt.viewerID
            && safety.accountGeneration == receipt.generation && safety.revision == receipt.safetyRevision
            && !safety.isBlocked(item.authorId)
    }
    var body: some View {
        SOOMCard {
            if readable, let item = verified {
                Text("공개 운동 요약").font(.headline)
                if case .workoutSession(let card) = item.cardData { Text(card.title).font(.subheadline) }
                if let date = item.activityDate { Text(date, style: .date).font(.caption) }
                if let seconds = item.workoutDurationSeconds { Text("운동 시간 \(Int(seconds / 60))분") }
                if let distance = item.workoutDistanceMeters { Text(String(format: "거리 %.2f km", distance / 1000)) }
                Text("읽기 전용 · 댓글과 응원은 제공하지 않아요.").font(.caption).foregroundStyle(.secondary)
            } else { Text("공개 범위를 다시 확인하고 있어요.").font(.caption) }
        }
        .task(id: refreshKey) { await revalidate() }
    }
    @MainActor private func revalidate() async {
        verified = nil
        guard readable, let receipt = item.previewLegacyReadContext,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { return }
        let key = refreshKey
        let current = try? await SupabaseFeedRemoteClient(client: client).previewLegacySummaryCard(postID: item.id, context: receipt)
        guard !Task.isCancelled, refreshKey == key, readable, current?.id == item.id, current?.authorId == item.authorId else { return }
        verified = current
    }
}
