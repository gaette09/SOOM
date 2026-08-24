import SwiftUI
import SwiftData

@main
struct SOOMApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dashboardViewModel: DashboardViewModel
    @StateObject private var communityViewModel: CommunityViewModel
    @StateObject private var authViewModel: AuthViewModel
    @StateObject private var rootAuthBootstrap: RootAuthBootstrap
    @State private var hasCompletedOnboarding: Bool
    private let authCallbackHandler: AuthCallbackHandler

    private let deviceTokenReceiptHandler: DeviceTokenReceiptHandler
    private let notificationPermissionRequester: any NotificationPermissionRequesting = NotificationPermissionRequester()
    @StateObject private var notificationDeepLinkRouter = NotificationDeepLinkRouter()

    init() {
        _hasCompletedOnboarding = State(initialValue: OnboardingStateStore.shared.hasCompletedOnboarding)
        let harness = MockWorkoutHarness()
        let authEnvironment = AuthEnvironmentLoader().load()
        let remoteAuthProvider = SupabaseAuthProvider(
            configuration: SupabaseAuthConfiguration.from(environment: authEnvironment)
        )

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
            remoteAccountDeleteHandler: remoteAuthProvider.deleteAccount
        )
        _dashboardViewModel = StateObject(wrappedValue: DashboardViewModel(harness: harness))
        _communityViewModel = StateObject(wrappedValue: CommunityViewModel(harness: harness))
        _authViewModel = StateObject(wrappedValue: authViewModel)
        _rootAuthBootstrap = StateObject(wrappedValue: RootAuthBootstrap(authViewModel: authViewModel))
        self.authCallbackHandler = AuthCallbackHandler(
            environment: authEnvironment,
            sessionHandler: remoteAuthProvider
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    RootTabView()
                } else {
                    OnboardingView {
                        OnboardingStateStore.shared.markOnboardingCompleted()
                        hasCompletedOnboarding = true
                    }
                }
            }
                .environmentObject(dashboardViewModel)
                .environmentObject(communityViewModel)
                .environmentObject(authViewModel)
                .environmentObject(notificationDeepLinkRouter)
                .task {
                    await rootAuthBootstrap.bootstrap()
                }
                .onOpenURL { url in
                    Task {
                        let result = await authCallbackHandler.handle(url: url)
                        authViewModel.handleAuthCallbackResult(result)
                    }
                }
                .onChange(of: authViewModel.session.currentUser?.id) { _, _ in
                    deviceTokenReceiptHandler.loginStateChanged(currentUser: authViewModel.session.currentUser)
                }
                .task {
                    appDelegate.onDidReceiveDeviceToken = { [deviceTokenReceiptHandler] token in
                        let hex = token.map { String(format: "%02x", $0) }.joined()
                        print("[AppDelegate] APNs device token: \(hex)")
                        Task { @MainActor in
                            deviceTokenReceiptHandler.received(tokenHex: hex, currentUser: authViewModel.session.currentUser)
                        }
                    }
                    await notificationPermissionRequester.reregisterIfAlreadyAuthorized()
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
                            notificationDeepLinkRouter.routeToPost(id: postId)
                        }
                    }
                    // Cold launch: iOS may have delivered the tap before this
                    // .task ran (see AppDelegate.pendingNotificationPostId).
                    if let pendingPostId = appDelegate.pendingNotificationPostId {
                        await rootAuthBootstrap.bootstrap()
                        notificationDeepLinkRouter.routeToPost(id: pendingPostId)
                    }
                }
        }
        .modelContainer(for: [
            CheckInRecord.self,
            DailyRecoverySnapshotRecord.self,
            UnifiedWorkoutRecord.self,
            PersistedWorkoutRoute.self
        ])
    }
}
