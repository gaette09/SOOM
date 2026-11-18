import SwiftData
import Combine
import SwiftUI
import UIKit

private enum SOOMTab: String, CaseIterable, Identifiable {
    case feed
    case activity
    case record
    case clubs
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed:
            return "피드"
        case .record:
            return "기록"
        case .activity:
            return "활동"
        case .clubs:
            return "랭킹"
        case .profile:
            return "프로필"
        }
    }

    var iconName: String {
        switch self {
        case .feed:
            return SOOMIcon.feed
        case .record:
            return SOOMIcon.record
        case .activity:
            return SOOMIcon.activity
        case .clubs:
            return "medal"
        case .profile:
            return SOOMIcon.profile
        }
    }
}

final class SOOMTabBarVisibility: ObservableObject {
    @Published var isHidden = false
    @Published var isFloatingCoachHidden = false
}

struct RootTabView: View {
    private let isGlobalFloatingCoachEnabled = false

    @ObservedObject private var socialSafety = CommunitySafetyStore.shared
    @EnvironmentObject private var accountStorage: HealthAccountStorageController
    @Environment(\.soomAccountPrivacyModel) private var accountPrivacy
    @StateObject private var automaticActivitySync = AccountActivityAutomaticSyncCoordinator()
    @ObservedObject private var watchCompanion = WatchWorkoutCompanion.shared
    @State private var isWatchWorkoutPresented = false
    @ObservedObject private var eventNotifications = EventNotificationCenter.shared
    @State private var selectedTab: SOOMTab = .activity
    @State private var tabBeforeRecording: SOOMTab = .feed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var isKeyboardPresented = false
    @State private var tabBarSafeAreaBottom: CGFloat = 0
    // Own the reference without subscribing the content/root to its publisher.
    // Only SOOMBottomTabBar observes compact/expanded transitions.
    @State private var tabBarScrollMotion = SOOMTabBarScrollMotion()
    @State private var isRecordLaunchPresented = false
    @State private var recordDismissDestination: SOOMTab?
    @State private var shouldAutoPresentRouteRecommendationOnRecordLaunch = false
    @State private var shouldShowInitialCoachPreview = true
    @State private var feedNavigationPath = NavigationPath()
    @State private var notificationSocialTarget: NotificationSocialTarget?
    @State private var profileNavigationPath = NavigationPath()
    @State private var clubsNavigationPath = NavigationPath()
    @State private var showingLogin = false
    @State private var loginOriginUserID: UUID?
    @State private var visitedProfile = false
    @State private var visitedClubs = false
    @State private var visitedActivity = false
    @State private var socialTabBarWasHidden: Bool?
    @State private var socialTabAtPause: SOOMTab?
    @State private var detailPresentation = WorkoutDetailPresentationStore()
    @EnvironmentObject private var authViewModel: AuthViewModel
    @AppStorage("SOOM.pendingLoginDestination") private var pendingLoginDestination = ""
    @StateObject private var tabBarVisibility = SOOMTabBarVisibility()
    @EnvironmentObject private var notificationDeepLinkRouter: NotificationDeepLinkRouter
    @Namespace private var tabBarNamespace

