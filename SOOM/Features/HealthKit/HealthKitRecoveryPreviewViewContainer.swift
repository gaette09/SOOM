import SwiftUI

struct HealthKitRecoveryPreviewViewContainer: View {
    var body: some View {
        if ReviewDemoMode.isActive {
            ReviewDemoIntegrationView(title: "Apple 건강 회복 분석")
        } else {
            HealthKitRecoveryPreviewView(
                viewModel: HealthKitRecoveryPreviewViewModel()
            )
        }
    }
}
