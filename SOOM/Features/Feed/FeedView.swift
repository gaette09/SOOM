import SwiftUI
import UIKit

struct FeedView: View {
    let audience: FeedAudience
    let onSelectAudience: (FeedAudience) async -> Void
    @Environment(\.soomFeedViewportCards) private var reportViewportCards
    let items: [FeedItem]
    let weeklySnapshot: FeedWeeklySnapshot?
    let recoveryInsight: FeedRecoveryInsight?
    let streak: FeedStreakSnapshot
    let isLoading: Bool
    let loadFailure: FeedLoadFailure?
    let hasMore: Bool
    let paginationRevision: Int
    let paginationWakeRevision: Int
    let paginationIsReady: Bool
    let isLoadingMore: Bool
    let loadMoreFailure: FeedLoadFailure?
    let onRefresh: () async -> Void
    let onLoadMore: () async -> Void
    let onRetryLoadMore: () async -> Void
    let notificationFetcher: (any NotificationInboxFetching)?
    let profileFetcher: (any FeedRemoteProfileFetching)?
    let resolveNotificationPost: (UUID) async -> FeedItem?
    let onRevealNotificationPost: (FeedItem) -> Void
    let onToggleCheer: (FeedItem) -> Void
    let onToggleSave: (FeedItem) -> Void
    let onSubmitComment: (FeedItem, String) async throws -> Void
    let onDeletePost: (FeedItem) -> Void
    let onNavigateToClubs: () -> Void
    let onNavigateToRouteRecommendation: () -> Void
    let onFirstCardDisplay: () -> Void
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.soomFeedIsActive) private var feedIsActive
    @Environment(\.soomFeedRevalidationRevision) private var revalidationRevision
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var sharedSafetyStore = CommunitySafetyStore.shared
    @ObservedObject private var staleSummaryCache = FeedStaleSummaryCache.shared
    @Environment(\.dynamicTypeSize) private var cacheDynamicType
    @Environment(\.locale) private var cacheLocale
    @Environment(\.layoutDirection) private var cacheDirection
    @Environment(\.legibilityWeight) private var cacheWeight
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    @Environment(\.feedChromeTestCache) private var chromeTestCache
    @Environment(\.feedChromeTestSafety) private var chromeTestSafety
    #endif
    private var safetyStore: CommunitySafetyStore {
        #if DEBUG
        chromeTestSafety ?? sharedSafetyStore
        #else
        sharedSafetyStore
        #endif
    }
    private var chromeCache: FeedStaleSummaryCache {
        #if DEBUG
        chromeTestCache ?? staleSummaryCache
        #else
        staleSummaryCache
        #endif
    }

    @State private var measuredChrome: FeedChromeLayout?
    @State private var isFeedScrolling = false
    @State private var scrollMotionGate = FeedScrollMotionGate()
    @State private var hasAppeared = false
    @State private var visibleItems: [FeedItem]
    @State private var isSignInSheetPresented = false
    @State private var isSearchPresented = false
    @State private var isSavedPostsPresented = false
    @State private var isNotificationsInboxPresented = false
    @State private var unreadNotificationCount = 0
    @ObservedObject private var notificationBadge = NotificationBadgeStore.shared
    @State private var isPresentingFeedWorkoutImport = false
    @State private var isManualWorkoutPresented = false
    @State private var selectedItem: FeedItem?
    @State private var visiblePaginationCards: Set<UUID> = []
    @State private var visiblePaginationFooter: Feed60PaginationFooterReceipt?
    @State private var paginationVisibilityRevision = 0
    @State private var prefetchedBoundary: Feed60PaginationPrefetchReceipt?


    init(
        audience: FeedAudience = .all,
        onSelectAudience: @escaping (FeedAudience) async -> Void = { _ in },
        items: [FeedItem] = [],
        weeklySnapshot: FeedWeeklySnapshot? = nil,
        recoveryInsight: FeedRecoveryInsight? = nil,
        streak: FeedStreakSnapshot = FeedStreakSnapshot(weekCount: 0, activityCount: 0),
        isLoading: Bool = false,
        loadFailure: FeedLoadFailure? = nil,
        hasMore: Bool = false,
        paginationRevision: Int = 0,
        paginationWakeRevision: Int = 0,
        paginationIsReady: Bool = true,
        isLoadingMore: Bool = false,
        loadMoreFailure: FeedLoadFailure? = nil,
        onRefresh: @escaping () async -> Void = {},
        onLoadMore: @escaping () async -> Void = {},
        onRetryLoadMore: @escaping () async -> Void = {},
        notificationFetcher: (any NotificationInboxFetching)? = nil,
        profileFetcher: (any FeedRemoteProfileFetching)? = nil,
        resolveNotificationPost: @escaping (UUID) async -> FeedItem? = { _ in nil },
        onRevealNotificationPost: @escaping (FeedItem) -> Void = { _ in },
        onToggleCheer: @escaping (FeedItem) -> Void = { _ in },
        onToggleSave: @escaping (FeedItem) -> Void = { _ in },
        onSubmitComment: @escaping (FeedItem, String) async throws -> Void = { _, _ in throw CommunitySafetyError.unavailable },
        onDeletePost: @escaping (FeedItem) -> Void = { _ in },
        onNavigateToClubs: @escaping () -> Void = {},
        onNavigateToRouteRecommendation: @escaping () -> Void = {},
        onFirstCardDisplay: @escaping () -> Void = {}
    ) {
        self.audience = audience; self.onSelectAudience = onSelectAudience
        self.onFirstCardDisplay = onFirstCardDisplay
        let sortedItems = FeedView.prioritizedItems(items)
        self.items = sortedItems
        self.weeklySnapshot = weeklySnapshot
        self.recoveryInsight = recoveryInsight
        self.streak = streak
        self.isLoading = isLoading
        self.loadFailure = loadFailure
        self.hasMore = hasMore
        self.paginationRevision = paginationRevision
        self.paginationWakeRevision = paginationWakeRevision
        self.paginationIsReady = paginationIsReady
        self.isLoadingMore = isLoadingMore
        self.loadMoreFailure = loadMoreFailure
        self.onRefresh = onRefresh
        self.onLoadMore = onLoadMore
        self.onRetryLoadMore = onRetryLoadMore
        self.notificationFetcher = notificationFetcher
        self.profileFetcher = profileFetcher
        self.resolveNotificationPost = resolveNotificationPost
        self.onRevealNotificationPost = onRevealNotificationPost
        self.onToggleCheer = onToggleCheer
        self.onToggleSave = onToggleSave
        self.onSubmitComment = onSubmitComment
        self.onDeletePost = onDeletePost
        self.onNavigateToClubs = onNavigateToClubs
        self.onNavigateToRouteRecommendation = onNavigateToRouteRecommendation
        _visibleItems = State(initialValue: sortedItems)
    }

    // Cached summaries are display-only. They never populate FeedItem, cursor,
    // detail authorization, social actions, or the current batch receipt.
    private func pendingCachedSummaries(now: Date) -> [FeedStaleSummarySnapshot] {
        guard feedIsActive, scenePhase == .active, safetyStore.canUseSocial,
              let viewer = authViewModel.session.currentUser?.id, viewer == safetyStore.viewerID,
              audience == .home else { return [] }
        let scope = FeedStaleSummaryScope(viewerID: viewer, generation: safetyStore.accountGeneration,
            safetyRevision: safetyStore.revision, policyVersion: 1)
        return Array(staleSummaryCache.allSnapshots(scope: scope, now: now)
            .filter { !safetyStore.isBlocked($0.ownerID) }.prefix(8))
    }

    var body: some View {
        GeometryReader { viewport in
        ScrollViewReader { scrollProxy in
        SOOMScreen(tracksTabBarScroll: feedIsActive, onVisibleScrollTargetIDs: updatePaginationTargetVisibility) {
            let chromeEnvironment = FeedStaleSummaryLayout.environment(locale: cacheLocale.identifier,
                direction: String(describing: cacheDirection), weight: String(describing: cacheWeight))
            let chromeWidth = Double(viewport.size.width)
            let chromeFont = String(describing: cacheDynamicType)
            let reservedChrome = chromeCache.chromeReservation(viewerID: authViewModel.session.currentUser?.id,
                width: chromeWidth, dynamicType: chromeFont, environment: chromeEnvironment)
            FeedChromeSlot(reservedHeight: reservedChrome.map { CGFloat($0.height) }) {
                VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            topHeader.id("feed.notification.top")
            Text("내 운동과 팔로잉")
                .font(SOOMFont.body(14, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .accessibilityIdentifier("feed.home.scope")

            if !authViewModel.session.isSignedIn && !ReviewDemoMode.isActive {
                FeedSignInBanner {
                    isSignInSheetPresented = true
                }
            }

            FeedCompactOverview(snapshot: weeklySnapshot, streak: streak, recovery: recoveryInsight)

            if let loadFailure {
                if visibleItems.isEmpty || loadFailure != .remoteFailed {
                    feedErrorCard(loadFailure)
                } else {
                    Text("새 게시물을 가져오지 못했어요. 아래로 당겨 다시 시도해 주세요.")
                        .font(SOOMFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("feed.refreshNotice")
                }
            }

                }
                .modifier(FeedChromeGeometryProbe(name: "live-chrome-intrinsic"))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    guard let layout = FeedChromeLayout(width: chromeWidth, dynamicType: chromeFont,
                        environment: chromeEnvironment, height: Double(height)) else { return }
                    measuredChrome = layout
                    if !isLoading, loadFailure == nil, !visibleItems.isEmpty {
                        chromeCache.captureChrome(layout, viewerID: authViewModel.session.currentUser?.id)
                    }
                }
            }
            .onChange(of: chromeCache.revision) { _, _ in
                if !isLoading, loadFailure == nil, !visibleItems.isEmpty, let measuredChrome {
                    chromeCache.captureChrome(measuredChrome, viewerID: authViewModel.session.currentUser?.id)
                }
            }
            .onChange(of: isLoading) { _, loading in
                if !loading, loadFailure == nil, !visibleItems.isEmpty, let measuredChrome {
                    chromeCache.captureChrome(measuredChrome, viewerID: authViewModel.session.currentUser?.id)
                }
            }

            VStack(spacing: 18) {
            if visibleItems.isEmpty {
                if isLoading {
                    if staleSummaryCache.enabled {
                        Group {
                            let snapshots = pendingCachedSummaries(now: Date())
                            if snapshots.isEmpty {
                                VStack(spacing: 18) { FeedSkeletonCard(); FeedSkeletonCard() }
                            } else {
                                ForEach(snapshots) { snapshot in
                                    if let height = snapshot.layout?.height(width: Double(viewport.size.width),
                                        dynamicType: String(describing: cacheDynamicType),
                                        environment: FeedStaleSummaryLayout.environment(locale: cacheLocale.identifier,
                                            direction: String(describing: cacheDirection), weight: String(describing: cacheWeight)),
                                        contentRevision: snapshot.layoutRevision) {
                                        FeedStaleSummaryView(snapshot: snapshot)
                                            .frame(height: CGFloat(height), alignment: .top).clipped()
                                            #if DEBUG && targetEnvironment(simulator)
                                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                                staleSummaryCache.recordPresentedHeight(cardID: snapshot.id, height: Double($0))
                                            }
                                            #endif
                                            .padding(.horizontal, -SOOMLayout.screenPadding)
                                    } else { FeedSkeletonCard() }
                                }
                            }
                        }.accessibilityIdentifier("feed.stale.initial")
                    } else {
                        VStack(spacing: 18) { FeedSkeletonCard(); FeedSkeletonCard() }
                    }
                } else if loadFailure == nil {
                    emptyState
                }
            } else {
                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                        feedItemCard(for: item)
                            .onAppear { onFirstCardDisplay() }
                            .feedCardReveal(index: index, isVisible: hasAppeared, reduceMotion: reduceMotion)
                            .accessibilityHint("자세한 운동 흐름으로 이동합니다.")
                            .id(item.id)
                            .accessibilityIdentifier("feed.card.\(item.id)")

                    }

            }
            if let loadMoreFailure {
                Button { Task { await onRetryLoadMore() } } label: {
                    Label("이전 게시물 다시 불러오기", soomIcon: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }.accessibilityHint(loadMoreFailure.message)
            } else if hasMore {
                // Empty filtered pages also have a footer. Each consumed page
                // and displayed boundary needs a fresh visibility observation;
                // the request's own loading flag never changes this identity.
                paginationFooter(receipt: paginationFooterReceipt)
                    .id(paginationFooterReceipt)
            }
            }
            .scrollTargetLayout()
            .modifier(FeedChromeGeometryProbe(name: "live-first-card-group"))
        }
        .environment(\.soomFeedScrollMotionGate, scrollMotionGate)
        .environment(\.soomFeedIsScrolling, isFeedScrolling)
        .onScrollPhaseChange { _, phase in
            let moving = phase != .idle
            scrollMotionGate.isScrolling = moving
            if moving != isFeedScrolling { isFeedScrolling = moving }
            #if DEBUG && targetEnvironment(simulator)
            if Feed68ScrollProbe.enabled {
                Feed68ScrollProbe.scrolling = moving
                Feed71FrameProbe.shared.setScrolling(moving)
                if moving { Feed68ScrollProbe.scrollEvents += 1 }
            }
            #endif
        }
        .overlay(alignment: .topTrailing) {
            #if DEBUG && targetEnvironment(simulator)
            if Feed68ScrollProbe.enabled {
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    Text(Feed68ScrollProbe.label).font(.system(size: 6))
                        .accessibilityIdentifier("feed68.scroll.probe").allowsHitTesting(false)
                }
            }
            #endif
        }
        .coordinateSpace(name: "feed.notification.viewport")
        // One page owner for both actual near-tail visibility and the footer.
        // Never key this task on isLoadingMore: the request sets it itself.
        .onChange(of: paginationNearTail) { _, _ in
            if !isLoadingMore { paginationVisibilityRevision += 1 }
        }
        .onChange(of: paginationFooterIsVisible) { _, _ in
            if !isLoadingMore { paginationVisibilityRevision += 1 }
        }
        .task(id: paginationTaskKey) {
            guard Feed60PaginationPolicy.canRequest(active: feedIsActive, ready: paginationIsReady && paginationDisplayIsCurrent,
                initialLoading: isLoading, pageLoading: isLoadingMore,
                hasMore: hasMore, hasFailure: loadMoreFailure != nil) else { return }
            guard Feed60PaginationPolicy.hasDemand(footerVisible: paginationFooterIsVisible,
                nearTail: paginationNearTail, receipt: paginationPrefetchReceipt,
                previous: prefetchedBoundary) else { return }
            if !paginationFooterIsVisible {
                guard let receipt = paginationPrefetchReceipt else { return }
                // One speculative page per visible tail, including a filtered
                // page with no additions. Only the visible footer drains those.
                prefetchedBoundary = receipt
            }
            await onLoadMore()
        }
        .refreshable {
            await onRefresh()
            await refreshUnreadNotificationCount()
        }
        .toolbar(.hidden, for: .navigationBar)
        .feedCardDestination(selection: $selectedItem, onSubmitComment: onSubmitComment)
        .navigationDestination(isPresented: $isPresentingFeedWorkoutImport) {
            HealthKitWorkoutImportViewContainer()
        }
        .onAppear {
            hasAppeared = true
        }
        .task(id: revalidationRevision) {
            guard feedIsActive else { return }
            await refreshUnreadNotificationCount()
        }
        .onChange(of: items) { oldItems, newItems in
            Task { @MainActor in await Task.yield(); onFirstCardDisplay() }
            visibleItems = Self.prioritizedItems(safetyStore.filtered(newItems))
        }
        .onChange(of: safetyStore.accountGeneration) { _, _ in
            visibleItems = []
            visiblePaginationCards = []
            visiblePaginationFooter = nil
            prefetchedBoundary = nil
            isSavedPostsPresented = false
            isNotificationsInboxPresented = false
            unreadNotificationCount = 0
        }
        .onChange(of: safetyStore.revision) { _, _ in
            visibleItems = audience != .all ? [] : Self.prioritizedItems(safetyStore.filtered(visibleItems).filter {
                $0.isLocalDraft || $0.authorId == safetyStore.viewerID || $0.visibility == .publicFeed
            })
            isSearchPresented = false
        }
        .onChange(of: authViewModel.session.isSignedIn) { _, isSignedIn in
            if isSignedIn {
                isSignInSheetPresented = false
            }
        }
        .feedCommentProfileNavigationHost()
        .suspendsSOOMTabBarScrollMotion(when: isSignInSheetPresented || isManualWorkoutPresented || isSearchPresented || isSavedPostsPresented || isNotificationsInboxPresented)
        .sheet(isPresented: $isSignInSheetPresented) {
            signInSheet
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isManualWorkoutPresented, onDismiss: { Task { await onRefresh() } }) {
            ManualWorkoutEntryView()
        }
        .navigationDestination(isPresented: $isSearchPresented) {
            FeedSearchSheet(items: visibleItems, onToggleCheer: onToggleCheer, onToggleSave: onToggleSave,
                onSubmitComment: onSubmitComment, onDeletePost: onDeletePost)
        }
        .navigationDestination(isPresented: $isSavedPostsPresented) {
            WorkoutBookmarksView()
        }
        .navigationDestination(isPresented: $isNotificationsInboxPresented) {
            NotificationInboxView(
                fetcher: notificationFetcher,
                profileFetcher: profileFetcher,
                onSelectPost: { _, _ in },
                onMarkedAllRead: { Task { await refreshUnreadNotificationCount() } },
                standaloneNavigation: false,
                postDestination: { request in
                    AnyView(FeedNotificationCardLoader(request:request, resolve:resolveNotificationPost,
                        onSubmitComment:onSubmitComment, onToggleCheer:onToggleCheer,
                        onToggleSave:onToggleSave,onDeletePost:onDeletePost).id(request.id))
                }
            )
        }
        .onChange(of: selectedItem?.id) { oldID, newID in
            guard let oldID, newID == nil else { return }
            scrollProxy.scrollTo(oldID, anchor: .center)
        }
        }
        }
    }

    private func updatePaginationTargetVisibility(_ visibleIDs: [UUID]) {
        reportViewportCards?(Set(visibleIDs).intersection(Set(visibleItems.map(\.id))))
        // One outer-scroll observation replaces per-card lifetime modifiers.
        // Only the current tail can produce a state mutation (at most two IDs).
        if let updated = Feed60PaginationPolicy.targetVisibilityUpdate(visibleIDs: visibleIDs,
            itemIDs: visibleItems.map(\.id), hasMore: hasMore, current: visiblePaginationCards) {
            visiblePaginationCards = updated
        }
    }

    private var paginationDisplayIsCurrent: Bool {
        Feed60PaginationPolicy.displayIsCurrent(sourceIDs: Self.prioritizedItems(safetyStore.filtered(items)).map(\.id),
            displayedIDs: visibleItems.map(\.id))
    }

    private var paginationFooterReceipt: Feed60PaginationFooterReceipt {
        .init(boundaryID: visibleItems.last?.id, pageRevision: paginationRevision)
    }

    private var paginationFooterIsVisible: Bool {
        Feed60PaginationPolicy.footerIsCurrent(visible: visiblePaginationFooter,
            current: paginationFooterReceipt, displayIsCurrent: paginationDisplayIsCurrent)
    }

    private func paginationFooter(receipt: Feed60PaginationFooterReceipt) -> some View {
        Color.clear.frame(height: 48)
            .overlay { if isLoadingMore { ProgressView().accessibilityLabel("이전 게시물 불러오는 중") } }
            .accessibilityIdentifier("feed.nextPageBoundary")
            .onScrollVisibilityChange(threshold: 0.1) { visible in
                if visible { visiblePaginationFooter = receipt }
                else if visiblePaginationFooter == receipt { visiblePaginationFooter = nil }
            }
            .onDisappear {
                // A retiring footer must not clear a newer footer's report.
                if visiblePaginationFooter == receipt { visiblePaginationFooter = nil }
            }
    }

    private var paginationNearTail: Bool {
        Feed60PaginationPolicy.isNearTail(itemIDs: visibleItems.map(\.id), visibleIDs: visiblePaginationCards)
    }

    private var paginationPrefetchReceipt: Feed60PaginationPrefetchReceipt? {
        visibleItems.last.map { .init(boundaryID: $0.id, accountGeneration: safetyStore.accountGeneration,
            safetyRevision: safetyStore.revision, returnEpoch: revalidationRevision, wakeRevision: paginationWakeRevision) }
    }

    private var paginationTaskKey: Feed60PaginationTaskKey {
        .init(pageRevision: paginationRevision, wakeRevision: paginationWakeRevision,
            accountGeneration: safetyStore.accountGeneration, safetyRevision: safetyStore.revision,
            returnEpoch: revalidationRevision, boundaryID: visibleItems.last?.id,
            active: feedIsActive, ready: paginationIsReady && paginationDisplayIsCurrent, initialLoading: isLoading,
            hasMore: hasMore, hasFailure: loadMoreFailure != nil,
            visibilityRevision: paginationVisibilityRevision)
    }

    private var displayedUnreadCount: Int {
        ReviewDemoMode.isActive ? unreadNotificationCount : (notificationBadge.count ?? 0)
    }

    private func refreshUnreadNotificationCount() async {
        if !ReviewDemoMode.isActive {
            await notificationBadge.refresh()
            return
        }
        let safety=CommunitySafetyStore.shared,generation=CommunitySafetyStore.shared.accountGeneration,revision=CommunitySafetyStore.shared.revision
        guard safety.canUseSocial,let owner=safety.viewerID,let notifications=try? await notificationFetcher?.fetchNotifications() else { return }
        guard !Task.isCancelled,safety.canUseSocial,safety.viewerID==owner,safety.accountGeneration==generation,safety.revision==revision else { return }
        unreadNotificationCount=notifications.filter { $0.readAt == nil }.count
    }

    private var signInSheet: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Spacing.lg) {
            AppleAuthCard(authViewModel: authViewModel)
            Spacer()
        }
        .padding(SOOMLayout.Spacing.xl)
    }

    private var topHeader: some View {
        HStack(spacing: 12) {
            Menu {
                Button { isManualWorkoutPresented = true } label: { Label("운동 직접 입력", soomIcon: SOOMIcon.edit) }
                Button { isPresentingFeedWorkoutImport = true } label: { Label("운동 파일 가져오기", soomIcon: SOOMIcon.package) }
            } label: {
                Image(soom: "plus").font(.system(size: 24)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("운동 추가")

            VStack(alignment: .leading, spacing: 1) {
                Image("SOOMWordmarkBlack")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 18, alignment: .leading)
                    .accessibilityLabel("SOOM")
                Text("운동 피드")
                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.tertiaryInk)
            }

            Spacer()

            headerIconButton(icon: "magnifyingglass", label: "검색") {
                isSearchPresented = true
            }
            headerIconButton(icon: "bookmark", label: "저장한 기록") {
                isSavedPostsPresented = true
            }
            headerIconButton(icon: "bell", label: "알림") {
                isNotificationsInboxPresented = true
            }
            .soomBadge(count: displayedUnreadCount)
            .accessibilityValue(displayedUnreadCount > 0 ? "안읽음 \(displayedUnreadCount)개" : "")
        }
        .padding(.bottom, -4)
    }

    private func headerIconButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(soom: icon)
                .font(.system(size: SOOMFont.Size.headline, weight: .semibold))
                .foregroundStyle(SOOMColor.ink)
                .frame(width: 38, height: 38)
                .background(SOOMColor.surfaceMuted)
                .clipShape(Circle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var aiDiscoveryCard: some View {
        HStack(spacing: 10) {
            Image(soom: SOOMIcon.sparkles)
                .font(.system(size: SOOMFont.Size.subheadline, weight: .semibold))
                .foregroundStyle(SOOMColor.accent)
                .frame(width: 28, height: 28)
                .background(SOOMColor.accentMuted)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("발견")
                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.tertiaryInk)
                Text("오늘은 가볍게 다시 탈 만한 코스가 많이 보입니다.")
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer()
        }
        .padding(.horizontal, SOOMLayout.Spacing.lg)
        .padding(.vertical, SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceAmbient.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func feedItemCard(for item: FeedItem) -> some View {
        FeedItemCard(
            item: item,
            isOwnPost: item.isLocalDraft || item.authorId == authViewModel.session.currentUser?.id,
            onToggleCheer: { onToggleCheer(item) },
            onToggleSave: { onToggleSave(item) },
            onSubmitComment: { body in try await onSubmitComment(item, body) },
            onDeletePost: { onDeletePost(item) },
            onOpen: { selectedItem = item }
        )
    }

    private func feedErrorCard(_ failure: FeedLoadFailure) -> some View {
        SOOMCard {
            SOOMSectionHeader(failure.title, caption: failure.message)
            Button {
                if failure == .signInRequired { isSignInSheetPresented = true }
                else { Task { await onRefresh() } }
            } label: {
                Label(failure == .signInRequired ? "로그인" : "다시 불러오기",
                      soomIcon: failure == .signInRequired ? "person.crop.circle" : "arrow.clockwise")
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    .frame(minHeight: 44)
            }
            .disabled(isLoading)
            .accessibilityIdentifier(failure == .signInRequired ? "feed.signInRequired" : "feed.retry")
        }
        .accessibilityIdentifier("feed.loadError")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            SOOMFirstJourneyCard(
                prompt: .feed,
                actions: [
                    SOOMFirstJourneyAction(
                        title: "첫 운동 가져오기",
                        subtitle: "Health 앱의 최근 움직임을 SOOM의 이야기로 이어봅니다.",
                        iconName: SOOMIcon.sync,
                        action: {
                            isPresentingFeedWorkoutImport = true
                        }
                    ),
                    SOOMFirstJourneyAction(
                        title: "추천 코스 보기",
                        subtitle: "오늘은 짧고 편하게 시작할 수 있는 route를 먼저 둡니다.",
                        iconName: SOOMIcon.map,
                        action: onNavigateToRouteRecommendation
                    ),
                    SOOMFirstJourneyAction(
                        title: "천천히 맞는 클럽 찾기",
                        subtitle: "속도보다 분위기가 맞는 사람들을 만나는 입구입니다.",
                        iconName: SOOMIcon.clubs,
                        action: onNavigateToClubs
                    )
                ],
                footer: "피드는 기록이 쌓일수록 점수판보다 하루의 흐름처럼 읽히게 됩니다."
            )

            FeedFirstJourneyStoryPreview()
        }
        .accessibilityElement(children: .contain)
    }

    private static func prioritizedItems(_ items: [FeedItem]) -> [FeedItem] {
        items.sorted(by: FeedDisplayOrder.newestFirst)
    }

}

