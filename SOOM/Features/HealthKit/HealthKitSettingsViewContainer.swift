import SwiftUI

struct HealthKitSettingsViewContainer: View {
    var body: some View {
        HealthKitSettingsView(
            viewModel: HealthKitSettingsViewModel(manager: HealthKitManager())
        )
    }
}
