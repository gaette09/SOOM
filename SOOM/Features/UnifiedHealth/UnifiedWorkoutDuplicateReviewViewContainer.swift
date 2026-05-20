import SwiftData
import SwiftUI

struct UnifiedWorkoutDuplicateReviewViewContainer: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        UnifiedWorkoutDuplicateReviewView(
            viewModel: UnifiedWorkoutDuplicateReviewViewModel(
                store: SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
            )
        )
    }
}
