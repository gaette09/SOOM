import SwiftData
import SwiftUI

struct FeedViewContainer: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: FeedViewModel?
    @State private var readModel = FeedReadModel.loading

    var body: some View {
        FeedView(
            items: readModel.items,
            weeklySnapshot: readModel.weeklySnapshot,
            recoveryInsight: readModel.recoveryInsight,
            streak: readModel.streak,
            onToggleCheer: { item in
                Task {
                    await viewModel?.toggleCheer(for: item)
                    readModel = viewModel?.readModel ?? readModel
                }
            },
            onSubmitComment: { item, body in
                Task {
                    try? await viewModel?.postComment(body, on: item)
                    readModel = viewModel?.readModel ?? readModel
                }
            },
            onDeletePost: { item in
                Task {
                    await viewModel?.deletePost(item)
                    readModel = viewModel?.readModel ?? readModel
                }
            }
        )
        .task {
            let vm = makeProductionViewModel()
            viewModel = vm
            await vm.load()
            readModel = vm.readModel
        }
    }

    private func makeProductionViewModel() -> FeedViewModel {
        let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        let clientProvider = SupabaseClientProvider(environment: AuthEnvironmentLoader().load())
        let remoteClient = clientProvider.makeClient().map(SupabaseFeedRemoteClient.init(client:))
        let draftStore = FileFeedShareDraftStore.live

        return FeedViewModel(
            feedLoader: FeedDataSource(
                remoteRepository: SupabaseFeedRepository(
                    clientProvider: clientProvider,
                    remoteFetcher: remoteClient,
                    profileFetcher: remoteClient
                ),
                draftStore: draftStore
            ),
            weeklyProgressProvider: UnifiedWorkoutWeeklyProgressProvider(store: store),
            recoveryPreviewProvider: UnifiedWorkoutRecoveryPreviewProvider(store: store),
            streakDatesProvider: UnifiedWorkoutStoreStreakDatesProvider(store: store),
            reactionPoster: remoteClient,
            commentPoster: remoteClient,
            postDeleter: remoteClient,
            draftStore: draftStore
        )
    }
}
