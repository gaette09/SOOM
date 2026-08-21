import SwiftData
import SwiftUI

struct FeedViewContainer: View {
    @Environment(\.modelContext) private var modelContext
    @State private var readModel = FeedReadModel.loading

    var body: some View {
        FeedView(
            items: readModel.items,
            weeklySnapshot: readModel.weeklySnapshot,
            recoveryInsight: readModel.recoveryInsight,
            streak: readModel.streak
        )
        .task {
            let viewModel = makeProductionViewModel()
            await viewModel.load()
            readModel = viewModel.readModel
        }
    }

    private func makeProductionViewModel() -> FeedViewModel {
        let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        let clientProvider = SupabaseClientProvider(environment: AuthEnvironmentLoader().load())
        let remoteClient = clientProvider.makeClient().map(SupabaseFeedRemoteClient.init(client:))

        return FeedViewModel(
            feedLoader: FeedDataSource(
                remoteRepository: SupabaseFeedRepository(
                    clientProvider: clientProvider,
                    remoteFetcher: remoteClient,
                    profileFetcher: remoteClient
                ),
                draftStore: FileFeedShareDraftStore.live
            ),
            weeklyProgressProvider: UnifiedWorkoutWeeklyProgressProvider(store: store),
            recoveryPreviewProvider: UnifiedWorkoutRecoveryPreviewProvider(store: store),
            streakDatesProvider: UnifiedWorkoutStoreStreakDatesProvider(store: store)
        )
    }
}
