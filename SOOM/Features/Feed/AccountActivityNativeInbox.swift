import Foundation
import SwiftUI
import Supabase

// Separate namespace: these IDs must never enter the legacy post notification route.
enum AccountActivityNativeInboxGate { static let productionReady = false }
enum AccountActivityNativeInboxError: Error { case disabled, staleContext, invalidReceipt, unavailable }
struct AccountActivityNativeInboxRow: Decodable, Equatable, Identifiable {
    let eventID: UUID
    let commentID: UUID
    let reason: String
    let createdAt: Date
    let cardID: UUID
    let actorID: UUID
    let readAt: Date?
    var id: UUID { eventID }
    enum CodingKeys: String, CodingKey {
        case eventID = "event_id", commentID = "comment_id", reason, createdAt = "created_at"
        case cardID = "card_id", actorID = "actor_id", readAt = "read_at"
    }
}
struct AccountActivityNativeInboxEnvelope: Decodable {
    let version: Int
    let viewerID: UUID
    let sourceKind: String
    let backing: String
    let rows: [AccountActivityNativeInboxRow]
    let pushDelivery: String
    let releaseReady: Bool
    let unreadCount: Int
    enum CodingKeys: String, CodingKey {
        case version, viewerID = "viewer_id", sourceKind = "source_kind", backing, rows
        case pushDelivery = "push_delivery", releaseReady = "release_ready", unreadCount = "unread_count"
    }
    static func decode(_ data: Data) throws -> Self { try decoder().decode(Self.self, from: data) }
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: value) { return date }
            f.formatOptions = [.withInternetDateTime]
            guard let date = f.date(from: value) else { throw AccountActivityNativeInboxError.invalidReceipt }
            return date
        }
        return decoder
    }
    func validated(viewer: UUID, limit: Int, fixture: Bool, now: Date, preview: Bool = false, expectedPolicy: AccountActivityReadPolicy = .approvedFollowersV1) throws -> [AccountActivityNativeInboxRow] {
        guard version == expectedPolicy.rawValue, viewerID == viewer, sourceKind == expectedPolicy.nativeSourceKind, backing == "native",
              pushDelivery == "candidate_disabled", releaseReady == !(fixture || preview),
              (1...100).contains(limit), rows.count <= limit, unreadCount >= rows.filter({ $0.readAt == nil }).count else { throw AccountActivityNativeInboxError.invalidReceipt }
        var events = Set<UUID>(), comments = Set<UUID>()
        for (index, row) in rows.enumerated() {
            guard events.insert(row.eventID).inserted, comments.insert(row.commentID).inserted,
                  ["comment", "reply", "mention"].contains(row.reason), row.actorID != viewer,
                  row.createdAt.timeIntervalSince1970.isFinite, row.createdAt <= now,
                  row.readAt.map({ $0.timeIntervalSince1970.isFinite && $0 <= now && $0 >= row.createdAt }) ?? true else {
                throw AccountActivityNativeInboxError.invalidReceipt
            }
            if index > 0 {
                let prior = rows[index - 1]
                guard prior.createdAt > row.createdAt || (prior.createdAt == row.createdAt && prior.eventID.uuidString < row.eventID.uuidString) else {
                    throw AccountActivityNativeInboxError.invalidReceipt
                }
            }
        }
        return rows
    }
}
enum AccountActivityNativeInboxAction: String, Encodable { case markRead = "mark_read", markUnread = "mark_unread", hide, undoHide = "undo_hide" }
struct AccountActivityNativeInboxSnapshot {
    let rows: [AccountActivityNativeInboxRow]
    let unreadCount: Int
}
struct AccountActivityNativeInboxStateReceipt: Decodable {
    let version: Int; let viewerID: UUID; let sourceKind: String
    let eventID: UUID; let commentID: UUID; let readAt: Date?; let hiddenAt: Date?; let releaseReady: Bool
    enum CodingKeys: String, CodingKey {
        case version, viewerID = "viewer_id", sourceKind = "source_kind", eventID = "event_id", commentID = "comment_id", readAt = "read_at", hiddenAt = "hidden_at", releaseReady = "release_ready"
    }
}
@MainActor protocol AccountActivityNativeInboxTransport {
    var readPolicy: AccountActivityReadPolicy { get }
    var context: AccountActivityReadContext? { get }
    func inbox(limit: Int) async throws -> Data
    func card(id: UUID) async throws -> AccountActivityCardEnvelope
    func state(commentID: UUID, action: AccountActivityNativeInboxAction) async throws -> Data
}
extension AccountActivityNativeInboxTransport { var readPolicy: AccountActivityReadPolicy { .approvedFollowersV1 } }
@MainActor final class SupabaseAccountActivityNativeInboxTransport: AccountActivityNativeInboxTransport {
    private let client: SupabaseClient
    let readPolicy: AccountActivityReadPolicy
    private let preview: Bool
    private let currentContext: () -> AccountActivityReadContext?
    init(client: SupabaseClient, context: @escaping () -> AccountActivityReadContext?, preview: Bool = false, readPolicy: AccountActivityReadPolicy = .approvedFollowersV1) { self.client = client; currentContext = context; self.preview = preview; self.readPolicy = readPolicy }
    var context: AccountActivityReadContext? {
        guard let value = currentContext(), client.auth.currentSession?.user.id == value.viewerID,
              !AccountDeletionWriteFence.shared.isRetired(value.viewerID) else { return nil }
        return value
    }
    private func gate() async throws {
        guard !preview || readPolicy == .approvedFollowersV1 else { throw AccountActivityNativeInboxError.disabled }
        if preview {
            guard let initial = context else { throw AccountActivityNativeInboxError.disabled }
            let capability = try await AccountActivityPreviewService(client: client, owner: initial.viewerID).capability()
            guard capability.enabled, context == initial else { throw AccountActivityNativeInboxError.staleContext }
            return
        }
        guard readPolicy.inboxProductionReady, context != nil else { throw AccountActivityNativeInboxError.disabled }
    }
    func inbox(limit: Int) async throws -> Data {
        try await gate()
        struct Params: Encodable { let p_limit: Int }
        return try await client.rpc(preview ? "soom_activity_native_inbox_preview_v1" : readPolicy.interactionRPC("soom_activity_native_inbox_candidate_v1"), params: Params(p_limit: limit)).execute().data
    }
    func state(commentID: UUID, action: AccountActivityNativeInboxAction) async throws -> Data {
        try await gate()
        struct Params: Encodable { let p_comment_id: UUID; let p_action: String }
        return try await client.rpc(preview ? "soom_activity_native_event_state_preview_v1" : readPolicy.interactionRPC("soom_activity_native_event_state_candidate_v1"), params: Params(p_comment_id: commentID, p_action: action.rawValue)).execute().data
    }
    func card(id: UUID) async throws -> AccountActivityCardEnvelope {
        try await gate()
        struct Params: Encodable { let p_card_id: UUID }
        return try await client.rpc(try readPolicy.cardRPC(preview: preview), params: Params(p_card_id: id)).execute().value
    }
}
@MainActor final class AccountActivityNativeInboxAdapter {
    private let transport: any AccountActivityNativeInboxTransport
    private let policy: AccountActivityReadPolicy
    private let fixture: Bool
    private let preview: Bool
    private var mutationInFlight = false
    init(transport: any AccountActivityNativeInboxTransport, preview: Bool = false) { self.transport = transport; policy = transport.readPolicy; fixture = false; self.preview = preview }
    #if DEBUG
    init(fixtureTransport: any AccountActivityNativeInboxTransport) { transport = fixtureTransport; policy = fixtureTransport.readPolicy; fixture = true; preview = false }
    #endif
    static func makeLive(client: SupabaseClient, context: @escaping () -> AccountActivityReadContext?, preview: Bool = false, readPolicy: AccountActivityReadPolicy = .approvedFollowersV1) -> AccountActivityNativeInboxAdapter {
        AccountActivityNativeInboxAdapter(transport: SupabaseAccountActivityNativeInboxTransport(client: client, context: context, preview: preview, readPolicy: readPolicy), preview: preview)
    }
    private func check(_ expected: AccountActivityReadContext) throws {
        guard !preview || policy == .approvedFollowersV1 else { throw AccountActivityNativeInboxError.disabled }
        guard fixture || (preview && policy == .approvedFollowersV1) || policy.inboxProductionReady else { throw AccountActivityNativeInboxError.disabled }
        guard transport.readPolicy == policy, transport.context == expected, !AccountDeletionWriteFence.shared.isRetired(expected.viewerID),
              !Task.isCancelled else { throw AccountActivityNativeInboxError.staleContext }
    }
    func load(context: AccountActivityReadContext, limit: Int = 100, now: Date = Date()) async throws -> [AccountActivityNativeInboxRow] {
        try await loadSnapshot(context: context, limit: limit, now: now).rows
    }
    func unreadCount(context: AccountActivityReadContext) async throws -> Int {
        try await loadSnapshot(context: context, limit: 1).unreadCount
    }
    func loadSnapshot(context: AccountActivityReadContext, limit: Int = 100, now: Date = Date()) async throws -> AccountActivityNativeInboxSnapshot {
        try check(context)
        guard (1...100).contains(limit) else { throw AccountActivityNativeInboxError.invalidReceipt }
        let data = try await transport.inbox(limit: limit); try check(context)
        let envelope = try AccountActivityNativeInboxEnvelope.decode(data)
        return AccountActivityNativeInboxSnapshot(rows: try envelope.validated(viewer: context.viewerID, limit: limit, fixture: fixture, now: now, preview: preview, expectedPolicy: policy), unreadCount: envelope.unreadCount)
    }
    func mutate(_ event: AccountActivityNativeInboxRow, action: AccountActivityNativeInboxAction, context: AccountActivityReadContext, now: Date = Date()) async throws -> AccountActivityNativeInboxSnapshot {
        try check(context)
        guard !mutationInFlight else { throw AccountActivityNativeInboxError.unavailable }
        mutationInFlight = true; defer { mutationInFlight = false }
        // State RPC itself checks recipient and fresh source access, including undo.
        // No automatic retry after ambiguous transport failure; each action is idempotent.
        let data = try await transport.state(commentID: event.commentID, action: action); try check(context)
        let receipt = try AccountActivityNativeInboxEnvelope.decoder().decode(AccountActivityNativeInboxStateReceipt.self, from: data)
        guard receipt.version == policy.rawValue, receipt.viewerID == context.viewerID, receipt.sourceKind == policy.nativeSourceKind,
              receipt.eventID == event.eventID, receipt.commentID == event.commentID, receipt.releaseReady == !(fixture || preview),
              [receipt.readAt, receipt.hiddenAt].allSatisfy({ $0.map { $0.timeIntervalSince1970.isFinite && $0 >= event.createdAt && $0 <= Date() } ?? true }) else { throw AccountActivityNativeInboxError.invalidReceipt }
        switch action {
        case .markRead: guard receipt.readAt != nil else { throw AccountActivityNativeInboxError.invalidReceipt }
        case .markUnread: guard receipt.readAt == nil else { throw AccountActivityNativeInboxError.invalidReceipt }
        case .hide: guard receipt.hiddenAt != nil else { throw AccountActivityNativeInboxError.invalidReceipt }
        case .undoHide: guard receipt.hiddenAt == nil else { throw AccountActivityNativeInboxError.invalidReceipt }
        }
        let snapshot = try await loadSnapshot(context: context, now: max(now, Date()))
        if let row = snapshot.rows.first(where: { $0.eventID == event.eventID }) {
            guard row.commentID == event.commentID, row.cardID == event.cardID, row.actorID == event.actorID,
                  row.readAt == receipt.readAt, receipt.hiddenAt == nil else { throw AccountActivityNativeInboxError.invalidReceipt }
        }
        // Missing row can mean fresh revocation or pagination, never fabricate it.
        return snapshot
    }
    func open(_ event: AccountActivityNativeInboxRow, context: AccountActivityReadContext, now: Date = Date()) async throws -> AccountActivityFeedRow {
        // A stale/deleted mention cannot grant access merely because the card remains public.
        let fresh = try await load(context: context, now: now)
        guard fresh.contains(where: { $0.eventID == event.eventID && $0.commentID == event.commentID && $0.cardID == event.cardID && $0.actorID == event.actorID && $0.reason == event.reason }) else { throw AccountActivityNativeInboxError.unavailable }
        let receipt = try await transport.card(id: event.cardID); try check(context)
        guard receipt.releaseReady == !(fixture || preview),
              let row = try receipt.validateCandidate(expectedCardID: event.cardID, requestViewerID: context.viewerID,
                currentViewerID: transport.context?.viewerID, requestGeneration: context.generation,
                currentGeneration: transport.context?.generation ?? -1, latestPermittedDate: now, expectedPolicy: policy) else { throw AccountActivityNativeInboxError.unavailable }
        let final = try await load(context: context, now: now)
        guard final.contains(where: { $0.eventID == event.eventID && $0.commentID == event.commentID && $0.cardID == event.cardID && $0.actorID == event.actorID && $0.reason == event.reason }) else { throw AccountActivityNativeInboxError.unavailable }
        return row
    }
}