    init() {
        _selectedTab = State(initialValue: CommunitySafetyStore.shared.canUseSocial ? .feed : .activity)
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFont(name: SOOMFont.displayBoldName, size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: UIColor(SOOMColor.ink)
        ]
        UINavigationBar.appearance().titleTextAttributes = [
            .font: UIFont(name: SOOMFont.displayMediumName, size: 17) ?? UIFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: UIColor(SOOMColor.ink)
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            retainedContent
                .environment(\.workoutDetailPresentationStore, detailPresentation)
                .environment(\.soomRequestLogin, { destination in
                    pendingLoginDestination = destination.rawValue
                    loginOriginUserID = authViewModel.session.currentUser?.id
                    showingLogin = true
                })
                .environment(\.soomOpenActivities, { selectedTab = .activity })
                .environmentObject(tabBarVisibility)
                .environment(\.soomTabBarScrollMotion, tabBarScrollMotion)
                .environment(\.soomBottomOverlayInset, bottomOverlayInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SOOMColor.background.ignoresSafeArea())

            if shouldShowFloatingCoach {
                FloatingRecoveryCoach(shouldShowInitialPreview: $shouldShowInitialCoachPreview)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, SOOMLayout.FloatingCoach.trailingPadding)
                    .padding(.bottom, SOOMLayout.TabBar.bottomOverlayInset + SOOMLayout.FloatingCoach.bottomPaddingAboveTab)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
            }

            if !tabBarVisibility.isHidden {
                SOOMBottomTabBar(
                    selectedTab: $selectedTab,
                    namespace: tabBarNamespace,
                    scrollMotion: tabBarScrollMotion,
                    recordMotionActive: isTabBarScrollMotionEnabled,
                    onRecordSelected: {
                        SOOMHaptics.softImpact()
                        tabBeforeRecording = selectedTab
                        if watchCompanion.workout != nil { isWatchWorkoutPresented = true }
                        else { isRecordLaunchPresented = true }
                    }
                )
                    // The bar scales its chrome/labels; tap slots and content inset stay fixed.
                    .padding(.horizontal, SOOMLayout.TabBar.outerHorizontalPadding)
                    .padding(.bottom, SOOMLayout.TabBar.bottomPadding)
                    .offset(y: SOOMLayout.TabBar.safeAreaLowering(tabBarSafeAreaBottom))
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SOOMColor.background.ignoresSafeArea())
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { tabBarSafeAreaBottom = $0 }
        .environment(\.soomAutomaticActivitySync, automaticActivitySync)
        .background {
            if let accountPrivacy {
                AccountActivityAutomaticSyncHost(privacy: accountPrivacy, coordinator: automaticActivitySync)
            }
            AccountActivitySourceImportHost()
        }
        // SOOM v1 keeps Light Mode only while the visual system stabilizes.
        .preferredColorScheme(.light)
        .environment(\.font, SOOMFont.body(15, relativeTo: .body))
        .environment(\.soomTabBarExtraHeight, tabBarExtraHeight)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onChange(of: selectedTab) { _, tab in
            if tab == .profile { visitedProfile = true }
            if tab == .clubs { visitedClubs = true }
            if tab == .activity { visitedActivity = true }
            tabBarScrollMotion.restore()
        }
        .onChange(of: socialSafety.canUseSocial) { _, allowed in
            if allowed {
                if let hidden = socialTabBarWasHidden, socialTabAtPause == selectedTab { tabBarVisibility.isHidden = hidden }
                socialTabBarWasHidden = nil; socialTabAtPause = nil
                openPendingPush()
            }
            if !allowed {
                notificationDeepLinkRouter.clearLegacy();notificationSocialTarget=nil
                if selectedTab == .feed || selectedTab == .clubs {
                    if socialTabBarWasHidden == nil { socialTabBarWasHidden = tabBarVisibility.isHidden; socialTabAtPause = selectedTab }
                    tabBarVisibility.isHidden = false
                }
            }
        }
        .onChange(of: socialSafety.canUseActivityPreview, initial: true) { _, allowed in
            if allowed {
                notificationDeepLinkRouter.resumeNativePush(currentUserID:socialSafety.viewerID,
                    generation:socialSafety.accountGeneration,previewAllowed:true)
            }
            // An unverified initial gate is not account revocation. Keep a
            // cold-launch payload until verification or generation reset.
        }
        .onChange(of: socialSafety.accountGeneration) { _, _ in
            detailPresentation.clear()
            notificationDeepLinkRouter.clear();notificationSocialTarget=nil
            feedNavigationPath = NavigationPath(); profileNavigationPath = NavigationPath(); clubsNavigationPath = NavigationPath()
            visitedProfile = selectedTab == .profile; visitedClubs = selectedTab == .clubs
            socialTabBarWasHidden = nil; socialTabAtPause = nil
        }
        .sheet(isPresented: $showingLogin, onDismiss: {
            if authViewModel.session.currentUser?.authProvider != .supabase, authViewModel.session.currentUser?.id == loginOriginUserID { pendingLoginDestination = "" }
        }) {
            NavigationStack {
                SettingsView(category: .account)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { pendingLoginDestination = ""; showingLogin = false } } }
            }
        }
        .task(id: authViewModel.session.currentUser?.id) {
            guard let destination = SocialLoginDestination(rawValue: pendingLoginDestination),
                  !showingLogin || authViewModel.session.currentUser?.authProvider == .supabase else { return }
            showingLogin = false; pendingLoginDestination = ""
            switch destination {
            case .feed: selectedTab = .feed
            case .clubs: selectedTab = .clubs
            case .googleHealth: selectedTab = .profile; profileNavigationPath.append(SocialLoginDestination.googleHealth)
            }
        }
        .onChange(of: feedNavigationPath.count) { _, _ in tabBarScrollMotion.restore() }
        .onChange(of: isTabBarScrollMotionEnabled, initial: true) { _, enabled in
            tabBarScrollMotion.isEnabled = enabled
            tabBarScrollMotion.restore()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardPresented = false
            tabBarScrollMotion.restore()
        }
        .task(id: accountStorage.scopeID) {
            if !socialSafety.canUseSocial { notificationDeepLinkRouter.pendingPostId = nil;feedNavigationPath = NavigationPath() }
            guard !ReviewDemoMode.isActive else { return }
            watchCompanion.bind(scope: accountStorage.scopeID)
            if watchCompanion.workout == nil,
               let restored = try? RecordWorkoutCheckpointStore(fileURL: accountStorage.scopeDirectory.appendingPathComponent("active-workout.json")).load() {
                WorkoutLiveActivityController.shared.submit(restored.liveState(scope: accountStorage.scopeID, at: Date()), force: true)
                watchCompanion.setPhoneRecording(restored.state == .active || restored.state == .paused)
            }
            openOngoingWorkoutIfNeeded()
        }
        .onChange(of: watchCompanion.shouldOpenWorkout) { _, open in
            if open { openOngoingWorkoutIfNeeded() }
        }
        .fullScreenCover(isPresented: $isWatchWorkoutPresented) { WatchWorkoutCompanionView() }
        .onChange(of:eventNotifications.homeRequest) { _,request in
            if request != nil {selectedTab = socialSafety.canUseSocial ? .feed:.activity;feedNavigationPath=NavigationPath();eventNotifications.homeRequest=nil}
        }
        .sheet(isPresented:$eventNotifications.showsInbox) {NavigationStack {EventNotificationInboxView().toolbar {ToolbarItem(placement:.cancellationAction){Button("닫기"){eventNotifications.showsInbox=false}}}}}
        .onChange(of: notificationDeepLinkRouter.pendingNativePush, initial:true) { _, _ in openPendingNativePush() }
        .onChange(of: socialSafety.canUseSocial) { _, _ in openPendingNativePush() }
        .onChange(of: socialSafety.canUseActivityPreview) { _, _ in openPendingNativePush() }
        .onChange(of: notificationDeepLinkRouter.pendingPush) { _,_ in openPendingPush() }
        .onChange(of: notificationDeepLinkRouter.pendingPostId) { _, newValue in
            guard let postId = newValue else { return }
            guard socialSafety.canUseSocial else { notificationDeepLinkRouter.pendingPostId = nil; return }
            selectedTab = .feed
            feedNavigationPath.append(FeedPostRouteTarget(postId: postId))
            notificationDeepLinkRouter.pendingPostId = nil
        }
        .animation(reduceMotion ? nil : SOOMMotion.subtleSpring, value: tabBarVisibility.isHidden)
        .fullScreenCover(isPresented: $isRecordLaunchPresented, onDismiss: {
            selectedTab = recordDismissDestination ?? tabBeforeRecording
            recordDismissDestination = nil
            shouldAutoPresentRouteRecommendationOnRecordLaunch = false
        }) {
            VStack(spacing: 0) {
                if ReviewDemoMode.isActive {
                    ReviewDemoBanner()
                        .fixedSize(horizontal: false, vertical: true)
                }
                NavigationStack {
                    RecordView(
                        onDismiss: {
                            recordDismissDestination = nil
                            selectedTab = tabBeforeRecording
                            isRecordLaunchPresented = false
                        },
                        onSaveComplete: {
                            recordDismissDestination = .activity
                            isRecordLaunchPresented = false
                        },
                        onShareDraftComplete: {
                            recordDismissDestination = .feed
                            selectedTab = .feed
                            isRecordLaunchPresented = false
                        },
                        shouldAutoPresentRouteRecommendation: shouldAutoPresentRouteRecommendationOnRecordLaunch
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .preferredColorScheme(.light)
        }
    }

    private var isTabBarScrollMotionEnabled: Bool {
        scenePhase == .active && !reduceMotion && !voiceOverEnabled && !dynamicTypeSize.isAccessibilitySize && !isKeyboardPresented
            && !tabBarVisibility.isHidden && !isRecordLaunchPresented && !isWatchWorkoutPresented
    }

    private func openOngoingWorkoutIfNeeded() {
        guard watchCompanion.shouldOpenWorkout else { return }
        watchCompanion.shouldOpenWorkout = false
        if watchCompanion.workout != nil { isWatchWorkoutPresented = true }
        else {
            tabBeforeRecording = selectedTab
            isRecordLaunchPresented = true
        }
    }

    private var shouldShowFloatingCoach: Bool {
        guard isGlobalFloatingCoachEnabled else {
            return false
        }

        if tabBarVisibility.isHidden || tabBarVisibility.isFloatingCoachHidden {
            return false
        }

        return selectedTab != .activity && selectedTab != .clubs
    }

    // Five fixed navigation targets cannot grow as multi-line accessibility text.
    // At accessibility sizes their names remain available via VoiceOver and the
    // native large-content viewer, while the content itself keeps full scaling.
    private var tabBarExtraHeight: CGFloat { 0 }

    private var bottomOverlayInset: CGFloat {
        guard !tabBarVisibility.isHidden else { return 0 }
        let extra = dynamicTypeSize.isAccessibilitySize ? tabBarExtraHeight : (shouldShowFloatingCoach ? 72 : 0)
        return max(0, SOOMLayout.TabBar.bottomOverlayInset + extra - SOOMLayout.TabBar.safeAreaLowering(tabBarSafeAreaBottom))
    }

    private var retainedContent: some View {
        ZStack {
            retainedFeed
                .id("feed:\(accountStorage.scopeID):\(socialSafety.accountGeneration)")
                .opacity(selectedTab == .feed ? 1 : 0).allowsHitTesting(selectedTab == .feed).accessibilityHidden(selectedTab != .feed).environment(\.soomProfileNavigationIsActive, selectedTab == .feed)
            if selectedTab == .profile || visitedProfile {
            NavigationStack(path: $profileNavigationPath) {
                ProfileIdentityView()
                    .accessibilityHidden(selectedTab != .profile)
                    .navigationDestination(for: SocialLoginDestination.self) { _ in GoogleHealthConnectionView() }
            }
            .id("profile:\(accountStorage.scopeID):\(socialSafety.accountGeneration)")
            .opacity(selectedTab == .profile ? 1 : 0).allowsHitTesting(selectedTab == .profile).accessibilityHidden(selectedTab != .profile).environment(\.soomProfileNavigationIsActive, selectedTab == .profile)
            }
            if selectedTab == .clubs || visitedClubs {
            SocialAccessBoundary(loginDestination: .clubs, allowActivityPreview: true) { NavigationStack(path: $clubsNavigationPath) { SocialRankingView() }.accessibilityHidden(selectedTab != .clubs) }
                .id("clubs:\(accountStorage.scopeID):\(socialSafety.accountGeneration)")
                .opacity(selectedTab == .clubs ? 1 : 0).allowsHitTesting(selectedTab == .clubs).accessibilityHidden(selectedTab != .clubs).environment(\.soomProfileNavigationIsActive, selectedTab == .clubs)
            }
            if selectedTab == .activity || visitedActivity {
                NavigationStack { ActivityHubView() }
                    .id("activity:\(accountStorage.scopeID)")
                    .opacity(selectedTab == .activity ? 1 : 0)
                    .allowsHitTesting(selectedTab == .activity).accessibilityHidden(selectedTab != .activity).environment(\.soomProfileNavigationIsActive, selectedTab == .activity)
            }
        }
    }

    private func openPendingNativePush() {
        guard let payload=notificationDeepLinkRouter.consumeNativePush(currentUserID:socialSafety.viewerID,
            canNavigate:socialSafety.canUseSocial || socialSafety.canUseActivityPreview) else { return }
        selectedTab = .feed
        feedNavigationPath.append(NativeNotificationRouteTarget(payload:payload))
    }

    private func openPendingPush() {
        guard socialSafety.canUseSocial else { return }
        guard let target=notificationDeepLinkRouter.consumePush(currentUserID:socialSafety.viewerID) else { return }
        selectedTab = .feed
        switch target {
        case .post(let id): feedNavigationPath.append(FeedPostRouteTarget(postId:id))
        case .requests: notificationSocialTarget = .requests
        case .profile(let id): notificationSocialTarget = .profile(id)
        }
    }

    private var retainedFeed: some View {
        SocialAccessBoundary(allowActivityPreview: true, allowsEarlyFeedCache: selectedTab == .feed) { NavigationStack(path: $feedNavigationPath) {
            FeedViewContainer(
                isActive: selectedTab == .feed,
                onNavigateToClubs: { selectedTab = .clubs },
                onNavigateToRouteRecommendation: {
                    SOOMHaptics.softImpact()
                    shouldAutoPresentRouteRecommendationOnRecordLaunch = true
                    tabBeforeRecording = selectedTab
                    isRecordLaunchPresented = true
                }
            ).accessibilityHidden(selectedTab != .feed)
                .navigationDestination(isPresented: Binding(get: { notificationSocialTarget != nil }, set: { if !$0 { notificationSocialTarget = nil } })) {
                    if let target = notificationSocialTarget {
                        switch target {
                        case .requests: FollowRequestsView()
                        case .profile(let id): SOOMProfileDestination(userID: id)
                        }
                    }
                }
        } }
    }


}

private struct FloatingRecoveryCoach: View {
    @Binding var shouldShowInitialPreview: Bool
    @State private var isExpanded = false
    @State private var dismissedUntil: Date?
    @State private var isPreviewVisible = false
    @State private var didScheduleInitialPreview = false
    @State private var typedCoachMessage = ""
    @State private var typingTask: Task<Void, Never>?
    @State private var isDetailExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let fixedSheetDetent: PresentationDetent = .height(RecordFixedSheetLayout.coachDetailHeight)

    private var summary: RecoverySummary {
        .mockToday
    }

    private var coachMessage: String {
        "오늘은 무리하지 않아도 좋아요.\n가볍게 이어가도 충분해요."
    }

    private var sheetDetents: Set<PresentationDetent> {
        [Self.fixedSheetDetent]
    }

    private var isDismissed: Bool {
        if let dismissedUntil {
            return Date() < dismissedUntil
        }
        return false
    }

    var body: some View {
        if !isDismissed {
            HStack(alignment: .bottom, spacing: 10) {
                if isPreviewVisible {
                    coachPreview
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)),
                                removal: .opacity.combined(with: .move(edge: .trailing))
                            )
                        )
                }

                circularButton
            }
            .task {
                await showInitialPreviewIfNeeded()
            }
            .sheet(isPresented: $isExpanded) {
                coachSheet
                    .presentationDetents(sheetDetents)
                    .presentationDragIndicator(.hidden)
            }
            .animation(reduceMotion ? nil : SOOMMotion.coachSpring, value: isPreviewVisible)
            .animation(reduceMotion ? nil : SOOMMotion.coachSpring, value: isDismissed)
        }
    }

    private var coachPreview: some View {
        HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Button {
                collapsePreview()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("회복 리듬 확인")
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                    Text("오늘은 가볍게 시작해도 좋아요")
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                collapsePreview()
            } label: {
                Image(soom: SOOMIcon.close)
                    .font(.system(size: SOOMFont.Size.caption, weight: .bold))
                    .foregroundStyle(SOOMColor.tertiaryInk)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("회복 코치 미리보기 닫기")
        }
        .padding(.horizontal, SOOMLayout.FloatingCoach.previewHorizontalPadding)
        .padding(.vertical, SOOMLayout.FloatingCoach.previewVerticalPadding)
        .frame(maxWidth: SOOMLayout.FloatingCoach.previewMaxWidth, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.pill, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.pill, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.58), lineWidth: 1)
        }
        .shadow(color: SOOMColor.ink.opacity(0.055), radius: 14, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("회복 코치 미리보기")
        .accessibilityValue("오늘은 가볍게 시작해도 좋아요")
    }

    private var circularButton: some View {
        Button {
            collapsePreview()
            SOOMHaptics.softImpact()
            isDetailExpanded = false
            isExpanded = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(SOOMColor.accent)
                    .overlay {
                        Circle()
                            .stroke(SOOMColor.white, lineWidth: 1.25)
                    }

                companionMark
                    .accessibilityHidden(true)

                Text("\(summary.score)")
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.ink)
                    .frame(width: SOOMLayout.FloatingCoach.scoreBadgeSize, height: SOOMLayout.FloatingCoach.scoreBadgeSize)
                    .background(SOOMColor.white)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(SOOMColor.accent, lineWidth: 1.2)
                    }
                    .shadow(color: SOOMColor.ink.opacity(0.10), radius: 4, x: 0, y: 2)
                    .padding(SOOMLayout.Spacing.xs)
            }
            .frame(width: SOOMLayout.FloatingCoach.buttonSize, height: SOOMLayout.FloatingCoach.buttonSize)
            .shadow(color: SOOMColor.ink.opacity(0.12), radius: 14, x: 0, y: 8)
            .contentShape(Circle())
        }
        .buttonStyle(FloatingCoachButtonStyle())
        .accessibilityLabel("회복 코치 열기")
        .accessibilityValue("\(summary.score)점, \(summary.recommendation)")
    }

    private var companionMark: some View {
        ZStack {
            Circle()
                .trim(from: 0.06, to: 0.40)
                .stroke(SOOMColor.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 45, height: 45)
                .rotationEffect(.degrees(-18))

            Circle()
                .trim(from: 0.57, to: 0.91)
                .stroke(SOOMColor.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 45, height: 45)
                .rotationEffect(.degrees(-18))

            Circle()
                .stroke(SOOMColor.white, lineWidth: 1.3)
                .frame(width: 31, height: 31)

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(SOOMColor.white)
                        .frame(width: 5.2, height: 5.2)
                    Circle()
                        .fill(SOOMColor.white)
                        .frame(width: 5.2, height: 5.2)
                }

                Capsule()
                    .fill(SOOMColor.white)
                    .frame(width: 14, height: 3)
                    .offset(y: -1)
            }
        }
        .frame(width: 48, height: 48)
    }

    private func collapsePreview() {
        withAnimation(reduceMotion ? nil : SOOMMotion.coachSpring) {
            isPreviewVisible = false
        }
    }

    private func showInitialPreviewIfNeeded() async {
        guard !didScheduleInitialPreview, shouldShowInitialPreview, !isDismissed else {
            return
        }
        didScheduleInitialPreview = true
        shouldShowInitialPreview = false

        await MainActor.run {
            withAnimation(reduceMotion ? nil : SOOMMotion.coachSpring) {
                isPreviewVisible = true
            }
        }

        let delay = UInt64(SOOMLayout.FloatingCoach.previewAutoCollapseDelaySeconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: delay)

        guard !Task.isCancelled, !isExpanded, !isDismissed else {
            return
        }

        await MainActor.run {
            collapsePreview()
        }
    }

    private func hideUntil(_ date: Date) {
        dismissedUntil = date
        collapsePreview()
        isExpanded = false
        isDetailExpanded = false
        stopTypingCoachMessage(reset: true)
    }

    private struct FloatingCoachButtonStyle: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .opacity(configuration.isPressed ? 0.92 : 1)
                .animation(reduceMotion ? nil : SOOMMotion.cardPress, value: configuration.isPressed)
        }
    }

    private var coachSheet: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 18) {
                Text("회복 코치")
                    .font(SOOMFont.body(17, weight: .bold, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 6) {
                    Text("오늘의 회복 리듬")
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                        .textCase(.uppercase)

                    Text("\(summary.score)")
                        .font(SOOMFont.display(54, relativeTo: .largeTitle))
                        .foregroundStyle(SOOMColor.accent)
                        .accessibilityLabel("회복 점수 \(summary.score)")

                    Text(summary.status)
                        .font(SOOMFont.displayMedium(23, relativeTo: .title3))
                        .foregroundStyle(SOOMColor.ink)
                }

                Text(typedCoachMessage.isEmpty ? " " : typedCoachMessage)
                    .font(SOOMFont.displayMedium(18, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .fixedSize(horizontal: false, vertical: true)

                if isDetailExpanded {
                    expandedCoachContext
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                actionArea
                    .padding(.top, isDetailExpanded ? 4 : 12)
            }
            .padding(.horizontal, SOOMLayout.screenPadding)
            .padding(.top, SOOMLayout.screenPadding + 4)
            .padding(.bottom, SOOMLayout.screenPadding + 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SOOMColor.background)
        .animation(reduceMotion ? nil : SOOMMotion.coachSpring, value: isDetailExpanded)
        .onAppear {
            startTypingCoachMessage()
        }
        .onDisappear {
            stopTypingCoachMessage(reset: true)
            isDetailExpanded = false
        }
    }

    private var expandedCoachContext: some View {
        VStack(alignment: .leading, spacing: 12) {
            recoveryContextRow(title: "오늘의 방향", value: "가볍게 이어가기")
            recoveryContextRow(title: "리듬", value: "무리한 강도보다 호흡 유지")
            recoveryContextRow(title: "추천", value: "짧은 산책이나 낮은 강도의 러닝")
        }
        .padding(SOOMLayout.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SOOMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.pill, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.pill, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.7), lineWidth: 1)
        }
    }

    private func recoveryContextRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.tertiaryInk)
                .frame(width: 74, alignment: .leading)

            Text(value)
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionArea: some View {
        VStack(spacing: 12) {
            HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                hideForOneHourButton
                hideForTodayButton
            }
            .frame(maxWidth: .infinity)

            coachDetailButton
        }
        .padding(.bottom, SOOMLayout.Spacing.xs)
    }

    private var coachDetailButton: some View {
        Button {
            SOOMHaptics.softImpact()
            withAnimation(reduceMotion ? nil : SOOMMotion.coachSpring) {
                isDetailExpanded = true
            }
        } label: {
            Text(isDetailExpanded ? "자세히 보는 중" : "자세히 보기")
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SOOMLayout.Spacing.md)
                .background(SOOMColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDetailExpanded)
    }

    private var hideForOneHourButton: some View {
        Button("1시간 숨기기") {
            SOOMHaptics.selection()
            hideUntil(Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date())
        }
        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
        .foregroundStyle(SOOMColor.secondaryInk)
    }

    private var hideForTodayButton: some View {
        Button("오늘 숨기기") {
            SOOMHaptics.selection()
            let endOfDay = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
            hideUntil(endOfDay)
        }
        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
        .foregroundStyle(SOOMColor.secondaryInk)
    }

    private func startTypingCoachMessage() {
        typingTask?.cancel()

        guard reduceMotion == false else {
            typedCoachMessage = coachMessage
            return
        }

        typedCoachMessage = ""
        let characters = Array(coachMessage)
        typingTask = Task {
            var wasInsideWord = false

            for index in characters.indices {
                let character = characters[index]
                let isWordCharacter = isTypingWordCharacter(character)
                let isWordStart = isWordCharacter && !wasInsideWord

                if isWordStart {
                    await MainActor.run {
                        SOOMHaptics.typingWordStart()
                    }
                }

                try? await Task.sleep(nanoseconds: 78_000_000)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    typedCoachMessage.append(character)
                }

                let isLastCharacter = index == characters.index(before: characters.endIndex)
                let nextCharacter = isLastCharacter ? nil : characters[characters.index(after: index)]
                let isWordEnd = isWordCharacter && (nextCharacter.map(isTypingWordCharacter) != true)
                wasInsideWord = isWordCharacter

                if isWordEnd && !isLastCharacter {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                }
            }
        }
    }

    private func stopTypingCoachMessage(reset: Bool) {
        typingTask?.cancel()
        typingTask = nil
        if reset {
            typedCoachMessage = ""
        }
    }

    private func isTypingWordCharacter(_ character: Character) -> Bool {
        guard reduceMotion == false else {
            return false
        }

        let scalars = character.unicodeScalars
        return scalars.contains { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) == false &&
            CharacterSet.punctuationCharacters.contains(scalar) == false
        }
    }
}

