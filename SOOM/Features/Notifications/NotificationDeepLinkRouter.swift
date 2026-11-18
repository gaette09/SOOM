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
    @Published var pendingPush: NotificationPushPayload?
    @Published var pendingNativePush: NativeActivityPushPayload?
    private var deferredNative: (payload: NativeActivityPushPayload, generation: Int, expires: Date)?
    func routeNativePush(_ payload: NativeActivityPushPayload, currentUserID: UUID?, previewAllowed: Bool,
                         generation: Int = 0, now: Date = Date()) {
        guard currentUserID == payload.recipientID else { return }
        if previewAllowed { deferredNative=nil; pendingNativePush=payload }
        else { deferredNative=(payload,generation,now.addingTimeInterval(120)) }
    }
    func resumeNativePush(currentUserID: UUID?, generation: Int, previewAllowed: Bool, now: Date = Date()) {
        guard let deferred=deferredNative else { return }
        guard currentUserID==deferred.payload.recipientID, generation==deferred.generation, now<deferred.expires else { deferredNative=nil;return }
        guard previewAllowed else { return }
        deferredNative=nil;pendingNativePush=deferred.payload
    }
    /// A cold-launch payload waits for the account's social gate. It is not
    /// consumed merely because RootTabView appeared before verification finished.
    func consumeNativePush(currentUserID: UUID?, canNavigate: Bool) -> NativeActivityPushPayload? {
        guard let payload=pendingNativePush, let currentUserID else { return nil }
        guard payload.recipientID==currentUserID else { pendingNativePush=nil; return nil }
        guard canNavigate else { return nil }
        pendingNativePush=nil
        return payload
    }
    func clearLegacy() { pendingPostId=nil;pendingPush=nil }
    func routePush(_ payload:NotificationPushPayload,currentUserID:UUID?) {
        guard currentUserID == payload.recipientID else { return }
        pendingPush=payload
    }
    func consumePush(currentUserID:UUID?) -> NotificationDestination? {
        defer { pendingPush=nil }
        guard let payload=pendingPush,payload.recipientID==currentUserID else { return nil }
        return payload.destination
    }
    func clear() { pendingPostId=nil;pendingPush=nil;pendingNativePush=nil;deferredNative=nil }

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

/// Pushes carry routing identifiers only, never health/location values. Unscoped
/// legacy taps cannot choose a destination in a different signed-in account.
struct NotificationPushPayload: Equatable {
    let notificationID: UUID
    let recipientID: UUID
    let destination: NotificationDestination
    init?(userInfo: [AnyHashable:Any]) {
        guard let id=(userInfo["notification_id"] as? String).flatMap(UUID.init(uuidString:)),
              let recipient=(userInfo["recipient_id"] as? String).flatMap(UUID.init(uuidString:)),
              let kind=(userInfo["notification_type"] as? String).flatMap(NotificationKind.init(rawValue:)) else { return nil }
        switch kind {
        case .reaction,.comment,.reply,.mention:
            guard let post=(userInfo["post_id"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            destination = .post(post)
        case .followRequest: destination = .requests
        case .followApproved:
            guard let profile=(userInfo["actor_id"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            destination = .profile(profile)
        case .unknown: return nil
        }
        notificationID=id;recipientID=recipient
    }
}
enum NotificationSocialTarget: Identifiable {
    case requests,profile(UUID)
    var id:String { switch self { case .requests:return "requests";case .profile(let id):return id.uuidString } }
}


/// Inbox navigation preserves the interaction kind; an unread receipt is not a
/// permission to display a cached or inaccessible post.
struct FeedNotificationRequest: Equatable, Identifiable {
    let id = UUID()
    let postID: UUID
    let opensComments: Bool
}

@MainActor
final class FeedNotificationNavigation: ObservableObject {
    @Published private(set) var item: FeedItem?
    @Published private(set) var readyRequestID: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    private var current: FeedNotificationRequest?
    private var commentsConsumed = false

    func resolve(_ request: FeedNotificationRequest,
                 isCurrent: () -> Bool = { true },
                 using lookup: (UUID) async -> FeedItem?) async {
        // Same presentation cannot refetch/reopen on view reappearance.
        guard !Task.isCancelled, isCurrent() else { clear(); return }
        guard current?.id != request.id else { return }
        current = request; item = nil; readyRequestID = nil
        commentsConsumed = false; failed = false; isLoading = true
        let result = await lookup(request.postID)
        guard current?.id == request.id else { return }
        isLoading = false
        guard !Task.isCancelled, isCurrent() else { clear(); return }
        guard let result, result.id == request.postID, !result.isLocalDraft else {
            failed = true; return
        }
        item = result; readyRequestID = request.id
    }

    func takeCommentsWhenVisible(postID: UUID) -> FeedItem? {
        guard readyRequestID == current?.id, current?.opensComments == true,
              item?.id == postID, !commentsConsumed else { return nil }
        commentsConsumed = true
        return item
    }

    func clear() {
        current = nil; item = nil; readyRequestID = nil
        isLoading = false; failed = false; commentsConsumed = false
    }
}

/// Separate native identifiers must never fall back to a legacy post route.
struct NativeActivityPushPayload: Hashable, Identifiable {
    let recipientID: UUID, eventID: UUID, cardID: UUID, commentID: UUID
    let kind: String
    var id: UUID { eventID }
    init?(userInfo v: [AnyHashable: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: v), data.count <= 3500,
              ["activity_native_v1", "activity_native_v2"].contains(v["source_kind"] as? String ?? ""),
              v["post_id"] == nil, v["notification_type"] == nil,
              let recipient = (v["recipient_id"] as? String).flatMap(UUID.init(uuidString:)),
              let event = (v["event_id"] as? String).flatMap(UUID.init(uuidString:)),
              let card = (v["card_id"] as? String).flatMap(UUID.init(uuidString:)),
              let comment = (v["comment_id"] as? String).flatMap(UUID.init(uuidString:)),
              let kind = v["kind"] as? String, ["comment", "reply", "mention"].contains(kind)
        else { return nil }
        recipientID=recipient;eventID=event;cardID=card;commentID=comment;self.kind=kind
    }
    func matches(_ row: AccountActivityNativeInboxRow) -> Bool {
        row.eventID == eventID && row.cardID == cardID && row.commentID == commentID && row.reason == kind
    }
}

/// Presentation state is separate from home membership. Closing a child sheet
/// cannot erase the authorized notification card or consume a timeline cursor.
struct FeedNotificationCardPresentation {
    let item: FeedItem
    let context: AccountActivityReadContext
    let opensComments: Bool
    private(set) var didPresentInitialComments = false
    var commentsPresented = false
    var supportsLegacyComments: Bool { !item.previewLegacySummary && item.activityProjection == nil }
    func permits(_ current: AccountActivityReadContext?) -> Bool { current == context }
    mutating func presentInitialComments(current: AccountActivityReadContext?, canUseSocial: Bool) {
        guard canUseSocial, supportsLegacyComments, opensComments, permits(current), !didPresentInitialComments else { return }
        didPresentInitialComments = true
        commentsPresented = true
    }
}

struct NativeNotificationRouteTarget: Hashable { let payload: NativeActivityPushPayload }
