import SwiftUI
import SwiftData

@main
struct SOOMApp: App {
    @StateObject private var dashboardViewModel: DashboardViewModel
    @StateObject private var communityViewModel: CommunityViewModel

    init() {
        let harness = MockWorkoutHarness()
        _dashboardViewModel = StateObject(wrappedValue: DashboardViewModel(harness: harness))
        _communityViewModel = StateObject(wrappedValue: CommunityViewModel(harness: harness))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(dashboardViewModel)
                .environmentObject(communityViewModel)
        }
        .modelContainer(for: [
            CheckInRecord.self,
            DailyRecoverySnapshotRecord.self,
            UnifiedWorkoutRecord.self,
            PersistedWorkoutRoute.self
        ])
    }
}