private enum ActivityHubSection: String, CaseIterable, Identifiable {
    case today
    case workouts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "오늘"
        case .workouts:
            return "운동 목록"
        }
    }
}

/// Remembers the last-viewed sub-tab across sessions (Strava-style), not just
/// within one screen lifetime — hence @AppStorage instead of plain @State.
private struct ActivityHubView: View {
    @AppStorage("activityHubSelectedSection") private var selectedSectionRawValue = ActivityHubSection.today.rawValue
    @State private var showsManualEntry = false
    @State private var hasVisitedLoad = false

    private var selectedSection: ActivityHubSection {
        ActivityHubSection(rawValue: selectedSectionRawValue) ?? .today
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("활동").font(SOOMFont.displayMedium(28, relativeTo: .title))
                Spacer()
                Button { showsManualEntry = true } label: {
                    Image(soom: "plus").font(.system(size: 22)).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("운동 직접 입력")
                .accessibilityIdentifier("activity.manualEntry")
            }
            .padding(.horizontal, SOOMLayout.screenPadding).frame(minHeight: 52)
            sectionPicker
                .padding(.horizontal, SOOMLayout.screenPadding)
                .padding(.top, 0)

            ZStack {
                if selectedSection == .today || hasVisitedLoad {
                    ActivityLoadTodayContainer(onAllRecords: { selectedSectionRawValue = ActivityHubSection.workouts.rawValue })
                        .opacity(selectedSection == .today ? 1 : 0)
                        .allowsHitTesting(selectedSection == .today)
                        .accessibilityHidden(selectedSection != .today)
                }
                if selectedSection == .workouts { ActivityCalendarView() }
            }
            .onAppear { if selectedSection == .today { hasVisitedLoad = true } }
            .onChange(of: selectedSection) { _, next in if next == .today { hasVisitedLoad = true } }
        }
        .suspendsSOOMTabBarScrollMotion(when: showsManualEntry)
        .sheet(isPresented: $showsManualEntry) {
            ManualWorkoutEntryView(onSave: { _ in selectedSectionRawValue = ActivityHubSection.workouts.rawValue })
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 4) {
            ForEach(ActivityHubSection.allCases) { section in
                Button {
                    selectedSectionRawValue = section.rawValue
                    SOOMHaptics.selection()
                } label: {
                    Text(section.title)
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(selectedSection == section ? SOOMColor.ink : SOOMColor.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .overlay(alignment: .bottom) {
                            if selectedSection == section { RoundedRectangle(cornerRadius: 1).fill(SOOMColor.ink).frame(width: 48, height: 2) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedSection == section ? [.isSelected] : [])
                .accessibilityIdentifier("activity.section.\(section.rawValue)")
            }
        }
    }
}

/// MVP: 이미 있는 provider(UnifiedWorkoutWeeklyProgressProvider/UnifiedWorkoutRecoveryPreviewProvider)와
/// Feed가 쓰는 것과 동일한 카드(FeedWeeklySnapshotCarousel/FeedRecoveryInsightCard)를 재사용한다.
/// PDF 스펙의 4지표(신체에너지/스트레스/회복/운동강도) 분리 대시보드는 별도 배치(M4, 신규 모델링 필요).
private struct ActivityTodaySection: View {
    @EnvironmentObject private var healthStorage: HealthAccountStorageController
    @Environment(\.modelContext) private var modelContext
    @State private var weeklySnapshot: FeedWeeklySnapshot?
    @State private var recoveryInsight: FeedRecoveryInsight?

    var body: some View {
        SOOMScreen(tracksTabBarScroll: true) {
            if let weeklySnapshot {
                FeedWeeklySnapshotCarousel(snapshot: weeklySnapshot)
            }

            if let recoveryInsight {
                NavigationLink {
                    RecoveryViewContainer()
                } label: {
                    FeedRecoveryInsightCard(insight: recoveryInsight)
                }
                .buttonStyle(.plain)
                .accessibilityHint("회복 상세 화면으로 이동합니다.")
            }
        }
        .task(id: healthStorage.dataRevision) {
            await loadTodayContent()
        }
    }

    @MainActor
    private func loadTodayContent() async {
        let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        let weeklyProgressProvider = UnifiedWorkoutWeeklyProgressProvider(store: store)
        let recoveryPreviewProvider = UnifiedWorkoutRecoveryPreviewProvider(store: store)

        async let weeklyProgress = weeklyProgressProvider.fetchWeeklyProgress(referenceDate: Date())
        async let recoveryPreview = recoveryPreviewProvider.fetchPreviewSummary()

        let progress = try? await weeklyProgress
        let recovery = try? await recoveryPreview

        weeklySnapshot = progress.map {
            FeedWeeklySnapshot(progress: $0, sportSummary: sportSummary(for: $0))
        }
        recoveryInsight = recovery.map { FeedRecoveryInsight(preview: $0) }
    }

    private func sportSummary(for progress: WeeklyWorkoutProgress) -> String {
        guard progress.workoutCount > 0 else { return "이번 주 운동을 기다리고 있어요" }
        return "이번 주 \(progress.workoutCount)회 움직였어요"
    }
}

/// Approved R11 frames at their original 30fps. No published animation state.
struct SOOMRecordCharacterTimeline {
    static let framesPerSecond = 30.0
    static let runFrameCount = 96
    static let totalFrameCount = 216
    static let duration = 7.2
    private(set) var elapsed = 0.0
    private(set) var isActive = false
    private var lastTimestamp: Double?

    var frameIndex: Int {
        min(Self.totalFrameCount - 1, Int((elapsed * Self.framesPerSecond + 0.0000001).rounded(.down)))
    }
    var isRunningClip: Bool { frameIndex < Self.runFrameCount }
    mutating func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        lastTimestamp = nil // Background/inactive time never advances the clip.
    }
    mutating func advance(to timestamp: Double) {
        guard isActive, timestamp.isFinite else { return }
        defer { lastTimestamp = timestamp }
        guard let lastTimestamp, timestamp >= lastTimestamp else { return }
        elapsed = (elapsed + timestamp - lastTimestamp).truncatingRemainder(dividingBy: Self.duration)
        // Normalize only nanosecond rounding at the full-cycle boundary.
        if Self.duration - elapsed < 0.00000001 { elapsed = 0 }
    }
    static func contentsRect(for frame: Int) -> CGRect {
        let index = max(0, min(frame, totalFrameCount - 1))
        // 120px frame + two transparent pixels on each edge prevents texture bleed.
        return CGRect(x: Double(index % 12 * 124 + 2) / 1488,
                      y: Double(index / 12 * 124 + 2) / 2232,
                      width: 120.0 / 1488, height: 120.0 / 2232)
    }
}

private struct SOOMRecordCharacterIcon: View {
    let isVisible: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityPlayAnimatedImages) private var playAnimatedImages

