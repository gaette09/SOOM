import SwiftUI
import SwiftData

@main
struct SOOMApp: App {
    @StateObject private var dashboardViewModel: DashboardViewModel
    @StateObject private var communityViewModel: CommunityViewModel
    @StateObject private var authViewModel: AuthViewModel
    @StateObject private var rootAuthBootstrap: RootAuthBootstrap
    private let authCallbackHandler: AuthCallbackHandler

    init() {
        let harness = MockWorkoutHarness()
        let authEnvironment = AuthEnvironmentLoader().load()
        let remoteAuthProvider = SupabaseAuthProvider(
            configuration: SupabaseAuthConfiguration.from(environment: authEnvironment)
        )
        let authViewModel = AuthViewModel(
            remoteSessionLoader: remoteAuthProvider,
            appleSignInHandler: remoteAuthProvider.signInWithAppleCredential
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
            RootTabView()
                .environmentObject(dashboardViewModel)
                .environmentObject(communityViewModel)
                .environmentObject(authViewModel)
                .task {
                    await rootAuthBootstrap.bootstrap()
                }
                .onOpenURL { url in
                    Task {
                        let result = await authCallbackHandler.handle(url: url)
                        authViewModel.handleAuthCallbackResult(result)
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
