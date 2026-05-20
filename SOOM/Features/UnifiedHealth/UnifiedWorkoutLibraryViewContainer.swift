import SwiftData
import SwiftUI

struct UnifiedWorkoutLibraryViewContainer: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        UnifiedWorkoutLibraryView(
            viewModel: UnifiedWorkoutLibraryViewModel(
                store: SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
            )
        )
    }
}