    var body: some View {
        SOOMRecordCharacterNativeView(active: isVisible && scenePhase == .active,
            reduced: reduceMotion || voiceOver || !playAnimatedImages)
            .frame(width: 40, height: 40)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct SOOMRecordCharacterNativeView: UIViewRepresentable {
    let active: Bool
    let reduced: Bool
    func makeUIView(context: Context) -> SOOMRecordCharacterSurface { SOOMRecordCharacterSurface() }
    func updateUIView(_ view: SOOMRecordCharacterSurface, context: Context) {
        view.configure(active: active, reduced: reduced)
    }
    static func dismantleUIView(_ view: SOOMRecordCharacterSurface, coordinator: ()) { view.stop() }
}

/// One shared, predecoded texture; decoding never runs on the main actor.
private final class SOOMRecordCharacterImages: @unchecked Sendable {
    let atlas: CGImage
    let reducedRun: CGImage
    let reducedCycle: CGImage
    init?(atlas: CGImage?, run: CGImage?, cycle: CGImage?) {
        guard let atlas, let run, let cycle else { return nil }
        self.atlas = atlas; reducedRun = run; reducedCycle = cycle
    }
    static let load = Task.detached(priority: .utility) { () -> SOOMRecordCharacterImages? in
        func decoded(_ name: String) -> CGImage? {
            guard let image = UIImage(named: name)?.cgImage,
                  let context = CGContext(data: nil, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return context.makeImage()
        }
        return SOOMRecordCharacterImages(atlas: decoded("SOOMRecordR11Atlas"),
            run: decoded("SOOMRecordR11ReducedRun"), cycle: decoded("SOOMRecordR11ReducedCycle"))
    }
}

@MainActor private final class SOOMRecordCharacterSurface: UIView {
    private let fallback = UIImageView(image: UIImage(systemName: "record.circle"))
    private var images: SOOMRecordCharacterImages?
    private var imageTask: Task<Void, Never>?
    private var displayLink: CADisplayLink?
    private var timeline = SOOMRecordCharacterTimeline()
    private var requestedActive = false
    private var reduced = false
    private var lastFrame: Int?
    private var showingReduced: Bool?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; isOpaque = false; isUserInteractionEnabled = false
        isAccessibilityElement = false
        fallback.contentMode = .scaleAspectFit; fallback.tintColor = .secondaryLabel
        fallback.isUserInteractionEnabled = false; fallback.isAccessibilityElement = false
        addSubview(fallback)
        layer.contentsGravity = .resize
        layer.minificationFilter = .linear; layer.magnificationFilter = .linear
        imageTask = Task { [weak self] in
            let images = await SOOMRecordCharacterImages.load.value
            guard !Task.isCancelled, let self else { return }
            self.images = images
            self.fallback.isHidden = images != nil
            self.updatePlayback()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews(); fallback.frame = bounds.insetBy(dx: 8, dy: 8)
    }
    override func didMoveToWindow() { super.didMoveToWindow(); updatePlayback() }

    func configure(active: Bool, reduced: Bool) {
        requestedActive = active; self.reduced = reduced
        updatePlayback()
    }
    private func updatePlayback() {
        let active = requestedActive && !reduced && window != nil && images != nil
        timeline.setActive(active)
        if active, displayLink == nil {
            let proxy = DisplayLinkTarget(owner: self)
            let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
            displayLink = link
            link.add(to: .main, forMode: .common)
        } else if !active {
            displayLink?.invalidate(); displayLink = nil
        }
        render()
    }
    fileprivate func tick(_ link: CADisplayLink) {
        timeline.advance(to: link.timestamp)
        render()
    }
    private func render() {
        guard let images else { return }
        let frame = timeline.frameIndex
        guard lastFrame != frame || showingReduced != reduced else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if reduced {
            layer.contents = timeline.isRunningClip ? images.reducedRun : images.reducedCycle
            layer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        } else {
            if showingReduced != false { layer.contents = images.atlas }
            layer.contentsRect = SOOMRecordCharacterTimeline.contentsRect(for: frame)
        }
        CATransaction.commit()
        lastFrame = frame; showingReduced = reduced
    }
    func stop() {
        requestedActive = false; timeline.setActive(false)
        displayLink?.invalidate(); displayLink = nil
        imageTask?.cancel(); imageTask = nil
    }
    deinit { displayLink?.invalidate(); imageTask?.cancel() }

    @MainActor private final class DisplayLinkTarget: NSObject {
        weak var owner: SOOMRecordCharacterSurface?
        init(owner: SOOMRecordCharacterSurface) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) {
            guard let owner else { link.invalidate(); return }
            owner.tick(link)
        }
    }
}

private struct SOOMBottomTabBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Binding var selectedTab: SOOMTab
    let namespace: Namespace.ID
    @ObservedObject var scrollMotion: SOOMTabBarScrollMotion
    let recordMotionActive: Bool
    @Environment(\.soomTabBarExtraHeight) private var tabBarExtraHeight
    let onRecordSelected: () -> Void

    private var visualScale: CGFloat {
        scrollMotion.isCompact ? SOOMTabBarScrollReducer.compactScale : 1
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = SOOMTabBarTouchLayout(
                containerWidth: proxy.size.width,
                visualScale: visualScale,
                tabCount: SOOMTab.allCases.count,
                horizontalPadding: SOOMLayout.TabBar.containerHorizontalPadding
            )
            ZStack(alignment: .bottom) {
                containerSurface
                    .frame(width: proxy.size.width, height: containerHeight)
                    .scaleEffect(visualScale, anchor: .bottom)
                    .allowsHitTesting(false)
                HStack(spacing: 0) {
                    ForEach(SOOMTab.allCases) { tab in
                        Button {
                            if tab == .record {
                                onRecordSelected()
                            } else {
                                guard selectedTab != tab else { return }
                                selectedTab = tab
                            }
                        } label: {
                            SOOMBottomTabItem(tab: tab, isSelected: selectedTab == tab, namespace: namespace, recordMotionActive: recordMotionActive)
                        }
                        .buttonStyle(LiquidTabButtonStyle(
                            visualScale: visualScale,
                            visualWidth: layout.visualItemWidth,
                            targetWidth: layout.targetItemWidth
                        ))
                        .frame(width: layout.targetItemWidth, height: SOOMLayout.TabBar.itemHeight + tabBarExtraHeight)
                        .accessibilityIdentifier("soom.tab." + tab.rawValue)
                        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                        .accessibilityHint(tab == .record ? "새 운동 기록을 엽니다." : "\(tab.title) 화면으로 이동합니다.")
                        .accessibilityShowsLargeContentViewer {
                            VStack { Image(soom: tab.iconName, selected: selectedTab == tab).font(.largeTitle); Text(tab.title) }
                        }
                    }
                }
                .frame(width: layout.targetRowWidth, height: SOOMLayout.TabBar.itemHeight + tabBarExtraHeight)
                .padding(.bottom, SOOMLayout.TabBar.containerVerticalPadding * visualScale)
            }
            .frame(width: proxy.size.width, height: containerHeight, alignment: .bottom)
        }
        .frame(height: containerHeight)
        .animation(reduceMotion || voiceOverEnabled ? nil : .easeInOut(duration: SOOMTabBarScrollReducer.animationDuration), value: scrollMotion.isCompact)
        .animation(reduceMotion ? nil : SOOMMotion.subtleSpring, value: selectedTab)
    }

