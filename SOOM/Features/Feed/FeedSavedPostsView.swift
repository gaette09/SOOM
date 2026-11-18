import Combine
import SwiftUI
import Supabase

@MainActor
final class FeedSavedPostsViewModel: ObservableObject {
    @Published private(set) var items: [FeedItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoadFailure = false

    private let repository: FeedRepositoryProtocol
    private let reactionPoster: (any FeedRemoteReactionPosting)?
    private let bookmarkPoster: (any FeedRemoteBookmarkPosting)?
    private let commentPoster: (any FeedRemoteCommentPosting)?
    private let postDeleter: (any FeedRemotePostDeleting)?
    private let safetyStore: CommunitySafetyStore?
    private let sessionUserID: (() -> UUID?)?
    private var safetySubscription: AnyCancellable?
    private let accountGeneration: Int?
    private let viewerID: UUID?
    private var reloadPending = false
    private var errorRevision = 0
    private var activeMutations: Set<String> = []

    init(
        repository: FeedRepositoryProtocol,
        reactionPoster: (any FeedRemoteReactionPosting)? = nil,
        bookmarkPoster: (any FeedRemoteBookmarkPosting)? = nil,
        commentPoster: (any FeedRemoteCommentPosting)? = nil,
        postDeleter: (any FeedRemotePostDeleting)? = nil,
        safetyStore: CommunitySafetyStore? = nil,
        sessionUserID: (() -> UUID?)? = nil
    ) {
        self.repository = repository
        self.reactionPoster = reactionPoster
        self.bookmarkPoster = bookmarkPoster
        self.commentPoster = commentPoster
        self.postDeleter = postDeleter
        self.safetyStore = safetyStore
        self.sessionUserID = sessionUserID
        accountGeneration = safetyStore?.accountGeneration
        viewerID = safetyStore?.viewerID
        safetySubscription = safetyStore?.$revision.dropFirst().sink { [weak self] _ in
            self?.invalidateForSafetyChange()
        }
    }

    func load() async {
        guard !isLoading else { reloadPending = true; return }
        isLoading = true
        defer { isLoading = false }
        repeat {
            reloadPending = false
            let startingErrorRevision = errorRevision
            do {
                try validateScope()
                let loadedItems = try await repository.fetchSavedPosts()
                try validateScope()
                // A mutation during a load requests one newer snapshot; never
                // restore the removed row/reaction from the earlier response.
                if !reloadPending {
                    items = FeedDataSource.uniqueWorkoutCards(safetyStore?.filtered(loadedItems) ?? loadedItems)
                    hasLoadFailure = false
                    if errorRevision == startingErrorRevision { errorMessage = nil }
                }
            } catch {
                items = [] // A failed RLS refresh cannot keep private cached content visible.
                hasLoadFailure = true
                showError(error)
                reloadPending = false
            }
        } while reloadPending
    }

    func toggleCheer(for item: FeedItem) async {
        guard item.previewLegacyReadContext == nil, safetyStore == nil || safetyStore?.canUseSocial == true else { return }
        let key = "cheer.\(item.id)"
        guard activeMutations.insert(key).inserted else { return }
        defer { activeMutations.remove(key) }
        do {
            let current = try validatedItem(item)
            guard current.previewLegacyReadContext == nil else { throw CommunitySafetyError.socialUnverified }
            guard let reactionPoster else { throw CommunitySafetyError.unavailable }
            let desired = !current.viewerHasCheered
            if desired { try await reactionPoster.addReaction(postId: item.id, reactionType: "cheer") }
            else { try await reactionPoster.removeReaction(postId: item.id, reactionType: "cheer") }
            try validateScope()
            guard safetyStore?.isBlocked(item.authorId) != true else { throw CommunitySafetyError.invalidTarget }
            let refreshed = try await repository.fetchPost(id: item.id)
            try validateScope()
            guard safetyStore?.isBlocked(item.authorId) != true else { throw CommunitySafetyError.invalidTarget }
            guard let refreshed, refreshed.id == item.id, refreshed.authorId == current.authorId,
                  !refreshed.isLocalDraft, refreshed.viewerHasCheered == desired else {
                throw FeedPostManagementError.changeNotConfirmed
            }
            if let index = items.firstIndex(where: { $0.id == item.id && $0.authorId == current.authorId }) {
                items[index].viewerHasCheered = desired
                items[index].reactions = refreshed.reactions
            }
            errorMessage = nil
            queueReloadIfLoading()
        } catch { showError(error) }
    }

    func toggleSave(for item: FeedItem) async {
        let key = "bookmark.\(item.id)"
        guard activeMutations.insert(key).inserted else { return }
        defer { activeMutations.remove(key) }
        do {
            let current = try validatedItem(item)
            guard let bookmarkPoster else { throw CommunitySafetyError.unavailable }
            if current.viewerHasSaved { try await bookmarkPoster.removeBookmark(postId: item.id) }
            else { try await bookmarkPoster.addBookmark(postId: item.id) }
            try validateScope()
            guard safetyStore?.isBlocked(item.authorId) != true else { throw CommunitySafetyError.invalidTarget }
            if current.viewerHasSaved { items.removeAll { $0.id == item.id } }
            else { setViewerHasSaved(true, forItemId: item.id) }
            errorMessage = nil
            queueReloadIfLoading()
        } catch { showError(error) }
    }

    func postComment(_ body: String, on item: FeedItem) async throws {
        do {
            _ = try validatedItem(item)
            guard let commentPoster else { throw CommunitySafetyError.unavailable }
            try await commentPoster.addComment(postId: item.id, body: body)
            try validateScope()
            guard safetyStore?.isBlocked(item.authorId) != true else { throw CommunitySafetyError.invalidTarget }
            await load()
            try validateScope()
        } catch {
            showError(error)
            throw error
        }
    }

    func deletePost(_ item: FeedItem) async {
        let key = "delete.\(item.id)"
        guard activeMutations.insert(key).inserted else { return }
        defer { activeMutations.remove(key) }
        do {
            let current = try validatedItem(item)
            guard current.authorId == viewerID else { throw CommunitySafetyError.invalidTarget }
            guard let postDeleter else { throw CommunitySafetyError.unavailable }
            try await postDeleter.deletePost(id: item.id)
            try validateScope()
            items.removeAll { $0.id == item.id }
            errorMessage = nil
            queueReloadIfLoading()
        } catch { showError(error) }
    }

    func invalidateForSafetyChange() {
        if accountGeneration != safetyStore?.accountGeneration || viewerID != safetyStore?.viewerID {
            items = []
            hasLoadFailure = true
            showError(safetyStore?.viewerID == nil ? CommunitySafetyError.signInRequired : .accountChanged)
        } else {
            items = safetyStore?.filtered(items) ?? items
        }
        queueReloadIfLoading()
    }

    private func validateScope() throws {
        // A repository-only instance is useful for local fixtures; production
        // always supplies both the safety store and the live SDK identity probe.
        if let safetyStore {
            guard let viewerID, safetyStore.viewerID != nil else { throw CommunitySafetyError.signInRequired }
            guard safetyStore.viewerID == viewerID, safetyStore.accountGeneration == accountGeneration else {
                throw CommunitySafetyError.accountChanged
            }
        }
        if let sessionUserID {
            guard let current = sessionUserID() else { throw CommunitySafetyError.signInRequired }
            guard current == viewerID else { throw CommunitySafetyError.accountChanged }
        }
    }

    private func validatedItem(_ item: FeedItem) throws -> FeedItem {
        try validateScope()
        guard viewerID != nil else { throw CommunitySafetyError.signInRequired }
        guard !item.isLocalDraft, safetyStore?.isBlocked(item.authorId) != true,
              let current = items.first(where: { $0.id == item.id && $0.authorId == item.authorId && !$0.isLocalDraft }) else {
            throw CommunitySafetyError.invalidTarget
        }
        return current
    }

    private func showError(_ error: Error) {
        errorRevision += 1
        errorMessage = FeedLoadFailure.classify(error) == .signInRequired
            ? CommunitySafetyError.signInRequired.errorDescription
            : CommunitySafetyError.message(for: error)
    }

    private func queueReloadIfLoading() { if isLoading { reloadPending = true } }

    private func setViewerHasCheered(_ value: Bool, forItemId id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].viewerHasCheered = value
    }
    private func setViewerHasSaved(_ value: Bool, forItemId id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].viewerHasSaved = value
    }
}

