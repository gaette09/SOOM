import Foundation
import Combine
import UserNotifications

protocol NotificationInboxFetching {
    func fetchNotifications() async throws -> [NotificationDTO]
    func fetchUnreadNotificationCount() async throws -> Int
    func markAllNotificationsAsRead() async throws
    func markNotificationsAsRead(ids: [UUID]) async throws
    func hideNotification(id: UUID) async throws
    func restoreNotification(id: UUID) async throws
}
extension NotificationInboxFetching {
    func fetchUnreadNotificationCount() async throws -> Int {
        Set(try await fetchNotifications().filter { $0.readAt == nil }.map(\.id)).count
    }
    func markNotificationsAsRead(ids: [UUID]) async throws { try await markAllNotificationsAsRead() }
    func hideNotification(id: UUID) async throws { throw NotificationInboxError.upgradeRequired }
    func restoreNotification(id: UUID) async throws { throw NotificationInboxError.upgradeRequired }
}

extension Notification.Name {
    static let soomNotificationReceiptsChanged = Notification.Name("soomNotificationReceiptsChanged")
}

/// One server count feeds the inbox bell and the home-screen icon. Counts are
/// snapshots, never increments inferred from a push or from opening the inbox.
@MainActor
final class NotificationBadgeStore: ObservableObject {
    static let shared = NotificationBadgeStore { count in
        try await UNUserNotificationCenter.current().setBadgeCount(count)
    }
    @Published private(set) var count: Int?
    @Published private(set) var iconUpdateFailed = false
    private var scope: String?
    private var fetcher: (any NotificationInboxFetching)?
    private var generation = UUID()
    private var refreshing = false
    private var refreshAgain = false
    private var pendingIconCount: Int?
    private var writingIcon = false
    private let writeIcon: @MainActor (Int) async throws -> Void

    init(writeIcon: @escaping @MainActor (Int) async throws -> Void) { self.writeIcon = writeIcon }

    func bind(scope: String?, fetcher: (any NotificationInboxFetching)?) {
        if self.fetcher != nil, fetcher == nil { generation = UUID() }
        self.fetcher = fetcher
        guard self.scope != scope else {
            if scope == nil, count == nil { publish(0) }
            return
        }
        let hadAccount = self.scope != nil
        self.scope = scope; generation = UUID()
        // Clear the previous account on sign-out/switch. On cold launch, keep
        // the OS badge until the first successful authoritative count arrives.
        count = nil
        if hadAccount || scope == nil { publish(0) }
    }

    func refresh() async {
        guard scope != nil, fetcher != nil else { return }
        if refreshing { refreshAgain = true; return }
        refreshing = true
        defer {
            refreshing = false
            // SwiftUI cancels the old .task when the account/safety key changes.
            // A queued refresh belongs to the new task and must survive that.
            if refreshAgain { Task { await self.refresh() } }
        }
        repeat {
            refreshAgain = false
            let gen = generation
            guard scope != nil, let fetcher else { break }
            do {
                let result = try await fetcher.fetchUnreadNotificationCount()
                guard gen == generation, !Task.isCancelled else { continue }
                guard result >= 0 else { continue } // malformed response isn't zero
                publish(result)
            } catch { /* retain the last known count; no optimistic zero */ }
        } while refreshAgain && !Task.isCancelled
    }

    private func publish(_ value: Int) {
        count = value; pendingIconCount = value
        guard !writingIcon else { return }
        writingIcon = true
        Task {
            // Serialize OS writes: a slow old-account write cannot finish
            // after the queued sign-out zero/new-account value.
            while let next = pendingIconCount {
                pendingIconCount = nil
                do { try await writeIcon(next); iconUpdateFailed = false }
                catch { iconUpdateFailed = true } // no permission prompt/retry loop
            }
            writingIcon = false
        }
    }
}
enum NotificationInboxError: Error { case upgradeRequired }