    private var containerHeight: CGFloat {
        SOOMLayout.TabBar.height + 2 * SOOMLayout.TabBar.containerVerticalPadding + tabBarExtraHeight
    }

    private var containerSurface: some View {
        Color.clear
        .background {
            ZStack {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                SOOMColor.white.opacity(0.34),
                                SOOMColor.white.opacity(0.14),
                                SOOMColor.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                SOOMColor.white.opacity(0.42),
                                SOOMColor.ink.opacity(0.05),
                                SOOMColor.white.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: SOOMColor.ink.opacity(0.07), radius: SOOMLayout.TabBar.containerShadowRadius, x: 0, y: SOOMLayout.TabBar.containerShadowYOffset)
        }
        .overlay(alignment: .top) {
            Capsule(style: .continuous)
                .fill(SOOMColor.white.opacity(0.30))
                .frame(height: SOOMLayout.TabBar.topHighlightHeight)
                .padding(.horizontal, SOOMLayout.TabBar.topHighlightHorizontalPadding)
                .offset(y: 1.5)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(SOOMColor.ink.opacity(0.025))
                .frame(height: SOOMLayout.TabBar.bottomHighlightHeight)
                .padding(.horizontal, SOOMLayout.TabBar.bottomHighlightHorizontalPadding)
                .offset(y: -1)
                .allowsHitTesting(false)
        }
        .compositingGroup()
    }
}