/// Legacy callbacks still used by saved cards retain the opener's identity at
/// the actual write boundary, including when SDK session refresh suspends.
@MainActor
private struct SavedPostsAccountRemote: FeedRemoteReactionPosting, FeedRemoteBookmarkPosting, FeedRemoteCommentPosting, FeedRemotePostDeleting {
    let client: SupabaseClient
    let ownerID: UUID?
    private func authorize() async throws -> UUID {
        guard let ownerID else { throw CommunitySafetyError.signInRequired }
        guard client.auth.currentSession?.user.id == ownerID else { throw CommunitySafetyError.accountChanged }
        let session = try await client.auth.session
        guard session.user.id == ownerID, client.auth.currentSession?.user.id == ownerID else {
            throw CommunitySafetyError.accountChanged
        }
        return ownerID
    }
    private func check(_ ownerID: UUID) throws {
        guard client.auth.currentSession?.user.id == ownerID else { throw CommunitySafetyError.accountChanged }
    }
    func addReaction(postId: UUID, reactionType: String) async throws {
        let owner = try await authorize()
        try check(owner)
        try await client.from("feed_reactions")
            .insert(FeedReactionInsertDTO(postId: postId, userId: owner, reactionType: reactionType)).execute()
        try check(owner)
    }
    func removeReaction(postId: UUID, reactionType: String) async throws {
        let owner = try await authorize()
        try check(owner)
        try await client.from("feed_reactions").delete().eq("post_id", value: postId)
            .eq("user_id", value: owner).eq("reaction_type", value: reactionType).execute()
        try check(owner)
    }
    func addComment(postId: UUID, body: String) async throws {
        let owner = try await authorize()
        try check(owner)
        try await client.from("feed_comments")
            .insert(FeedCommentInsertDTO(postId: postId, userId: owner, body: body)).execute()
        try check(owner)
    }
    func addBookmark(postId: UUID) async throws {
        let owner = try await authorize()
        try check(owner)
        try await SupabaseFeedPostManagementRemote(client: client).setBookmark(postID: postId, viewerID: owner, isSaved: true)
        try check(owner)
    }
    func removeBookmark(postId: UUID) async throws {
        let owner = try await authorize()
        try check(owner)
        try await SupabaseFeedPostManagementRemote(client: client).setBookmark(postID: postId, viewerID: owner, isSaved: false)
        try check(owner)
    }
    func deletePost(id: UUID) async throws {
        let owner = try await authorize()
        try check(owner)
        try await SupabaseFeedPostManagementRemote(client: client).deletePost(id: id, ownerID: owner)
        try check(owner)
    }
}

