import SwiftData
import SwiftUI

struct UnifiedWorkoutLibraryViewContainer: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        let routeStore = SwiftDataWorkoutRoutePersistenceStore(modelContext: modelContext)
        let routeCandidateProvider = PersistedRouteCandidateProvider(store: routeStore)
        UnifiedWorkoutLibraryView(
            viewModel: UnifiedWorkoutLibraryViewModel(store: store),
            similarCandidateProvider: SimilarWorkoutCandidateProvider(
                store: store,
                persistedRouteProvider: routeCandidateProvider
            ),
            detailRouteContextProvider: WorkoutDetailRouteContextProvider(store: routeStore)
        )
    }
}
