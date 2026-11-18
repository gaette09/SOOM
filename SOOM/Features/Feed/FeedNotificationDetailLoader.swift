import SwiftUI

/// Deep-link landing spot for a tapped notification. Resolves `postId` to a
/// `FeedItem` through a fresh server lookup (see `FeedViewModel.resolveFeedItem`)
/// and only then renders the same `FeedItemDetailDestination` the normal
/// feed-card tap path uses.
///
/// `.failed` covers every non-success case uniformly (deleted post,
/// private post the viewer can't see per RLS, network error) — the UI
/// deliberately doesn't distinguish "doesn't exist" from "exists but you
/// can't see it": showing a different message for the latter would leak
/// that a private post exists at all.
struct FeedNotificationDetailLoader: View {
    let postId: UUID
    let resolve: (UUID) async -> FeedItem?
    let onSubmitComment: ((FeedItem, String) async throws -> Void)?

    private enum LoadState {
        case loading
        case loaded(FeedItem, revision: Int)
        case failed
    }

    @ObservedObject private var safetyStore = CommunitySafetyStore.shared
    @State private var state: LoadState = .loading

    init(
        postId: UUID,
        resolve: @escaping (UUID) async -> FeedItem?,
        onSubmitComment: ((FeedItem, String) async throws -> Void)? = nil
    ) {
        self.postId = postId
        self.resolve = resolve
        self.onSubmitComment = onSubmitComment
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ScrollView { SOOMSkeleton(layout: .detail, label: "알림의 운동 불러오는 중").padding(SOOMLayout.screenPadding) }
            case .loaded(let item, let revision):
                if revision == safetyStore.revision {
                    FeedItemDetailDestination(
                        item: item,
                        onSubmitComment: onSubmitComment.map { callback in
                            { (body: String) in try await callback(item, body) }
                        }
                    )
                    .id(safetyStore.revision)
                } else {
                    SOOMSkeleton(layout: .detail, label: "공개 범위 확인 중").padding(SOOMLayout.screenPadding)
                }
            case .failed:
                failedState
            }
        }
        .task(id: "\(postId.uuidString):\(safetyStore.revision)") {
            let revision = safetyStore.revision
            state = .loading
            let item = await resolve(postId)
            guard !Task.isCancelled, revision == safetyStore.revision else { return }
            if let item, !safetyStore.isBlocked(item.authorId) {
                state = .loaded(item, revision: revision)
            } else {
                state = .failed
            }
        }
    }

    private var failedState: some View {
        VStack(spacing: SOOMLayout.Spacing.md) {
            Image(soom: SOOMIcon.activity)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(SOOMColor.tertiaryInk)

            Text("게시물을 찾을 수 없어요")
                .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)

            Text("삭제되었거나 더 이상 볼 수 없는 게시물이에요.")
                .font(SOOMFont.body(13, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(SOOMLayout.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
