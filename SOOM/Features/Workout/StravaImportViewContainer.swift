import SwiftData
import SwiftUI

struct StravaImportViewContainer: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        StravaImportView(
            viewModel: StravaImportViewModel(
                pipeline: StravaImportPipeline(
                    store: SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
                )
            )
        )
    }
}
