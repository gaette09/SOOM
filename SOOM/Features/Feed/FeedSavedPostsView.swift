import SwiftUI

@MainActor
final class FeedSavedPostsViewModel: ObservableObject {
    @Published private(set) var items: [FeedItem] = []
    @Published private(set) var isLoading = false

    private let repository: FeedRepositoryProtocol
    private let reactionPoster: (any FeedRemoteReactionPosting)?
    private let bookmarkPoster: (any FeedRemoteBookmarkPosting)?
    private let commentPoster: (any FeedRemoteCommentPosting)?
    private let postDeleter: (any FeedRemotePostDeleting)?

    init(
        repository: FeedRepositoryProtocol,
        reactionPoster: (any FeedRemoteReactionPosting)? = nil,
        bookmarkPoster: (any FeedRemoteBookmarkPosting)? = nil,
        commentPoster: (any FeedRemoteCommentPosting)? = nil,
        postDeleter: (any FeedRemotePostDeleting)? = nil
    ) {
        self.repository = repository
        self.reactionPoster = reactionPoster
        self.bookmarkPoster = bookmarkPoster
        self.commentPoster = commentPoster
        self.postDeleter = postDeleter
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        items = (try? await repository.fetchSavedPosts()) ?? []
    }

    func toggleCheer(for item: FeedItem) async {
        guard !item.isLocalDraft, let reactionPoster else {
            return
        }

        let wasCheered = item.viewerHasCheered
        setViewerHasCheered(!wasCheered, forItemId: item.id)

        do {
            if wasCheered {
                try await reactionPoster.removeReaction(postId: item.id, reactionType: "cheer")
            } else {
                try await reactionPoster.addReaction(postId: item.id, reactionType: "cheer")
            }
        } catch {
            setViewerHasCheered(wasCheered, forItemId: item.id)
        }
    }

    func toggleSave(for item: FeedItem) async {
        guard !item.isLocalDraft, let bookmarkPoster else {
            return
        }

        let wasSaved = item.viewerHasSaved
        setViewerHasSaved(!wasSaved, forItemId: item.id)
        if wasSaved {
            items.removeAll { $0.id == item.id }
        }

        do {
            if wasSaved {
                try await bookmarkPoster.removeBookmark(postId: item.id)
            } else {
                try await bookmarkPoster.addBookmark(postId: item.id)
            }
        } catch {
            setViewerHasSaved(wasSaved, forItemId: item.id)
        }
    }

    func postComment(_ body: String, on item: FeedItem) async throws {
        guard !item.isLocalDraft, let commentPoster else {
            return
        }

        try await commentPoster.addComment(postId: item.id, body: body)
        await load()
    }

    func deletePost(_ item: FeedItem) async {
        do {
            if !item.isLocalDraft {
                try await postDeleter?.deletePost(id: item.id)
            }
            items.removeAll { $0.id == item.id }
        } catch {
            // Deletion failed, so keep the server-backed item visible.
        }
    }

    private func setViewerHasCheered(_ value: Bool, forItemId id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].viewerHasCheered = value
    }

    private func setViewerHasSaved(_ value: Bool, forItemId id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].viewerHasSaved = value
    }
}

struct FeedSavedPostsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FeedSavedPostsViewModel

    init(viewModel: FeedSavedPostsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.items.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: SOOMLayout.stackSpacing) {
                            ForEach(viewModel.items) { item in
                                FeedItemCard(
                                    item: item,
                                    onToggleCheer: {
                                        Task { await viewModel.toggleCheer(for: item) }
                                    },
                                    onToggleSave: {
                                        Task { await viewModel.toggleSave(for: item) }
                                    },
                                    onSubmitComment: { body in
                                        Task { try? await viewModel.postComment(body, on: item) }
                                    },
                                    onDeletePost: {
                                        Task { await viewModel.deletePost(item) }
                                    }
                                )
                            }
                        }
                        .padding(SOOMLayout.screenPadding)
                    }
                }
            }
            .background(SOOMColor.background)
            .navigationTitle("저장한 글")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .task {
                await viewModel.load()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: SOOMLayout.Spacing.sm) {
            Text("저장한 글이 없어요")
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)

            Text("피드에서 저장한 글을 여기서 볼 수 있어요.")
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FeedSavedPostsViewContainer: View {
    @StateObject private var viewModel: FeedSavedPostsViewModel

    init() {
        let clientProvider = SupabaseClientProvider(environment: AuthEnvironmentLoader().load())
        let remoteClient = clientProvider.makeClient().map(SupabaseFeedRemoteClient.init(client:))
        let repository = SupabaseFeedRepository(
            clientProvider: clientProvider,
            remoteFetcher: remoteClient,
            profileFetcher: remoteClient
        )

        _viewModel = StateObject(wrappedValue: FeedSavedPostsViewModel(
            repository: repository,
            reactionPoster: remoteClient,
            bookmarkPoster: remoteClient,
            commentPoster: remoteClient,
            postDeleter: remoteClient
        ))
    }

    var body: some View {
        FeedSavedPostsView(viewModel: viewModel)
    }
}
