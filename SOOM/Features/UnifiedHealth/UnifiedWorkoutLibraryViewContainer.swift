import SwiftData
import SwiftUI

struct UnifiedWorkoutLibraryViewContainer: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        UnifiedWorkoutLibraryView(
            viewModel: UnifiedWorkoutLibraryViewModel(store: store),
            similarCandidateProvider: SimilarWorkoutCandidateProvider(store: store)
        )
    }
}