enum NotificationKind: String, Codable, Equatable {
    case reaction, comment, reply, mention
    case followRequest = "follow_request"
    case followApproved = "follow_approved"
    case unknown
    var opensComments: Bool { self == .comment || self == .reply }
    var showsBodyPreview: Bool { self == .comment || self == .reply || self == .mention }
    var inboxMessage: String {
        switch self {
        case .reaction: return "님이 회원님의 운동에 응원을 보냈어요."
        case .comment: return "님이 회원님의 운동에 댓글을 남겼어요."
        case .reply: return "님이 댓글에 답글을 남겼어요."
        case .mention: return "님이 회원님을 언급했어요."
        case .followRequest: return "님이 팔로우를 요청했어요."
        case .followApproved: return "님이 팔로우 요청을 승인했어요."
        case .unknown: return "새 알림이 있어요."
        }
    }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unknown
    }
}
enum NotificationDestination: Hashable {
    case post(UUID), requests, profile(UUID)
}
struct NotificationDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let recipientId: UUID
    let actorId: UUID?
    let type: NotificationKind
    let postId: UUID?
    let body: String?
    let readAt: Date?
    let createdAt: Date
    let requestId: UUID?
    init(id: UUID, recipientId: UUID, actorId: UUID?, type: NotificationKind, postId: UUID?, body: String?, readAt: Date?, createdAt: Date, requestId: UUID? = nil) {
        self.id=id; self.recipientId=recipientId; self.actorId=actorId; self.type=type; self.postId=postId
        self.body=body; self.readAt=readAt; self.createdAt=createdAt; self.requestId=requestId
    }
    enum CodingKeys: String, CodingKey {
        case id, type, body
        case recipientId="recipient_id", actorId="actor_id", postId="post_id", readAt="read_at", createdAt="created_at", requestId="request_id"
    }
    var destination: NotificationDestination? {
        switch type {
        case .reaction, .comment, .reply, .mention: return postId.map(NotificationDestination.post)
        case .followRequest: return .requests
        case .followApproved: return actorId.map(NotificationDestination.profile)
        case .unknown: return nil
        }
    }
    func read(at date: Date) -> Self {
        .init(id:id,recipientId:recipientId,actorId:actorId,type:type,postId:postId,body:body,readAt:readAt ?? date,createdAt:createdAt,requestId:requestId)
    }
}

enum NotificationInboxFailureContext: Equatable {
    case load, read, hide(UUID), restore(UUID)
}

@MainActor
final class NotificationInboxModel: ObservableObject {
    @Published private(set) var items: [NotificationDTO] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var failureContext: NotificationInboxFailureContext?
    @Published private(set) var busy = Set<UUID>()
    @Published private(set) var undoItem: NotificationDTO?
    @Published private(set) var receiptRevision = 0
    private let fetcher: (any NotificationInboxFetching)?
    private let session: @MainActor () -> String?
    private var generation = UUID()
    private var loadRequest = UUID()
    init(fetcher: (any NotificationInboxFetching)?, session: @escaping @MainActor () -> String? = {
        let s = CommunitySafetyStore.shared
        guard s.canUseSocial, let owner = s.viewerID else { return nil }
        return "\(owner):\(s.accountGeneration):\(s.revision)"
    }) { self.fetcher=fetcher; self.session=session }
    func reset() { generation=UUID();invalidateLoad();items=[];busy=[];undoItem=nil;error=nil;failureContext=nil }
    private func invalidateLoad() { loadRequest=UUID();isLoading=false }
    func load() async {
        guard !isLoading, let stamp=session(), let fetcher else { return }
        let gen=generation,request=UUID();loadRequest=request;isLoading=true;error=nil;failureContext=nil
        defer { if generation==gen && loadRequest==request { isLoading=false } }
        do {
            let result=try await fetcher.fetchNotifications()
            guard valid(stamp,gen),loadRequest==request else { return }
            var seen=Set<UUID>();items=result.filter { seen.insert($0.id).inserted }
            await markRead()
            if valid(stamp,gen) {
                NotificationCenter.default.post(name: .soomNotificationReceiptsChanged, object: nil)
            }
        } catch { if valid(stamp,gen),loadRequest==request { self.error="알림을 불러오지 못했어요. 연결을 확인하고 다시 시도해 주세요.";self.failureContext = .load } }
    }
    func markRead() async {
        guard let stamp=session(),let fetcher else { return }
        let gen=generation, ids=items.filter { $0.readAt == nil }.map(\.id)
        guard !ids.isEmpty else { return }
        do {
            // Preserve the existing full history; bound each write instead of
            // truncating older unread notifications out of the list/badge.
            for start in stride(from:0,to:ids.count,by:100) {
                let batch=Array(ids[start..<min(start+100,ids.count)])
                try await fetcher.markNotificationsAsRead(ids:batch)
                guard valid(stamp,gen) else { return }
                let marked=Set(batch);items=items.map { marked.contains($0.id) ? $0.read(at:Date()) : $0 };receiptRevision+=1
                NotificationCenter.default.post(name: .soomNotificationReceiptsChanged, object: nil)
            }
            error=nil;failureContext=nil
        } catch { if valid(stamp,gen) { self.error="읽음 처리를 저장하지 못했어요. 다시 시도해 주세요.";self.failureContext = .read } }
    }
    func hide(_ item: NotificationDTO) async {
        guard let stamp=session(),let fetcher,!busy.contains(item.id),items.contains(where:{$0.id==item.id}) else { return }
        let gen=generation;busy.insert(item.id)
        defer { if generation==gen { busy.remove(item.id) } }
        do {
            try await fetcher.hideNotification(id:item.id)
            guard valid(stamp,gen) else { return }
            invalidateLoad()
            items.removeAll { $0.id==item.id };undoItem=item;error=nil;failureContext=nil;receiptRevision+=1
            NotificationCenter.default.post(name: .soomNotificationReceiptsChanged, object: nil)
        } catch { if valid(stamp,gen) { self.error="알림을 삭제하지 못했어요. 원래 내역은 유지돼요. 다시 시도해 주세요.";self.failureContext = .hide(item.id) } }
    }
    func undoHide() async {
        guard let item=undoItem,let stamp=session(),let fetcher,!busy.contains(item.id) else { return }
        let gen=generation;busy.insert(item.id)
        defer { if generation==gen { busy.remove(item.id) } }
        do {
            try await fetcher.restoreNotification(id:item.id)
            guard valid(stamp,gen) else { return }
            invalidateLoad()
            if !items.contains(where:{$0.id==item.id}) {
                items.append(item);items.sort { $0.createdAt > $1.createdAt }
            }
            undoItem=nil;error=nil;failureContext=nil;receiptRevision+=1
            NotificationCenter.default.post(name: .soomNotificationReceiptsChanged, object: nil)
            await load()
        } catch { if valid(stamp,gen) { self.error="삭제 취소를 저장하지 못했어요. 다시 시도해 주세요.";self.failureContext = .restore(item.id) } }
    }
    private func valid(_ stamp: String,_ gen:UUID) -> Bool { !Task.isCancelled && generation==gen && session()==stamp }
}

