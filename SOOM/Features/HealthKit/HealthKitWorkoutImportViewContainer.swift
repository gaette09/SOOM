import SwiftData
import SwiftUI

struct HealthKitWorkoutImportViewContainer: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HealthKitWorkoutImportView(
            viewModel: HealthKitWorkoutImportViewModel(
                pipeline: HealthKitWorkoutImportPipeline(
                    workoutFetcher: HealthKitWorkoutFetcher(),
                    store: SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
                )
            )
        )
    }
}
