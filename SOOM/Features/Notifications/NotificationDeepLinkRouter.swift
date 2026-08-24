import Foundation

/// Bridges a tapped push notification (received by `AppDelegate`, which
/// lives outside the SwiftUI view tree) to `RootTabView`'s navigation
/// state. `pendingPostId` is a one-shot mailbox: `RootTabView` consumes it
/// (switches to the Feed tab, pushes the post) and clears it back to nil,
/// so re-appearing views don't replay a stale route.
///
/// Also covers cold launch: if the app wasn't running when the
/// notification was tapped, `AppDelegate` can set `pendingPostId` before
/// `RootTabView` even exists — `@Published` means the eventual observer
/// still sees it once the view hierarchy is up, no separate buffering
/// needed.
@MainActor
final class NotificationDeepLinkRouter: ObservableObject {
    @Published var pendingPostId: UUID?

    func routeToPost(id: UUID) {
        pendingPostId = id
    }

    func consumePendingPostId() -> UUID? {
        defer { pendingPostId = nil }
        return pendingPostId
    }
}

/// Navigation value for `NavigationStack(path:)` — deliberately separate
/// from the existing `NavigationLink { FeedItemDetailDestination(item:) }`
/// call sites, which push an already-loaded `FeedItem` by value. This one
/// carries only an id, because a deep link may arrive before that post is
/// loaded anywhere.
struct FeedPostRouteTarget: Hashable {
    let postId: UUID
}
