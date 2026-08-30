import SwiftData
import SwiftUI

struct FeedViewContainer: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: FeedViewModel?
    @State private var readModel = FeedReadModel.loading
    @State private var notificationFetcher: (any NotificationInboxFetching)?
    @State private var profileFetcher: (any FeedRemoteProfileFetching)?

    var body: some View {
        FeedView(
            items: readModel.items,
            weeklySnapshot: readModel.weeklySnapshot,
            recoveryInsight: readModel.recoveryInsight,
            streak: readModel.streak,
            notificationFetcher: notificationFetcher,
            profileFetcher: profileFetcher,
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
        .navigationDestination(for: FeedPostRouteTarget.self) { target in
            FeedNotificationDetailLoader(
                postId: target.postId,
                resolve: { postId in
                    await viewModel?.resolveFeedItem(postId: postId) ?? nil
                },
                onSubmitComment: { item, body in
                    Task {
                        try? await viewModel?.postComment(body, on: item)
                        readModel = viewModel?.readModel ?? readModel
                    }
                }
            )
        }
        .task {
            let (vm, remoteClient) = makeProductionViewModel()
            viewModel = vm
            notificationFetcher = remoteClient
            profileFetcher = remoteClient
            await vm.load()
            readModel = vm.readModel
        }
    }

    private func makeProductionViewModel() -> (FeedViewModel, SupabaseFeedRemoteClient?) {
        let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        let clientProvider = SupabaseClientProvider(environment: AuthEnvironmentLoader().load())
        let remoteClient = clientProvider.makeClient().map(SupabaseFeedRemoteClient.init(client:))
        let draftStore = FileFeedShareDraftStore.live

        let viewModel = FeedViewModel(
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
        return (viewModel, remoteClient)
    }
}