private struct SOOMBottomTabItem: View {
    @Environment(\.soomTabBarExtraHeight) private var tabBarExtraHeight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var auth: AuthViewModel
    let tab: SOOMTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let recordMotionActive: Bool

    var body: some View {
        standardItem
    }

    private var standardItem: some View {
        ZStack {
            if isSelected {
                if reduceMotion {
                    selectionPill
                } else {
                    selectionPill.matchedGeometryEffect(id: "selectedLiquidTab", in: namespace)
                }
            }

            VStack(spacing: SOOMLayout.TabBar.itemLabelSpacing) {
                Group {
                    if tab == .record {
                        SOOMRecordCharacterIcon(isVisible: recordMotionActive)
                    } else if tab == .profile, auth.session.currentUser?.avatarPath != nil {
                        SOOMAvatarView(userID: auth.session.currentUser?.id,
                                       avatarPath: auth.session.currentUser?.avatarPath, size: 24)
                            .overlay(Circle().stroke(isSelected ? SOOMColor.accent : .clear, lineWidth: 1.5))
                    } else {
                        Image(soom: tab.iconName, selected: isSelected)
                    }
                }
                    .font(.system(size: SOOMLayout.TabBar.defaultIconSize, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .frame(height: SOOMLayout.TabBar.iconHeight)
                    .scaleEffect(reduceMotion ? 1 : (isSelected ? 1.06 : SOOMLayout.TabBar.normalIconScale))
                    .offset(y: reduceMotion ? 0 : (isSelected ? -1 : 0))

                if !dynamicTypeSize.isAccessibilitySize {
                    Text(tab.title)
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .lineLimit(1)
                        .opacity(isSelected ? 1 : 0.74)
                }
            }
        }
        .foregroundStyle(isSelected ? SOOMColor.accent : SOOMColor.ink.opacity(0.56))
        .frame(maxWidth: .infinity)
        .frame(height: SOOMLayout.TabBar.itemHeight + tabBarExtraHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityValue(tab == .record ? "" : (isSelected ? "선택됨" : "선택 안 됨"))
    }

    private var selectionPill: some View {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        SOOMColor.accentSurface.opacity(0.80),
                                        SOOMColor.white.opacity(0.22),
                                        SOOMColor.accent.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(SOOMColor.white.opacity(0.42), lineWidth: 1)
                    }
                    .shadow(color: SOOMColor.accent.opacity(0.07), radius: SOOMLayout.TabBar.selectedShadowRadius, x: 0, y: 3)
            .allowsHitTesting(false)
    }
}

private struct LiquidTabButtonStyle: ButtonStyle {
    @Environment(\.soomTabBarExtraHeight) private var tabBarExtraHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let visualScale: CGFloat
    let visualWidth: CGFloat
    let targetWidth: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: visualWidth, height: SOOMLayout.TabBar.itemHeight + tabBarExtraHeight)
            .scaleEffect(visualScale * (reduceMotion ? 1 : (configuration.isPressed ? SOOMLayout.TabBar.pressScale : 1)), anchor: .bottom)
            .opacity(configuration.isPressed ? 0.76 : 1)
            // Add the hit rectangle after every visual transform, including press.
            .frame(width: targetWidth, height: SOOMLayout.TabBar.itemHeight + tabBarExtraHeight, alignment: .bottom)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : SOOMMotion.cardPress, value: configuration.isPressed)
    }
}