struct FeedSavedPostsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FeedSavedPostsViewModel
    @ObservedObject private var safetyStore = CommunitySafetyStore.shared
    @State private var selectedItem: FeedItem?

    init(viewModel: FeedSavedPostsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ScrollView { SOOMSkeleton(layout: .feed, label: "저장한 기록을 불러오는 중").padding(SOOMLayout.screenPadding) }
                } else if viewModel.hasLoadFailure && viewModel.items.isEmpty {
                    errorState
                        .padding(SOOMLayout.screenPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.items.isEmpty && viewModel.errorMessage == nil {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: SOOMLayout.stackSpacing) {
                            if viewModel.errorMessage != nil { errorState }
                            ForEach(viewModel.items) { item in
                                FeedItemCard(
                                    item: item,
                                    isOwnPost: item.authorId == safetyStore.viewerID,
                                    onToggleCheer: {
                                        Task { await viewModel.toggleCheer(for: item) }
                                    },
                                    onToggleSave: {
                                        Task { await viewModel.toggleSave(for: item) }
                                    },
                                    onSubmitComment: { body in
                                        try await viewModel.postComment(body, on: item)
                                    },
                                    onDeletePost: {
                                        Task { await viewModel.deletePost(item) }
                                    },
                                    onOpen: { selectedItem = item }
                                )
                            }
                        }
                        .padding(SOOMLayout.screenPadding)
                    }
                    .refreshable { await viewModel.load() }
                }
            }
            .background(SOOMColor.background)
            .feedCardDestination(selection: $selectedItem, onSubmitComment: { item, body in
                try await viewModel.postComment(body, on: item)
            })
            .navigationTitle("저장한 글")
            .feedCommentProfileNavigationHost()
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(NotificationCenter.default.publisher(for: FeedPostManagement.didChange)) { _ in Task { await viewModel.load() } }
            .onReceive(NotificationCenter.default.publisher(for: WorkoutRecordManagement.didChange)) { _ in Task { await viewModel.load() } }
            .task(id: safetyStore.revision) {
                await viewModel.load()
            }
        }
    }

    private var errorState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.hasLoadFailure ? "저장한 기록을 불러오지 못했어요" : "변경을 완료하지 못했어요")
                .font(SOOMFont.body(17, weight: .bold, relativeTo: .headline))
                .foregroundStyle(SOOMColor.ink)
            Text(viewModel.errorMessage ?? "연결 상태를 확인하고 다시 시도해 주세요.")
                .font(SOOMFont.body(14, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if !viewModel.hasLoadFailure {
                Text("변경 결과를 다시 불러와 확인한 뒤 원하는 동작을 다시 선택해 주세요.")
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }
            Button { Task { await viewModel.load() } } label: {
                Label("다시 불러오기", soomIcon: SOOMIcon.sync)
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    .frame(minHeight: 44)
            }
            .disabled(viewModel.isLoading)
            .accessibilityIdentifier("feed.saved.retry")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SOOMColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("feed.saved.error")
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
        if ReviewDemoMode.isActive {
            let demo = ReviewDemoCommunityStore.shared
            _viewModel = StateObject(wrappedValue: FeedSavedPostsViewModel(repository: demo,
                reactionPoster: demo, bookmarkPoster: demo, commentPoster: demo, postDeleter: demo,
                safetyStore: .shared, sessionUserID: { demo.sessionUserID }))
            return
        }
        let clientProvider = SupabaseClientProvider(environment: AuthEnvironmentLoader().load())
        let client = clientProvider.makeClient()
        let remoteClient = client.map(SupabaseFeedRemoteClient.init(client:))
        let scopedRemote = client.map { SavedPostsAccountRemote(client: $0, ownerID: CommunitySafetyStore.shared.viewerID) }
        let repository = SupabaseFeedRepository(
            clientProvider: clientProvider,
            remoteFetcher: remoteClient,
            profileFetcher: remoteClient
        )

        _viewModel = StateObject(wrappedValue: FeedSavedPostsViewModel(
            repository: repository,
            reactionPoster: scopedRemote,
            bookmarkPoster: scopedRemote,
            commentPoster: scopedRemote,
            postDeleter: scopedRemote,
            safetyStore: .shared,
            sessionUserID: { client?.auth.currentSession?.user.id }
        ))
    }

    var body: some View {
        SocialAccessBoundary {
        FeedSavedPostsView(viewModel: viewModel)

        }
    }
}