struct FeedSkeletonCard: View {
    var body: some View { SOOMSkeleton(layout: .feed, label: "운동 카드 불러오는 중") }
}

/// Filters the already-loaded feed pages client-side — no server-side search
/// exists yet, so this only searches items the feed already has in
/// memory (see soom-launch-blockers scoping: a real search API over all
/// posts was explicitly deferred).
private struct FeedSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedItem: FeedItem?
    let items: [FeedItem]
    let onToggleCheer: (FeedItem) -> Void
    let onToggleSave: (FeedItem) -> Void
    let onSubmitComment: (FeedItem, String) async throws -> Void
    let onDeletePost: (FeedItem) -> Void

    private var results: [FeedItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return items.filter {
            $0.authorName.localizedCaseInsensitiveContains(trimmed)
                || $0.recordTitle.localizedCaseInsensitiveContains(trimmed)
                || $0.activityContext.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        Group {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
                    SOOMCard {
                        SOOMSectionHeader("게시물 · 불러온 피드", caption: "이미 불러온 게시물의 작성자·제목·운동 정보를 검색해요. 모든 과거 게시물을 검색하는 기능은 아니에요.")
                            .accessibilityIdentifier("feed.search.scope")
                        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("일치하는 게시물 \(results.count)개")
                                .font(SOOMFont.body(14, relativeTo: .subheadline))
                        }
                    }
                    SOOMCard {
                        NavigationLink { ProfileSearchView() } label: {
                            SOOMActionRow(icon: "person.crop.circle", title: "전체 사용자 검색",
                                subtitle: "게시물 검색과 별도로 이름 또는 사용자 이름을 찾아요.", tint: SOOMColor.accent)
                        }.frame(minHeight: 44).accessibilityIdentifier("profile.search.open")
                    }
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("작성자나 제목으로 검색해보세요.").font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                    } else if results.isEmpty {
                        Text("불러온 피드 안에서 일치하는 게시물을 찾지 못했어요.").font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                    } else {
                        ForEach(results) { item in
                            FeedItemCard(item: item,
                                onToggleCheer: { onToggleCheer(item) },
                                onToggleSave: { onToggleSave(item) },
                                onSubmitComment: { try await onSubmitComment(item, $0) },
                                onDeletePost: { onDeletePost(item) },
                                onOpen: { selectedItem = item })
                        }
                    }
                }.padding(SOOMLayout.screenPadding)
            }
            .feedCardDestination(selection: $selectedItem, onSubmitComment: onSubmitComment)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "불러온 피드의 작성자 또는 제목")
            .navigationTitle("검색")
            .feedCommentProfileNavigationHost()
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct FeedCoachAccessBanner: View {
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(SOOMColor.accentMuted)

                Image(soom: SOOMIcon.sparkles)
                    .font(.system(size: SOOMFont.Size.body, weight: .semibold))
                    .foregroundStyle(SOOMColor.accent)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("가볍게 확인")
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)
                    .lineLimit(1)

                Text("회복 코치는 오른쪽 아래에서 필요할 때 열 수 있어요.")
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(soom: SOOMIcon.close)
                    .font(.system(size: SOOMFont.Size.caption, weight: .bold))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .frame(width: 32, height: 32)
                    .background(SOOMColor.surfaceMuted)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("회복 코치 안내 닫기")
        }
        .padding(.horizontal, SOOMLayout.Spacing.lg)
        .padding(.vertical, SOOMLayout.Spacing.md)
        .background(SOOMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: SOOMColor.black.opacity(0.03), radius: 10, x: 0, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("가볍게 확인")
        .accessibilityValue("회복 코치는 오른쪽 아래에서 필요할 때 열 수 있어요.")
    }
}

private struct FeedFirstJourneyStoryPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                SOOMColor.bike.opacity(0.13),
                                SOOMColor.recovery.opacity(0.08),
                                SOOMColor.surfaceMuted
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 168)
                    .overlay {
                        FirstJourneyRouteLine()
                            .stroke(SOOMColor.bike.opacity(0.64), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                            .padding(.horizontal, 30)
                            .padding(.vertical, 38)
                    }
                    .overlay(alignment: .topTrailing) {
                        Text("예시 route")
                            .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                            .foregroundStyle(SOOMColor.tertiaryInk)
                            .padding(.horizontal, SOOMLayout.Spacing.sm)
                            .padding(.vertical, SOOMLayout.Spacing.sm)
                            .background(SOOMColor.surface.opacity(0.72))
                            .clipShape(Capsule())
                            .padding(SOOMLayout.Spacing.md)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("첫 움직임이 기록되면")
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                    Text("오늘의 길과 호흡이 한 장의 이야기로 남아요.")
                        .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(SOOMLayout.Spacing.lg)
            }

            HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                Label("강변 35분", soomIcon: SOOMIcon.map)
                Label("무리 없는 시작", soomIcon: SOOMIcon.recovery)
            }
            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(SOOMColor.secondaryInk)
            .padding(.horizontal, SOOMLayout.Card.padding)
            .padding(.vertical, SOOMLayout.Spacing.md)
        }
        .background(SOOMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.56), lineWidth: SOOMLayout.Card.borderWidth)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("첫 피드 예시")
        .accessibilityValue("첫 움직임이 기록되면 오늘의 길과 호흡이 한 장의 이야기로 남아요.")
    }
}

