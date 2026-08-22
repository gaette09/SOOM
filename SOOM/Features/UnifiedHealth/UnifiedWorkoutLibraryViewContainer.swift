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
            detailRouteContextProvider: WorkoutDetailRouteContextProvider(store: routeStore),
            relativeEffortHistoryProvider: SwiftDataRelativeEffortHistoryProvider(store: store),
            achievementHistoryProvider: SwiftDataWorkoutAchievementHistoryProvider(workoutStore: store, routeStore: routeStore),
            fitnessTrendHistoryProvider: SwiftDataFitnessTrendHistoryProvider(store: store),
            gpxRouteAttachmentService: GPXRouteAttachmentService(
                workoutStore: store,
                routeStore: routeStore
            ),
            fitRouteAttachmentService: FITRouteAttachmentService(
                workoutStore: store,
                routeStore: routeStore
            ),
            tcxRouteAttachmentService: TCXRouteAttachmentService(
                workoutStore: store,
                routeStore: routeStore
            ),
            companionUpdateService: WorkoutCompanionUpdateService(workoutStore: store)
        )
    }
}
