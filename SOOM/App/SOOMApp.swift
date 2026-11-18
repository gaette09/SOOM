import SwiftUI
import SwiftData
import AuthenticationServices

@main
struct SOOMApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dashboardViewModel: DashboardViewModel
    @State private var showingOnboarding = false
    @StateObject private var communityViewModel: CommunityViewModel
    @StateObject private var authViewModel: AuthViewModel
    @StateObject private var rootAuthBootstrap: RootAuthBootstrap
    @StateObject private var healthStorageBootstrap: HealthStorageBootstrap
    @StateObject private var reviewDemo = ReviewDemoController.shared
    @State private var hasCompletedOnboarding: Bool
    private let authCallbackHandler: AuthCallbackHandler
    private let remoteAuthProvider: SupabaseAuthProvider

    private let deviceTokenReceiptHandler: DeviceTokenReceiptHandler
    private let notificationPermissionRequester: any NotificationPermissionRequesting = NotificationPermissionRequester()
    @StateObject private var notificationDeepLinkRouter = NotificationDeepLinkRouter()
    @ObservedObject private var badgeSafety = CommunitySafetyStore.shared

    private var notificationBadgeScope: String {
        "\(rootAuthBootstrap.state):\(authViewModel.session.currentUser?.id.uuidString ?? "guest"):\(badgeSafety.accountGeneration):\(badgeSafety.revision):\(badgeSafety.canUseSocial):\(ReviewDemoMode.isActive)"
    }

    @MainActor private func refreshNotificationBadge() async {
        guard !ReviewDemoMode.isActive, rootAuthBootstrap.state == .completed else { return }
        let user = authViewModel.session.currentUser
        let scope = user?.authProvider == .supabase
            ? "\(user!.id):\(badgeSafety.accountGeneration)" : nil
        let canFetch = badgeSafety.canUseSocial && badgeSafety.viewerID == user?.id
        NotificationBadgeStore.shared.bind(scope: scope,
            fetcher: canFetch ? remoteAuthProvider.underlyingClient.map { SupabaseFeedRemoteClient(client: $0) } : nil)
        await NotificationBadgeStore.shared.refresh()
    }

    init() {
        _ = WatchWorkoutCompanion.shared
        _hasCompletedOnboarding = State(initialValue: OnboardingStateStore.shared.hasCompletedOnboarding)
        let harness = MockWorkoutHarness()
        let authEnvironment = AuthEnvironmentLoader().load()
        let remoteAuthProvider = SupabaseAuthProvider(
            configuration: SupabaseAuthConfiguration.from(environment: authEnvironment)
        )

        self.remoteAuthProvider = remoteAuthProvider
        SupabaseClientProvider.installAppClient(
            remoteAuthProvider.underlyingClient,
            configuration: SupabaseAuthConfiguration.from(environment: authEnvironment)
        )
        CommunitySafetyStore.shared.configure(client: remoteAuthProvider.underlyingClient)
        _healthStorageBootstrap = StateObject(wrappedValue: HealthStorageBootstrap(
            remote: remoteAuthProvider.underlyingClient.map { SupabaseHealthCloudRemote(client: $0) }
        ))

        // Reuses remoteAuthProvider's own client rather than making a new
        // one — a second SupabaseClient would have its own independent
        // in-memory Auth session cache (Keychain storage is shared, but
        // the session isn't), so device token registration would never
        // see a login this app's own sign-in flow just completed.
        let deviceTokenStore = DeviceTokenStore.shared
        let deviceTokenRegistrar: any DeviceTokenRegistering
        if let supabaseClient = remoteAuthProvider.underlyingClient {
            deviceTokenRegistrar = SupabaseDeviceTokenRegistrar(client: supabaseClient)
        } else {
            deviceTokenRegistrar = NoopDeviceTokenRegistrar()
        }
        self.deviceTokenReceiptHandler = DeviceTokenReceiptHandler(store: deviceTokenStore, registrar: deviceTokenRegistrar)
        let signOutCleanup = SignOutDeviceTokenCleanup(registrar: deviceTokenRegistrar, store: deviceTokenStore)

        let authViewModel = AuthViewModel(
            remoteSessionLoader: remoteAuthProvider,
            appleSignInHandler: remoteAuthProvider.signInWithAppleCredential,
            remoteSignOutHandler: signOutCleanup.wrapping(remoteAuthProvider.signOut),
            remoteDisplayNameHandler: remoteAuthProvider.updateDisplayName,
            remoteAvatarHandler: remoteAuthProvider.updateAvatar,
            remoteAccountDeleteForUserHandler: remoteAuthProvider.deleteAccount(expectedUserID:),
            appleCredentialRevocationHandler: { userID in
                await remoteAuthProvider.endSessionAfterAppleCredentialRevocation(
                    expectedUserID: userID,
                    beforeSignOut: { await signOutCleanup.deleteCachedDeviceToken() }
                )
            }
        )
        _dashboardViewModel = StateObject(wrappedValue: DashboardViewModel(harness: harness))
        _communityViewModel = StateObject(wrappedValue: CommunityViewModel(harness: harness))
        _authViewModel = StateObject(wrappedValue: authViewModel)
        _rootAuthBootstrap = StateObject(wrappedValue: RootAuthBootstrap(authViewModel: authViewModel))
        self.authCallbackHandler = AuthCallbackHandler(
            environment: authEnvironment,
            sessionHandler: remoteAuthProvider
        )
        #if DEBUG && targetEnvironment(simulator)
        if (ProcessInfo.processInfo.environment["SOOM_SKELETON_QA"] == "1" ||
            ProcessInfo.processInfo.environment["SOOM_DETAIL_MOTION_QA"] == "1" ||
            ProcessInfo.processInfo.environment["SOOM_DETAIL_NORMAL_LAYOUT_QA"] == "1"),
           ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1" {
            ReviewDemoController.shared.start()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                if !hasCompletedOnboarding && reviewDemo.runtime == nil {
                    OptionalOnboardingEntryView(
                        onStartDemo: { reviewDemo.start() },
                        onShowGuide: { showingOnboarding = true }
                    )
                }
                Group {
                if let runtime = reviewDemo.runtime {
                    ReviewDemoRootView(runtime: runtime)
                } else if rootAuthBootstrap.state == .timedOut {
                    ContentUnavailableView {
                        Label("계정 확인이 지연되고 있어요", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("저장된 기록은 그대로 보관되어 있어요. 잠시 후 다시 시도해 주세요.")
                    } actions: {
                        Button("다시 시도") {
                            Task {
                                await rootAuthBootstrap.retry()
                                guard !ReviewDemoMode.isActive, rootAuthBootstrap.state == .completed else { return }
                                CommunitySafetyStore.shared.setViewerID(authViewModel.session.currentUser?.id)
                                await authViewModel.refreshAppleCredentialState()
                            }
                        }
                        .accessibilityIdentifier("authBootstrap.retry")
                    }
                    .accessibilityIdentifier("authBootstrap.timedOut")
                } else if let storage = healthStorageBootstrap.controller {
                    HealthAccountRootGate(storage: storage, authReady: rootAuthBootstrap.state == .completed) {
                        if let owner = authViewModel.session.currentUser?.id {
                            AccountPrivacyRootGate(owner: owner, onboardingComplete: hasCompletedOnboarding) { RootTabView() }.id(owner)
                        } else { RootTabView() }
                    }
                } else {
                    ContentUnavailableView {
                        Label("기록 저장 공간을 열 수 없어요", soomIcon: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(healthStorageBootstrap.errorMessage ?? "다시 시도해 주세요.")
                        if let demoError = reviewDemo.errorMessage {
                            Text(demoError).foregroundStyle(SOOMColor.warning)
                                .accessibilityIdentifier("reviewDemo.startError")
                        }
                    } actions: {
                        Button("다시 시도") { healthStorageBootstrap.open() }
                        if ReviewDemoAccessPolicy.canStart {
                            Button("데모 체험 / Try Demo") { reviewDemo.start() }
                        }
                    }
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(WorkoutRootViewport(allowsStatusBarOverflow: hasCompletedOnboarding || reviewDemo.runtime != nil))
            }
                .onChange(of: reviewDemo.runtime != nil) { _, isDemo in
                    if !isDemo {
                        CommunitySafetyStore.shared.setViewerID(authViewModel.session.currentUser?.id)
                        deviceTokenReceiptHandler.loginStateChanged(currentUser: authViewModel.session.currentUser)
                    }
                }
                .sheet(isPresented: $showingOnboarding) {
                    OnboardingView {
                        OnboardingStateStore.shared.markOnboardingCompleted()
                        hasCompletedOnboarding = true
                        showingOnboarding = false
                    }
                }
                .environmentObject(dashboardViewModel)
                .environmentObject(communityViewModel)
                .environmentObject(authViewModel)
                .environmentObject(notificationDeepLinkRouter)
                .task(id: notificationBadgeScope) { await refreshNotificationBadge() }
                .onReceive(NotificationCenter.default.publisher(for: .soomNotificationReceiptsChanged)) { _ in
                    Task { await refreshNotificationBadge() }
                }
                .task {
                    guard !ReviewDemoMode.isActive else { return }
                    await rootAuthBootstrap.bootstrap()
                    guard !ReviewDemoMode.isActive, rootAuthBootstrap.state == .completed else { return }
                    CommunitySafetyStore.shared.setViewerID(authViewModel.session.currentUser?.id)
                    await authViewModel.refreshAppleCredentialState()
                }
                .task(id: authViewModel.session.currentUser?.id) {
                    let user=authViewModel.session.currentUser
                    let id = !ReviewDemoMode.isActive && user?.authProvider == .supabase ? user?.id:nil
                    let service: (any EventNotificationServing)? = id.flatMap { owner in remoteAuthProvider.underlyingClient.map { SupabaseEventNotifications(client:$0,userID:owner) } }
                    EventNotificationCenter.shared.bind(user:id,service:service)
                    if EventNotificationFeature.enabled, let id, PushRegistrationStatus.shared.state == .registered,
                       let token=DeviceTokenStore.shared.cachedTokenHex {
                        await EventNotificationCenter.shared.registrationSucceeded(token:token,userID:id)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && !ReviewDemoMode.isActive {
                        Task {
                            // Settings can change while this view stays mounted in the background.
                            await notificationPermissionRequester.refreshPermissionStatus()
                            await rootAuthBootstrap.bootstrap()
                            guard !ReviewDemoMode.isActive, rootAuthBootstrap.state == .completed else { return }
                            await authViewModel.refreshAppleCredentialState()
                            await refreshNotificationBadge()
                            if EventNotificationFeature.enabled, let user=authViewModel.session.currentUser, user.authProvider == .supabase {
                                if PushRegistrationStatus.shared.state == .registered, let token=DeviceTokenStore.shared.cachedTokenHex {
                                    await EventNotificationCenter.shared.registrationSucceeded(token:token,userID:user.id)
                                }
                            }
                            await healthStorageBootstrap.controller?.syncNow()
                        }
                    }
                }
                .task {
                    await remoteAuthProvider.observeSessionTermination(onEnded: authViewModel.remoteSessionDidEnd)
                }
                .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
                    guard !ReviewDemoMode.isActive else { return }
                    Task { await authViewModel.refreshAppleCredentialState() }
                }
                .onOpenURL { url in
                    guard !ReviewDemoMode.isActive else { return }
                    if url.scheme == "soom-workout", url.host == "resume" {
                        WatchWorkoutCompanion.shared.shouldOpenWorkout = true
                        return
                    }
                    Task {
                        await authViewModel.handleAuthCallback {
                            await authCallbackHandler.handle(url: url)
                        }
                    }
                }
                .onChange(of: authViewModel.session.currentUser?.id) { _, _ in
                    guard !ReviewDemoMode.isActive else { return }
                    CommunitySafetyStore.shared.setViewerID(authViewModel.session.currentUser?.id)
                    WatchWorkoutCompanion.shared.bind(scope: authViewModel.session.currentUser?.id.uuidString.lowercased() ?? "guest")
                    deviceTokenReceiptHandler.loginStateChanged(currentUser: authViewModel.session.currentUser)
                    Task { await authViewModel.refreshAppleCredentialState() }
                }
                .task {
                    appDelegate.eventCanPresent = { event in
                        !ReviewDemoMode.isActive && authViewModel.session.currentUser?.authProvider == .supabase
                            && authViewModel.session.currentUser?.id == event.recipientID && EventNotificationCenter.shared.accepts(event)
                    }
                    appDelegate.eventReceived = { event,tapped in Task { @MainActor in
                        await rootAuthBootstrap.bootstrap()
                        guard !ReviewDemoMode.isActive, authViewModel.session.currentUser == nil ||
                            (authViewModel.session.currentUser?.authProvider == .supabase && authViewModel.session.currentUser?.id == event.recipientID) else {return}
                        await EventNotificationCenter.shared.handle(event,tapped:tapped)
                    } }
                    if let event=appDelegate.consumePendingEventTap() {appDelegate.eventReceived?(event,true)}
                    appDelegate.shouldPresentRemotePush = { [authViewModel] payload in
                        guard !ReviewDemoMode.isActive,
                              let user = authViewModel.session.currentUser,
                              user.authProvider == .supabase,
                              payload.recipientID == user.id else { return false }
                        let safety = CommunitySafetyStore.shared
                        return safety.viewerID == user.id && safety.canUseSocial
                    }
                    appDelegate.onDidReceiveVisiblePush = { Task { await refreshNotificationBadge() } }
                    appDelegate.onDidReceiveDeviceToken = { [deviceTokenReceiptHandler] token in
                        let hex = token.map { String(format: "%02x", $0) }.joined()
                        Task { @MainActor in
                            // APNs may rotate the token during a demo. Cache it
                            // now, but defer registration until the real session
                            // is visible again when the demo exits.
                            deviceTokenReceiptHandler.received(tokenHex: hex,
                                currentUser: ReviewDemoMode.isActive ? nil : authViewModel.session.currentUser)
                        }
                    }
                    appDelegate.onDidFailToRegister = { [deviceTokenReceiptHandler] _ in
                        Task { @MainActor in deviceTokenReceiptHandler.registrationFailed() }
                    }
                    appDelegate.onHealthWorkoutUpdate = { [healthStorageBootstrap] completion in
                        Task { @MainActor in
                            if !ReviewDemoMode.isActive, let storage = healthStorageBootstrap.controller,
                               storage.userID == authViewModel.session.currentUser?.id {
                                await HealthKitAutomaticImport.run(storage: storage)
                            }
                            completion()
                        }
                    }
                    appDelegate.onGoogleHealthEvent = { [healthStorageBootstrap] completion in
                        Task { @MainActor in
                            if !ReviewDemoMode.isActive, let storage = healthStorageBootstrap.controller,
                               storage.userID == authViewModel.session.currentUser?.id {
                                await GoogleHealthAutomaticImport.run(storage: storage)
                                completion(.newData)
                            } else { completion(.noData) }
                        }
                    }
                    await notificationPermissionRequester.registerForBackgroundUpdates()
                }
                .task {
                    appDelegate.onDidReceiveNotificationTap = { [notificationDeepLinkRouter, rootAuthBootstrap] postId in
                        Task { @MainActor in
                            // A tap can race auth session restore (worst case:
                            // cold launch). fetchPost requires an authenticated
                            // role per RLS, so routing before the session is
                            // back would silently resolve to "not found" even
                            // for a post the user can see. bootstrap() is a
                            // no-op once already completed.
                            await rootAuthBootstrap.bootstrap()
                            guard !ReviewDemoMode.isActive else { return }
                            notificationDeepLinkRouter.routeToPost(id: postId)
                        }
                    }
                    appDelegate.nativePushReceived = { [notificationDeepLinkRouter, rootAuthBootstrap, authViewModel] payload in
                        Task { @MainActor in
                            await rootAuthBootstrap.bootstrap()
                            guard !ReviewDemoMode.isActive, authViewModel.session.currentUser?.authProvider == .supabase else { return }
                            let safety = CommunitySafetyStore.shared
                            notificationDeepLinkRouter.routeNativePush(payload,currentUserID:authViewModel.session.currentUser?.id,
                                previewAllowed:safety.canUseActivityPreview && safety.viewerID == payload.recipientID, generation:safety.accountGeneration)
                        }
                    }
                    if let pending=appDelegate.consumePendingNativePush() { appDelegate.nativePushReceived?(pending) }
                    appDelegate.onDidReceivePushTap = { [notificationDeepLinkRouter, rootAuthBootstrap, authViewModel] payload in
                        Task { @MainActor in
                            await rootAuthBootstrap.bootstrap()
                            guard !ReviewDemoMode.isActive,authViewModel.session.currentUser?.authProvider == .supabase else { return }
                            notificationDeepLinkRouter.routePush(payload,currentUserID:authViewModel.session.currentUser?.id)
                        }
                    }
                    if let pending=appDelegate.consumePendingPushTap() { appDelegate.onDidReceivePushTap?(pending) }
                    // Cold launch: iOS may have delivered the tap before this
                    // .task ran (see AppDelegate.pendingNotificationPostId).
                    if let pendingPostId = appDelegate.pendingNotificationPostId {
                        await rootAuthBootstrap.bootstrap()
                        guard !ReviewDemoMode.isActive else { return }
                        notificationDeepLinkRouter.routeToPost(id: pendingPostId)
                    }
                }
        }
    }
}

/// Keep the optional entry usable without occupying the small-screen content
/// area at accessibility text sizes. Spoken names retain the complete action.
private struct OptionalOnboardingEntryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onStartDemo: () -> Void
    let onShowGuide: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            if ReviewDemoAccessPolicy.canStart {
                Button(action: onStartDemo) {
                    if dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "play.rectangle").font(.system(size: 24)).frame(width: 44, height: 44)
                    } else {
                        Text("데모 체험 / Try Demo").font(.footnote).frame(minHeight: 44)
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("데모 체험 / Try Demo")
                .accessibilityIdentifier("reviewDemo.start")
            }
            Button(action: onShowGuide) {
                if dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "questionmark.circle").font(.system(size: 24)).frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Text("앱 안내 보기").font(.footnote).frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .accessibilityLabel("앱 안내 보기")
            .accessibilityIdentifier("onboarding.optional")
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(SOOMColor.background)
    }
}