private struct FirstJourneyRouteLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.midY + rect.height * 0.26))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.midY - rect.height * 0.18),
            control1: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.midY - rect.height * 0.08),
            control2: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.midY - rect.height * 0.28)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.midY + rect.height * 0.06),
            control1: CGPoint(x: rect.minX + rect.width * 0.52, y: rect.midY - rect.height * 0.08),
            control2: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.midY + rect.height * 0.2)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.midY - rect.height * 0.22),
            control1: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.midY - rect.height * 0.02),
            control2: CGPoint(x: rect.minX + rect.width * 0.86, y: rect.midY - rect.height * 0.22)
        )
        return path
    }
}

private struct FeedSurfaceButton: View {
    let kind: String
    let icon: String
    let title: String
    let subtitle: String
    let footer: String
    let tint: Color

    var body: some View {
        Button {
            SOOMHaptics.selection()
        } label: {
            FeedSurfaceCard(
                kind: kind,
                icon: icon,
                title: title,
                subtitle: subtitle,
                footer: footer,
                tint: tint
            )
        }
        .buttonStyle(FeedCardButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

private struct FeedSurfaceCard: View {
    let kind: String
    let icon: String
    let title: String
    let subtitle: String
    let footer: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind)
                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(tint.opacity(0.52))
                    .padding(.horizontal, SOOMLayout.Spacing.sm)
                    .padding(.vertical, SOOMLayout.Spacing.xs)
                    .background(tint.opacity(0.035))
                    .clipShape(Capsule())

                Spacer(minLength: 6)

                Image(soom: icon)
                    .font(.system(size: SOOMFont.Size.subheadline, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.42))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.ink.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(subtitle)
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk.opacity(0.66))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Text(footer)
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.tertiaryInk.opacity(0.70))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: SOOMLayout.Feed.surfaceCardMinHeight, alignment: .topLeading)
        .padding(SOOMLayout.Card.padding)
        .background(SOOMColor.surfaceAmbient.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.07), lineWidth: SOOMLayout.Card.borderWidth)
        }
    }
}

