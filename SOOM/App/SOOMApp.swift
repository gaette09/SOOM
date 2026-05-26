import SwiftUI
import SwiftData

@main
struct SOOMApp: App {
    @StateObject private var dashboardViewModel: DashboardViewModel
    @StateObject private var communityViewModel: CommunityViewModel
    private let authCallbackHandler: AuthCallbackHandler

    init() {
        let harness = MockWorkoutHarness()
        let authEnvironment = AuthEnvironmentLoader().load()
        let remoteAuthProvider = SupabaseAuthProvider(
            configuration: SupabaseAuthConfiguration.from(environment: authEnvironment)
        )
        _dashboardViewModel = StateObject(wrappedValue: DashboardViewModel(harness: harness))
        _communityViewModel = StateObject(wrappedValue: CommunityViewModel(harness: harness))
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
                .onOpenURL { url in
                    Task {
                        _ = await authCallbackHandler.handle(url: url)
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
