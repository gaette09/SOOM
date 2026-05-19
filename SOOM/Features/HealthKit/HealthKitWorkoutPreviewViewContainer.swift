import SwiftUI

struct HealthKitWorkoutPreviewViewContainer: View {
    var body: some View {
        HealthKitWorkoutPreviewView(
            viewModel: HealthKitWorkoutPreviewViewModel(
                fetcher: HealthKitWorkoutFetcher()
            )
        )
    }
}