private struct FeedCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(reduceMotion ? nil : SOOMMotion.cardPress, value: configuration.isPressed)
    }
}

#Preview("FeedView") {
    NavigationStack {
        FeedView(items: FeedMockData.items)
    }
    .preferredColorScheme(.light)
}

private extension View {
    func feedCardReveal(index: Int, isVisible: Bool, reduceMotion: Bool) -> some View {
        opacity(isVisible ? SOOMMotion.Opacity.visible : SOOMMotion.Opacity.hidden)
            .offset(y: reduceMotion || isVisible ? 0 : SOOMMotion.Offset.cardRevealY)
            .animation(
                reduceMotion
                    ? nil
                    : SOOMMotion.normalEaseOut.delay(Double(index) * 0.025),
                value: isVisible
            )
    }
}

/// A notification landing card is not inserted into the home feed. Full workout
/// detail stays a separate tap, so a summary-authorized post remains visible even
/// when its owner has not shared HR/GPS detail.
struct FeedNotificationCardDestination: View {
    @State private var presentation: FeedNotificationCardPresentation
    let onSubmitComment: (FeedItem, String) async throws -> Void
    let onToggleCheer: (FeedItem) -> Void
    let onToggleSave: (FeedItem) -> Void
    let onDeletePost: (FeedItem) -> Void
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.scenePhase) private var scene
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDetail: FeedItem?
    init(item: FeedItem, context: AccountActivityReadContext, opensComments: Bool,
         onSubmitComment: @escaping (FeedItem, String) async throws -> Void,
         onToggleCheer: @escaping (FeedItem) -> Void,
         onToggleSave: @escaping (FeedItem) -> Void,
         onDeletePost: @escaping (FeedItem) -> Void) {
        _presentation = State(initialValue: .init(item:item, context:context, opensComments:opensComments))
        self.onSubmitComment=onSubmitComment; self.onToggleCheer=onToggleCheer
        self.onToggleSave=onToggleSave; self.onDeletePost=onDeletePost
    }
    private var currentContext: AccountActivityReadContext? {
        guard safety.canUseSocial || safety.canUseActivityPreview, let viewer=safety.viewerID else { return nil }
        return .init(viewerID:viewer,generation:safety.accountGeneration,safetyRevision:safety.revision)
    }
    var body: some View {
        SocialAccessBoundary(allowActivityPreview:true) {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                if presentation.permits(currentContext), !safety.isBlocked(presentation.item.authorId), scene != .background {
                    let item=presentation.item
                    FeedItemCard(item:item, isOwnPost:item.authorId==safety.viewerID,
                        onToggleCheer:{ onToggleCheer(item) }, onToggleSave:{ onToggleSave(item) },
                        onSubmitComment:{ try await onSubmitComment(item,$0) },
                        onDeletePost:{ onDeletePost(item); dismiss() },
                        onOpen:{ selectedDetail=item },showsSocialActions:false)
                        .environment(\.soomFeedIsActive,true)
                        .padding(SOOMLayout.screenPadding)
                        .accessibilityIdentifier("feed.notification.card.\(item.id)")
                    if safety.canUseSocial && presentation.supportsLegacyComments {
                        Button("댓글 보기") { presentation.commentsPresented=true }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SOOMColor.accent)
                            .frame(minHeight:44)
                            .padding(.horizontal, SOOMLayout.screenPadding)
                            .accessibilityIdentifier("feed.notification.comments.reopen")
                    }
                }
            }
            }
            .navigationTitle("알림의 운동").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("feed.notification.detail")
            .feedCardDestination(selection:$selectedDetail,onSubmitComment:onSubmitComment)
            .task { presentation.presentInitialComments(current:currentContext,canUseSocial:safety.canUseSocial) }
            .sheet(isPresented:$presentation.commentsPresented) {
                if safety.canUseSocial, presentation.supportsLegacyComments, presentation.permits(currentContext) {
                    FeedCommentsSheet(item:presentation.item,
                        onSubmit:{ try await onSubmitComment(presentation.item,$0) })
                }
            }
        }
        .feedCommentProfileNavigationHost()
        .toolbar(.visible,for:.navigationBar)
        .onChange(of:currentContext) { _, value in
            if !presentation.permits(value) { presentation.commentsPresented=false; dismiss() }
        }
        .onChange(of:scene) { _, phase in
            if phase == .background { presentation.commentsPresented=false; dismiss() }
        }
    }
}