/// Read-only restoration of previously authorized recipient inbox rows. This
/// capability intentionally exposes no mark-read/hide/reply/profile operations.
@MainActor protocol LegacyInboxPreviewReading {
    func readLegacyInboxPreview(owner: UUID) async throws -> [NotificationDTO]
}
@MainActor final class LegacyInboxPreviewModel: ObservableObject {
    @Published private(set) var rows: [NotificationDTO] = []
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    private let reader: (any LegacyInboxPreviewReading)?
    private let context: () -> AccountActivityReadContext?
    private var request = UUID()
    private var loadedContext: AccountActivityReadContext?
    func readOnlyPostID(for row: NotificationDTO) -> UUID? {
        guard let loadedContext, context() == loadedContext, !loading, error == nil,
              row.recipientId == loadedContext.viewerID, rows.contains(row),
              case .post(let id) = row.destination else { return nil }
        return id
    }
    init(reader: (any LegacyInboxPreviewReading)?, context: @escaping () -> AccountActivityReadContext?) {
        self.reader = reader; self.context = context
    }
    func reset() { request = UUID(); loadedContext = nil; rows = []; error = nil; loading = false }
    func load() async {
        reset()
        guard let reader, let expected = context() else { return }
        let token = request; loading = true
        defer { if token == request { loading = false } }
        do {
            let result = try await reader.readLegacyInboxPreview(owner: expected.viewerID)
            guard token == request, context() == expected, !Task.isCancelled else { return }
            guard result.count <= 100, result.allSatisfy({ $0.recipientId == expected.viewerID }),
                  Set(result.map(\.id)).count == result.count else { throw NotificationInboxError.upgradeRequired }
            loadedContext = expected
            rows = result.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString > $1.id.uuidString : $0.createdAt > $1.createdAt }
        } catch {
            guard token == request, context() == expected, !Task.isCancelled else { return }
            self.error = "기존 알림을 확인하지 못했어요. 기록은 삭제하거나 읽음 처리하지 않았어요."
        }
    }
}
