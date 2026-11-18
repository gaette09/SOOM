import SwiftUI

struct HealthKitSettingsViewContainer: View {
    var body: some View {
        if ReviewDemoMode.isActive {
            ReviewDemoIntegrationView(title: "Apple 건강 연결")
        } else {
            HealthKitSettingsView(
                viewModel: HealthKitSettingsViewModel(manager: HealthKitManager())
            )
        }
    }
}