/// Resolves on the inbox's navigation stack, not in the hidden home view. The
/// request may target a post outside home membership; no page/filter is mutated.
struct FeedNotificationCardLoader: View {
    let request: FeedNotificationRequest
    let resolve: (UUID) async -> FeedItem?
    let onSubmitComment: (FeedItem, String) async throws -> Void
    let onToggleCheer: (FeedItem) -> Void
    let onToggleSave: (FeedItem) -> Void
    let onDeletePost: (FeedItem) -> Void
    @StateObject private var navigation = FeedNotificationNavigation()
    @State private var context: AccountActivityReadContext?
    @State private var retry = UUID()
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scene
    private var currentContext: AccountActivityReadContext? {
        guard safety.canUseSocial || safety.canUseActivityPreview, let viewer=safety.viewerID else { return nil }
        return .init(viewerID:viewer,generation:safety.accountGeneration,safetyRevision:safety.revision)
    }
    var body: some View {
        Group {
            if let item=navigation.item, let context, context==currentContext {
                FeedNotificationCardDestination(item:item,context:context,opensComments:request.opensComments,
                    onSubmitComment:onSubmitComment,onToggleCheer:onToggleCheer,
                    onToggleSave:onToggleSave,onDeletePost:onDeletePost)
            } else if navigation.failed {
                VStack(spacing:16) {
                    Text("운동 카드를 열 수 없어요").font(.headline)
                    Text("삭제되었거나 접근할 수 없거나 연결이 원활하지 않아요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("다시 확인") { navigation.clear(); retry=UUID() }
                }.padding().accessibilityIdentifier("feed.notification.unavailable")
            } else {
                ProgressView("알림의 운동 찾는 중").accessibilityIdentifier("feed.notification.loading")
            }
        }
        .navigationTitle("알림의 운동").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible,for:.navigationBar)
        .task(id:retry) {
            guard let expected=currentContext else { return }
            if let context, context != expected { navigation.clear(); dismiss(); return }
            context=expected
            await navigation.resolve(request,isCurrent:{ currentContext==expected },using:resolve)
        }
        .onChange(of:currentContext) { _, value in
            if let context, value != context { navigation.clear(); dismiss() }
        }
        .onChange(of:scene) { _, phase in
            if phase == .background { navigation.clear(); dismiss() }
        }
    }
}