private struct SOOMTabBarHiddenModifier: ViewModifier {
    @EnvironmentObject private var visibility: SOOMTabBarVisibility

    func body(content: Content) -> some View {
        content
            .onAppear {
                visibility.isHidden = true
            }
            .onDisappear {
                visibility.isHidden = false
            }
    }
}

private struct SOOMFloatingCoachHiddenModifier: ViewModifier {
    @EnvironmentObject private var visibility: SOOMTabBarVisibility

    func body(content: Content) -> some View {
        content
            .onAppear {
                visibility.isFloatingCoachHidden = true
            }
            .onDisappear {
                visibility.isFloatingCoachHidden = false
            }
    }
}

extension View {
    func hidesSOOMTabBar() -> some View {
        modifier(SOOMTabBarHiddenModifier())
    }

    func hidesSOOMFloatingCoach() -> some View {
        modifier(SOOMFloatingCoachHiddenModifier())
    }
}

private struct SOOMTabBarExtraHeightKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
private extension EnvironmentValues {
    var soomTabBarExtraHeight: CGFloat {
        get { self[SOOMTabBarExtraHeightKey.self] }
        set { self[SOOMTabBarExtraHeightKey.self] = newValue }
    }
}

/// Root-owned automatic reconciliation is independent of visiting the Feed tab.
/// A temporary receipt/network suspension stops delivery, not local collection.
@MainActor final class AccountActivityAutomaticSyncCoordinator: ObservableObject {
    @Published private(set) var worker: AccountActivityAutomaticSyncWorker?
    private(set) var identity: String?
    private var expiresAt: Date?
    private var refreshPolicy: (() -> Void)?
    private var configurationTask: Task<Void,Never>?
    private var retirementTask: Task<Void,Never>?
    private var expirationTask: Task<Void,Never>?
    private var retirementEpoch=UUID()
    private var epoch=UUID()
    func configure(identity: String, expiresAt: Date, refreshPolicy: @escaping () -> Void,
                   makeWorker: @escaping () -> AccountActivityAutomaticSyncWorker) {
        guard self.identity != identity || (worker == nil && configurationTask == nil) else { request(); return }
        stop()
        let retirement=retirementTask
        self.identity=identity;self.expiresAt=expiresAt;self.refreshPolicy=refreshPolicy
        let token=epoch
        if let retirement {
            // A cancelled write can still own the durable path until its awaited
            // transport returns. Do not race the replacement worker for that lock.
            configurationTask=Task { @MainActor in
                await retirement.value
                guard !Task.isCancelled,self.epoch==token,self.identity==identity else{return}
                self.configurationTask=nil
                guard expiresAt>Date() else {self.refreshPolicy?();return}
                self.worker=makeWorker();self.worker?.request();self.scheduleLeaseRenewal(token:token)
            }
        } else if expiresAt>Date() {worker=makeWorker();worker?.request();scheduleLeaseRenewal(token:token)}
        else {refreshPolicy()}
    }
    private func scheduleLeaseRenewal(token:UUID) {
        guard let expiresAt else{return}
        expirationTask=Task { @MainActor in
            // Renew only a still-running batch, before it starts receiving
            // expired-lease failures. Idle/error states do not poll forever.
            let seconds=min(300,max(0,expiresAt.timeIntervalSinceNow-1))
            do {try await Task.sleep(for:.seconds(seconds))} catch {return}
            guard !Task.isCancelled,self.epoch==token,
                  expiresAt.timeIntervalSinceNow<=1,self.worker?.isRunning==true else{return}
            let refresh=self.refreshPolicy
            self.stop()
            refresh?()
        }
    }
    func request() {
        guard let expiresAt else { return }
        if expiresAt<=Date().addingTimeInterval(1) { refreshPolicy?(); return }
        worker?.request()
    }
    func retry() { refreshPolicy?() }
    func stop() {
        epoch=UUID();configurationTask?.cancel();configurationTask=nil
        expirationTask?.cancel();expirationTask=nil
        if let retiring=worker {
            retiring.cancel()
            let previous=retirementTask,token=UUID();retirementEpoch=token
            retirementTask=Task { @MainActor in
                await previous?.value
                await retiring.waitUntilIdle()
                if self.retirementEpoch==token {self.retirementTask=nil}
            }
        }
        worker=nil;identity=nil;expiresAt=nil;refreshPolicy=nil
    }
    func waitUntilConfigured() async {await configurationTask?.value}
}
private struct AutomaticActivitySyncEnvironmentKey: EnvironmentKey {
    static let defaultValue: AccountActivityAutomaticSyncCoordinator? = nil
}
extension EnvironmentValues {
    var soomAutomaticActivitySync: AccountActivityAutomaticSyncCoordinator? {
        get {self[AutomaticActivitySyncEnvironmentKey.self]}
        set {self[AutomaticActivitySyncEnvironmentKey.self]=newValue}
    }
}
private struct AccountActivityAutomaticSyncHost: View {
    @ObservedObject var privacy: AccountPrivacyModel
    @ObservedObject var coordinator: AccountActivityAutomaticSyncCoordinator
    @ObservedObject private var safety=CommunitySafetyStore.shared
    @EnvironmentObject private var storage: HealthAccountStorageController
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scene
    private var context: AccountActivitySyncContext? {
        guard ProfileOnlyPrivacyReleaseGate.productionReady,AccountActivitySyncReleaseGate.productionReady,
              !ReviewDemoMode.isActive,scene == .active,privacy.canContinue,
              let receipt=privacy.receipt,receipt.policyVersion==2,receipt.isSelected,
              let owner=storage.userID,owner==safety.viewerID,
              modelContext.container === storage.container,
              !HealthCloudJournal.isRetired(modelContext),HealthCloudJournal.accountID(for:modelContext)==owner else {return nil}
        return .init(ownerID:owner,scopeID:storage.scopeID,generation:safety.accountGeneration,retired:false)
    }
    private var identity:String? {
        guard let context,let revision=privacy.receipt?.revision else{return nil}
        return "\(context.ownerID):\(context.generation):\(revision):\(ObjectIdentifier(storage.container))"
    }
    var body: some View {
        Color.clear.frame(width:0,height:0).accessibilityHidden(true)
            .onChange(of:identity,initial:true) {_,_ in configure()}
            .task(id: identity) {
                // Details have their own consent and queue. Recheck them on a fresh
                // profile/foreground lease without coupling to source import success.
                guard identity != nil else { return }
                await WorkoutExistingDetailRefreshRetry.run(storage: storage)
            }
            .onChange(of:storage.dataRevision) {_,_ in coordinator.request()}
            .onReceive(NotificationCenter.default.publisher(for:HealthCloudJournal.didCommit)) {event in
                guard let owner=event.object as? UUID,owner==storage.userID else{return}
                coordinator.request()
            }
            .onDisappear {coordinator.stop()}
    }
    private func configure() {
        guard let identity,let expected=context,let receipt=privacy.receipt,
              let client=SupabaseClientProvider(environment:AuthEnvironmentLoader().load()).makeClient(),
              client.auth.currentSession?.user.id==expected.ownerID else {coordinator.stop();return}
        let expiration=Date().addingTimeInterval(300)
        let grant=AccountActivityStagingAuthorization(ownerID:expected.ownerID,
            evidenceReference:"profile-only-v2:\(receipt.revision)",earliestActivity:.distantPast,
            expiresAt:expiration,permitsOwnerPrivateStaging:true)
        let revision=receipt.revision
        coordinator.configure(identity:identity,expiresAt:expiration,refreshPolicy:{Task {await privacy.load()}}) {
            let current:()->AccountActivitySyncContext? = {
                guard self.privacy.receipt?.revision==revision,self.context==expected,
                      client.auth.currentSession?.user.id==expected.ownerID else{return nil}
                return expected
            }
            let transport=SupabaseAccountActivityStageTransport(client:client,currentContext:current,
                currentProfileRevision:{current() == nil ? nil : revision})
            let directory=storage.scopeDirectory.appendingPathComponent("activity-sync-v2",isDirectory:true)
            let engine=AccountActivitySyncCandidate(transport:transport,
                outbox:AccountActivityStageOutbox(directory:directory.appendingPathComponent("outbox",isDirectory:true)),
                authorization:{current() == nil ? nil : grant})
            return AccountActivityAutomaticSyncWorker(queue:AccountActivityAutomaticQueue(directory:directory),
                orchestrator:AccountActivitySyncOrchestrator(engine:engine),currentContext:current,
                snapshot:{try AccountActivityLocalSnapshot.read(context:modelContext,expected:expected)})
        }
    }
}

