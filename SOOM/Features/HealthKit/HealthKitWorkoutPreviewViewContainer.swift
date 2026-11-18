import SwiftUI

struct HealthKitWorkoutPreviewViewContainer: View {
    var body: some View {
        if ReviewDemoMode.isActive {
            ReviewDemoIntegrationView(title: "Apple 건강 운동 미리보기")
        } else {
            HealthKitWorkoutPreviewView(
                viewModel: HealthKitWorkoutPreviewViewModel(
                    fetcher: HealthKitWorkoutFetcher()
                )
            )
        }
    }
}