// Pure display-trigger policy. It grants no content or media authorization.
enum Feed60PaginationPolicy {
    static func shouldTrack(cardID: UUID, itemIDs: [UUID], hasMore: Bool) -> Bool {
        hasMore && itemIDs.suffix(2).contains(cardID)
    }
    /// nil means no mutation. Ignore unrelated/nested target IDs and ordering.
    static func targetVisibilityUpdate(visibleIDs: [UUID], itemIDs: [UUID],
                                       hasMore: Bool, current: Set<UUID>) -> Set<UUID>? {
        let updated = hasMore ? Set(visibleIDs).intersection(Set(itemIDs.suffix(2))) : []
        return updated == current ? nil : updated
    }
    static func displayIsCurrent(sourceIDs: [UUID], displayedIDs: [UUID]) -> Bool {
        sourceIDs == displayedIDs
    }
    static func footerIsCurrent(visible: Feed60PaginationFooterReceipt?,
                                current: Feed60PaginationFooterReceipt, displayIsCurrent: Bool) -> Bool {
        displayIsCurrent && visible == current
    }
    static func isNearTail(itemIDs: [UUID], visibleIDs: Set<UUID>) -> Bool {
        !itemIDs.suffix(2).allSatisfy { !visibleIDs.contains($0) }
    }
    static func hasDemand(footerVisible: Bool, nearTail: Bool,
                          receipt: Feed60PaginationPrefetchReceipt?, previous: Feed60PaginationPrefetchReceipt?) -> Bool {
        if footerVisible { return true }
        guard nearTail, let receipt else { return false }
        return receipt != previous
    }
    static func canRequest(active: Bool, ready: Bool, initialLoading: Bool, pageLoading: Bool,
                           hasMore: Bool, hasFailure: Bool) -> Bool {
        active && ready && !initialLoading && !pageLoading && hasMore && !hasFailure
    }
}

struct Feed60PaginationPrefetchReceipt: Equatable {
    let boundaryID: UUID
    let accountGeneration: Int
    let safetyRevision: Int
    let returnEpoch: Int
    let wakeRevision: Int
}

struct Feed60PaginationTaskKey: Equatable {
    let pageRevision: Int
    let wakeRevision: Int
    let accountGeneration: Int
    let safetyRevision: Int
    let returnEpoch: Int
    let boundaryID: UUID?
    let active: Bool
    let ready: Bool
    let initialLoading: Bool
    let hasMore: Bool
    let hasFailure: Bool
    let visibilityRevision: Int
}

/// A visibility observation belongs to the actual rendered footer, not to all
/// future pages. Successful empty pages renew geometry, but retry wakes do not.
struct Feed60PaginationFooterReceipt: Hashable {
    let boundaryID: UUID?
    let pageRevision: Int
}