/// Host must dismiss any presented native sheet when context changes. Selection is
/// a freshly validated projection row, never a UUID for the legacy post callback.
struct AccountActivityNativeInboxSection: View {
    let adapter: AccountActivityNativeInboxAdapter
    let context: AccountActivityReadContext?
    let onSelect: (AccountActivityFeedRow) -> Void
    var onRead: () -> Void = {}
    @State private var hiddenEvent: AccountActivityNativeInboxRow?
    @State private var rows: [AccountActivityNativeInboxRow] = []
    @State private var loadedContext: AccountActivityReadContext?
    @State private var message: String?
    @State private var opening = false
    private var key: String { context.map { "\($0.viewerID):\($0.generation):\($0.safetyRevision)" } ?? "signed-out" }
    var body: some View {
        Section {
            if loadedContext == context, context != nil {
                ForEach(rows) { row in
                    Button { Task { await open(row) } } label: {
                        HStack {
                            Image(systemName: row.readAt == nil ? "circle.fill" : "circle").font(.caption2)
                            VStack(alignment: .leading) {
                                Text(row.reason == "mention" ? "운동 댓글에서 회원님을 언급했어요" : row.reason == "reply" ? "운동 댓글에 답글이 달렸어요" : "운동에 댓글이 달렸어요")
                                Text(SOOMKoreanRelativeTime.text(row.createdAt)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.disabled(opening)
                    .accessibilityIdentifier("notifications.native.row.\(row.eventID)")
                    .contextMenu {
                        Button(row.readAt == nil ? "읽음으로 표시" : "읽지 않음으로 표시") { Task { await change(row, action: row.readAt == nil ? .markRead : .markUnread) } }
                        Button("알림 숨기기") { Task { await change(row, action: .hide) } }
                    }
                }
                if let hiddenEvent { Button("숨기기 취소") { Task { await change(hiddenEvent, action: .undoHide) } }.disabled(opening).accessibilityIdentifier("notifications.native.undo") }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            } else if context != nil {
                // A completely empty lazy List Section may never mount its task.
                // Keep a real row until loading resolves, without showing stale content.
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                else { ProgressView("운동 알림 확인 중").accessibilityIdentifier("notifications.native.loading") }
            }
        }.task(id: key) { await reload() }
    }
    @MainActor private func reload() async {
        // List can remount the Section task when a last row becomes an undo row.
        // Do not erase a confirmed hide receipt within the same privacy context.
        if let context, loadedContext == context { return }
        rows = []; loadedContext = nil; message = nil; opening = false; hiddenEvent = nil
        guard let expected = context else { return }
        do {
            let result = try await adapter.load(context: expected)
            guard !Task.isCancelled, context == expected else { return }
            rows = result; loadedContext = expected
        } catch {
            guard context == expected, !Task.isCancelled else { return }
            rows = []; loadedContext = nil; message = "운동 알림을 확인하지 못했어요."
            #if DEBUG && targetEnvironment(simulator)
            if AccountActivityNativeInboxUIFixture.enabled { print("NATIVE_INBOX_QA load_error \(String(describing: error))") }
            #endif
        }
    }
    @MainActor private func open(_ event: AccountActivityNativeInboxRow) async {
        guard !opening, let expected = context, loadedContext == expected else { return }
        opening = true; defer { opening = false }
        do {
            let row = try await adapter.open(event, context: expected)
            guard !Task.isCancelled, context == expected else { return }
            if event.readAt == nil {
                let snapshot = try await adapter.mutate(event, action: .markRead, context: expected)
                guard context == expected, !Task.isCancelled else { return }
                rows = snapshot.rows; onRead()
                // Revalidate access again after the mutation before navigation.
                let current = try await adapter.open(event, context: expected)
                guard context == expected, !Task.isCancelled else { return }
                onSelect(current)
            } else { onSelect(row) }
        } catch { rows = []; message = "공개 범위가 바뀌었거나 알림을 확인할 수 없어요." }
    }
    @MainActor private func change(_ event: AccountActivityNativeInboxRow, action: AccountActivityNativeInboxAction) async {
        guard !opening, let expected = context, loadedContext == expected else { return }
        opening = true; defer { opening = false }
        do {
            let snapshot = try await adapter.mutate(event, action: action, context: expected)
            guard context == expected, !Task.isCancelled else { return }
            rows = snapshot.rows; hiddenEvent = action == .hide ? event : nil; message = nil; onRead()
            #if DEBUG && targetEnvironment(simulator)
            if AccountActivityNativeInboxUIFixture.enabled { print("NATIVE_INBOX_QA state_success \(action.rawValue) rows=\(rows.count) undo=\(hiddenEvent != nil)") }
            #endif
        } catch {
            #if DEBUG && targetEnvironment(simulator)
            if AccountActivityNativeInboxUIFixture.enabled { print("NATIVE_INBOX_QA state_error \(action.rawValue) \(String(describing: error))") }
            #endif
            guard context == expected, !Task.isCancelled else { return }
            rows = []; hiddenEvent = nil
            message = "변경 결과를 확인하지 못했어요. 다시 조회해 주세요."
            // Refresh only; never retry the write or claim it failed remotely.
            if let snapshot = try? await adapter.loadSnapshot(context: expected), context == expected, !Task.isCancelled { rows = snapshot.rows; onRead() }
        }
    }

}

#if DEBUG && targetEnvironment(simulator)
/// Opt-in UI fixture. No Supabase client, file journal, or production transport.
@MainActor final class AccountActivityNativeInboxUIFixture: AccountActivityNativeInboxTransport {
    static var enabled: Bool { ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_NATIVE_INBOX_QA"] == "1" }
    private let current: () -> AccountActivityReadContext?
    private var readAt: Date?
    private var hidden = false
    private let created = Date().addingTimeInterval(-600)
    static let eventID = UUID(uuidString: "A1100000-0000-0000-0000-000000000001")!
    static let commentID = UUID(uuidString: "A1100000-0000-0000-0000-000000000002")!
    static let cardID = UUID(uuidString: "A1100000-0000-0000-0000-000000000003")!
    static let actorID = UUID(uuidString: "A1100000-0000-0000-0000-000000000004")!
    static let canonicalID = UUID(uuidString: "A1100000-0000-0000-0000-000000000005")!
    init(context: @escaping () -> AccountActivityReadContext?) { current = context }
    var context: AccountActivityReadContext? { Self.enabled ? current() : nil }
    private func owner() throws -> UUID {
        guard Self.enabled, let viewer = context?.viewerID, viewer == ReviewDemoMode.userID else { throw AccountActivityNativeInboxError.disabled }
        return viewer
    }
    private func dateValue(_ date: Date?) -> Any { date.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull() }
    func inbox(limit: Int) async throws -> Data {
        let viewer = try owner()
        guard (1...100).contains(limit) else { throw AccountActivityNativeInboxError.invalidReceipt }
        let row: [String: Any] = ["event_id":Self.eventID.uuidString,"comment_id":Self.commentID.uuidString,
            "card_id":Self.cardID.uuidString,"actor_id":Self.actorID.uuidString,"reason":"mention",
            "created_at":dateValue(created),"read_at":dateValue(readAt)]
        return try JSONSerialization.data(withJSONObject: ["version":1,"viewer_id":viewer.uuidString,"source_kind":"activity_native_v1",
            "backing":"native","rows":hidden ? [] : [row],"push_delivery":"candidate_disabled","release_ready":false,
            "unread_count":hidden || readAt != nil ? 0 : 1])
    }
    func card(id: UUID) async throws -> AccountActivityCardEnvelope {
        let viewer = try owner()
        guard id == Self.cardID else { throw AccountActivityNativeInboxError.unavailable }
        return try JSONDecoder().decode(AccountActivityCardEnvelope.self, from: JSONSerialization.data(withJSONObject: [
            "version":1,"viewer_id":viewer.uuidString,"release_ready":false,"row":["card_id":id.uuidString,
                "canonical_id":Self.canonicalID.uuidString,"owner_id":Self.actorID.uuidString,"sport":"running",
                "activity_at":dateValue(created.addingTimeInterval(-1800)),"duration_seconds":1800,"distance_meters":5000,"revision":1]]))
    }
    func state(commentID: UUID, action: AccountActivityNativeInboxAction) async throws -> Data {
        let viewer = try owner()
        guard commentID == Self.commentID else { throw AccountActivityNativeInboxError.unavailable }
        switch action {
        case .markRead: if readAt == nil { readAt = Date() }
        case .markUnread: readAt = nil
        case .hide: hidden = true
        case .undoHide: hidden = false
        }
        return try JSONSerialization.data(withJSONObject: ["version":1,"viewer_id":viewer.uuidString,"source_kind":"activity_native_v1",
            "event_id":Self.eventID.uuidString,"comment_id":commentID.uuidString,"read_at":dateValue(readAt),
            "hidden_at":hidden ? dateValue(Date()) : NSNull(),"release_ready":false])
    }
}
#endif
