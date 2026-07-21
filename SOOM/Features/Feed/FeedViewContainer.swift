import SwiftData
import SwiftUI

struct FeedViewContainer: View {
    @Environment(\.modelContext) private var modelContext
    @State private var readModel = FeedReadModel.loading

    var body: some View {
        FeedView(
            items: readModel.items,
            weeklySnapshot: readModel.weeklySnapshot,
            recoveryInsight: readModel.recoveryInsight
        )
        .task {
            let viewModel = makeProductionViewModel()
            await viewModel.load()
            readModel = viewModel.readModel
        }
    }

    private func makeProductionViewModel() -> FeedViewModel {
        let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        return FeedViewModel(
            feedLoader: FeedDataSource(draftStore: FileFeedShareDraftStore.live),
            weeklyProgressProvider: UnifiedWorkoutWeeklyProgressProvider(store: store),
            recoveryPreviewProvider: UnifiedWorkoutRecoveryPreviewProvider(store: store)
        )
    }
}