struct AccountActivityAutomaticSyncStatusView: View {
    @ObservedObject var coordinator: AccountActivityAutomaticSyncCoordinator
    var body: some View {
        if let worker=coordinator.worker {
            AutomaticActivityWorkerStatus(worker:worker,retry:coordinator.retry)
        } else if ProfileOnlyPrivacyReleaseGate.productionReady {
            Text("프로필 공개범위를 확인한 뒤 운동 자동 반영을 이어갑니다. 원본은 기기에 그대로 보관돼요.")
                .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
        }
    }
}
private struct AutomaticActivityWorkerStatus: View {
    @ObservedObject var worker:AccountActivityAutomaticSyncWorker
    let retry:()->Void
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text("운동 요약 자동 반영").font(.headline)
            if worker.isRunning {ProgressView("저장된 운동을 반영하는 중")}
            else if worker.pendingCount==0 && worker.rejectedCanonicalIDs.isEmpty && worker.lastError==nil {
                Text("이 기기에 저장된 운동 요약의 반영을 확인했어요.").font(.footnote)
            } else {
                Text("대기 \(worker.pendingCount)개 · 확인 필요 \(worker.rejectedCanonicalIDs.count)개").font(.footnote)
                Text("기록 원본은 유지돼요. 연결과 공개범위를 다시 확인한 뒤 이어서 반영할 수 있어요.").font(.footnote)
                Button("자동 반영 다시 확인",action:retry).accessibilityIdentifier("activity.autoSync.retry")
            }
            Text("다른 서비스에만 있는 이전 운동은 해당 연결 화면에서 가져온 뒤 반영해요.")
                .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
        }.accessibilityIdentifier("activity.autoSync.status")
    }
}

/// Source collection does not depend on social verification or visiting a tab.
/// Each source retains its own OS permission and explicit import-range setting.
private struct AccountActivitySourceImportHost: View {
    @EnvironmentObject private var storage:HealthAccountStorageController
    @EnvironmentObject private var auth:AuthViewModel
    @Environment(\.scenePhase) private var scene
    private var activeIdentity:String? {
        guard ProfileOnlyPrivacyReleaseGate.productionReady,!ReviewDemoMode.isActive,scene == .active,
              auth.session.currentUser?.authProvider == .supabase,
              let owner=storage.userID,owner==auth.session.currentUser?.id else{return nil}
        return "\(owner):\(ObjectIdentifier(storage.container))"
    }
    var body:some View {
        Color.clear.frame(width:0,height:0).accessibilityHidden(true)
            .task(id:activeIdentity) {
                guard activeIdentity != nil else{return}
                async let health:Void=HealthKitAutomaticImport.run(storage:storage)
                async let google:Void=GoogleHealthAutomaticImport.run(storage:storage)
                _ = await (health,google)
            }
    }
}


/// Detailed measurements remain a separate, existing-consent-only queue.
/// A successful summary batch must not hide a pending detail refresh.
struct WorkoutExistingDetailRefreshStatusView: View {
    @EnvironmentObject private var storage: HealthAccountStorageController
    @State private var pendingCount = 0
    @State private var countIdentity: String?
    @State private var retrying = false
    @State private var retryTask: Task<Void, Never>?
    private var identity: String { "\(storage.userID?.uuidString ?? "none"):\(storage.scopeID):\(ObjectIdentifier(storage.container))" }
    var body: some View {
        Group {
            if ProfileOnlyPrivacyReleaseGate.productionReady && !ReviewDemoMode.isActive && countIdentity == identity && (pendingCount > 0 || retrying) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("기존 공유 상세 보완").font(.headline)
                    if retrying { ProgressView("상세 보완 상태를 확인하는 중") }
                    Text("상세 보완 대기 \(pendingCount)개").font(.footnote)
                    Text("운동 요약과 별도로 확인해요. 이미 동의하고 공유한 상세만 보완하며, 새 공유 동의나 공개범위는 만들지 않아요. 원본은 그대로 유지됩니다.")
                        .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                    Button("상세 보완 다시 확인") { retry() }
                        .disabled(retrying).accessibilityIdentifier("activity.detailRefresh.retry")
                }.accessibilityIdentifier("activity.detailRefresh.status")
            }
        }
        .onChange(of: identity, initial: true) { _, _ in
            retryTask?.cancel(); retryTask = nil; retrying = false; refreshCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: WorkoutExistingDetailRefreshPending.didChange)) { event in
            guard event.object as? UUID == storage.userID else { return }
            refreshCount()
        }
        .onDisappear { retryTask?.cancel(); retryTask = nil; retrying = false }
    }
    private func refreshCount() {
        countIdentity = identity
        pendingCount = storage.userID.map { WorkoutExistingDetailRefreshPending.count(ownerID: $0) } ?? 0
    }
    private func retry() {
        guard !retrying, storage.userID != nil else { return }
        let expected = identity
        retrying = true
        retryTask = Task { @MainActor in
            await WorkoutExistingDetailRefreshRetry.run(storage: storage)
            guard !Task.isCancelled, identity == expected else { return }
            refreshCount(); retrying = false; retryTask = nil
        }
    }
}
