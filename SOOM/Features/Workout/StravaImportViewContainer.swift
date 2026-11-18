import SwiftData
import SwiftUI

struct StravaImportViewContainer: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var storage: HealthAccountStorageController

    var body: some View {
        if ReviewDemoMode.isActive {
            ReviewDemoIntegrationView(title: "Strava ZIP")
        } else {
            StravaImportView(
                viewModel: StravaImportViewModel(
                    pipeline: StravaImportPipeline(
                        store: SwiftDataUnifiedWorkoutStore(modelContext: modelContext),
                        routeStore: SwiftDataWorkoutRoutePersistenceStore(modelContext: modelContext),
                        autoPublishNewWorkouts: ImportedWorkoutPublication.usesLegacyPublication && storage.autoPublishImportedWorkouts, pendingAudience: storage.defaultWorkoutAudience
                    ),
                    publication: ImportedWorkoutPublication(context: modelContext, storage: storage)
                )
            )
        }
    }
}
