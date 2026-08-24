import SwiftUI

/// Deep-link landing spot for a tapped notification. Resolves `postId` to a
/// `FeedItem` (the resolver checks the already-loaded feed first, then
/// falls back to a single-post fetch — see `FeedViewModel.resolveFeedItem`)
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

    private enum LoadState {
        case loading
        case loaded(FeedItem)
        case failed
    }

    @State private var state: LoadState = .loading

    init(postId: UUID, resolve: @escaping (UUID) async -> FeedItem?) {
        self.postId = postId
        self.resolve = resolve
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let item):
                FeedItemDetailDestination(item: item)
            case .failed:
                failedState
            }
        }
        .task {
            if let item = await resolve(postId) {
                state = .loaded(item)
            } else {
                state = .failed
            }
        }
    }

    private var failedState: some View {
        VStack(spacing: SOOMLayout.Spacing.md) {
            Image(systemName: SOOMIcon.activity)
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
