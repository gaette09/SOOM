import Foundation
import SwiftUI
import Supabase
import UIKit

enum ProfileSocialInboxQA {
    static var enabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_PROFILE_SOCIAL_INBOX_QA"] == "1"
        #else
        return false
        #endif
    }
}

struct ProfileSocialInboxEvent: Decodable, Identifiable {
    let source_kind: String
    let event_id: UUID
    let recipient_id: UUID
    let actor_id: UUID
    let card_id: UUID
    let comment_id: UUID?
    let reason: String
    let created_at: String
    let read_at: String?
    let receipt: ProfileActivitySocialReceipt
    let actor_profile: FeedProfileDTO?
    var id: String { source_kind + ":" + event_id.uuidString.lowercased() }
}
struct ProfileSocialInboxEnvelope: Decodable {
    let version: Int
    let viewer_id: UUID
    let release_ready: Bool
    let rows: [ProfileSocialInboxEvent]
    let unread_count: Int
    let push_delivery: String
}
struct ProfileSocialInboxState: Decodable {
    let version: Int
    let viewer_id: UUID
    let source_kind: String
    let event_id: UUID
    let card_id: UUID
    let receipt: ProfileActivitySocialReceipt
    let read_at: String?
    let hidden_at: String?
    let release_ready: Bool
}
@MainActor protocol ProfileSocialInboxTransport {
    func inbox(limit: Int) async throws -> Data
    func state(source: String, eventID: UUID, action: String) async throws -> Data
    func card(id: UUID) async throws -> AccountActivityCardEnvelope
}
@MainActor struct SupabaseProfileSocialInboxTransport: ProfileSocialInboxTransport {
    let client: SupabaseClient
    func inbox(limit: Int) async throws -> Data {
        struct Params: Encodable { let p_limit: Int }
        return try await client.rpc("soom_activity_social_inbox_candidate_v2", params: Params(p_limit: limit)).execute().data
    }
    func state(source: String, eventID: UUID, action: String) async throws -> Data {
        struct Params: Encodable { let p_source_kind: String; let p_event_id: UUID; let p_action: String }
        return try await client.rpc("soom_activity_social_event_state_candidate_v2", params: Params(p_source_kind: source, p_event_id: eventID, p_action: action)).execute().data
    }
    func card(id: UUID) async throws -> AccountActivityCardEnvelope {
        struct Params: Encodable { let p_card_id: UUID }
        return try await client.rpc("soom_activity_card_candidate_v2", params: Params(p_card_id: id)).execute().value
    }
}
@MainActor final class ProfileSocialInboxAdapter {
    static let sources: Set<String> = ["legacy", "approved_v2", "profile_social_v2"]
    private let transport: any ProfileSocialInboxTransport
    private let context: () -> AccountActivityReadContext?
    private let fixture: Bool
    private var writing = false
    init(transport: any ProfileSocialInboxTransport, context: @escaping () -> AccountActivityReadContext?) {
        self.transport = transport; self.context = context; fixture = false
    }
    #if DEBUG
    private init(transport: any ProfileSocialInboxTransport, context: @escaping () -> AccountActivityReadContext?, fixture: Bool) {
        self.transport = transport; self.context = context; self.fixture = fixture
    }
    static func localFixture(transport: any ProfileSocialInboxTransport, context: @escaping () -> AccountActivityReadContext?) -> ProfileSocialInboxAdapter {
        .init(transport: transport, context: context, fixture: true)
    }
    #endif
    static func live(client: SupabaseClient) -> ProfileSocialInboxAdapter {
        .init(transport: SupabaseProfileSocialInboxTransport(client: client), context: {
            let safety = CommunitySafetyStore.shared
            guard UIApplication.shared.applicationState == .active, safety.canUseSocial,
                  let viewer = safety.viewerID, client.auth.currentSession?.user.id == viewer,
                  !AccountDeletionWriteFence.shared.isRetired(viewer) else { return nil }
            return .init(viewerID: viewer, generation: safety.accountGeneration, safetyRevision: safety.revision)
        })
    }
    private func begin() throws -> AccountActivityReadContext {
        guard fixture || ProfileActivitySocialReleaseGate.productionReady, let c = context(),
              !Task.isCancelled, !AccountDeletionWriteFence.shared.isRetired(c.viewerID) else { throw ProfileActivitySocialError.accountChanged }
        return c
    }
    private func check(_ c: AccountActivityReadContext) throws {
        guard context() == c, !Task.isCancelled, !AccountDeletionWriteFence.shared.isRetired(c.viewerID) else { throw ProfileActivitySocialError.accountChanged }
    }
    private func receipt(_ r: ProfileActivitySocialReceipt, card: UUID, context c: AccountActivityReadContext) throws {
        guard r.version == 2, r.viewer_id == c.viewerID, r.card_id == card, r.release_ready == !fixture,
              r.projection_revision > 0, r.projection_revision < Int64.max, r.profile_revision > 0, r.profile_revision < Int64.max,
              r.hasValidRouting else { throw ProfileActivitySocialError.malformed }
    }
    private func event(_ e: ProfileSocialInboxEvent, context c: AccountActivityReadContext, now: Date) throws {
        try receipt(e.receipt, card: e.card_id, context: c)
        guard Self.sources.contains(e.source_kind), e.recipient_id == c.viewerID, e.actor_id != c.viewerID,
              ["comment", "reply", "mention", "reaction"].contains(e.reason),
              let date = ProfileActivitySocialAdapter.date(e.created_at), date <= now,
              e.read_at.map({ ProfileActivitySocialAdapter.date($0).map { $0 >= date && $0 <= now } == true }) ?? true,
              e.actor_profile.map({ $0.id == e.actor_id && !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true else { throw ProfileActivitySocialError.malformed }
    }
    func load(limit: Int = 100, now: Date = Date()) async throws -> ProfileSocialInboxEnvelope {
        let c = try begin()
        guard (1...100).contains(limit) else { throw ProfileActivitySocialError.invalidRequest }
        let data = try await transport.inbox(limit: limit); try check(c)
        let value = try JSONDecoder().decode(ProfileSocialInboxEnvelope.self, from: data)
        guard value.version == 2, value.viewer_id == c.viewerID, value.release_ready == !fixture,
              value.push_delivery == "unchanged_no_new_scope_push", value.unread_count >= 0,
              value.rows.count <= limit, Set(value.rows.map(\.id)).count == value.rows.count,
              value.unread_count >= value.rows.filter({ $0.read_at == nil }).count else { throw ProfileActivitySocialError.malformed }
        var previous: (Date, String, String)?
        for row in value.rows {
            try event(row, context: c, now: now)
            guard let date = ProfileActivitySocialAdapter.date(row.created_at) else { throw ProfileActivitySocialError.malformed }
            let id = row.event_id.uuidString.lowercased()
            if let p = previous {
                guard date < p.0 || (date == p.0 && (row.source_kind > p.1 || (row.source_kind == p.1 && id > p.2))) else { throw ProfileActivitySocialError.malformed }
            }
            previous = (date, row.source_kind, id)
        }
        return value
    }
    func change(_ e: ProfileSocialInboxEvent, action: String) async throws -> ProfileSocialInboxEnvelope {
        let c = try begin(); try event(e, context: c, now: Date())
        guard !writing, ["mark_read", "mark_unread", "hide", "undo_hide"].contains(action) else { throw ProfileActivitySocialError.pendingWrite }
        writing = true; defer { writing = false }
        let data = try await transport.state(source: e.source_kind, eventID: e.event_id, action: action); try check(c)
        let value = try JSONDecoder().decode(ProfileSocialInboxState.self, from: data)
        try receipt(value.receipt, card: e.card_id, context: c)
        guard value.version == 2, value.viewer_id == c.viewerID, value.source_kind == e.source_kind, value.event_id == e.event_id,
              value.card_id == e.card_id, value.release_ready == !fixture,
              value.receipt.owner_id == e.receipt.owner_id, value.receipt.canonical_id == e.receipt.canonical_id,
              value.receipt.backing == e.receipt.backing, value.receipt.source_id == e.receipt.source_id, value.receipt.source_revision == e.receipt.source_revision,
              value.receipt.read_sources == e.receipt.read_sources, value.receipt.write_backing == e.receipt.write_backing,
              [value.read_at, value.hidden_at].allSatisfy({ $0.map { ProfileActivitySocialAdapter.date($0).map { $0 <= Date() && $0 >= (ProfileActivitySocialAdapter.date(e.created_at) ?? .distantFuture) } == true } ?? true }) else { throw ProfileActivitySocialError.malformed }
        switch action {
        case "mark_read": guard value.read_at != nil else { throw ProfileActivitySocialError.malformed }
        case "mark_unread": guard value.read_at == nil else { throw ProfileActivitySocialError.malformed }
        case "hide": guard value.hidden_at != nil else { throw ProfileActivitySocialError.malformed }
        default: guard value.hidden_at == nil else { throw ProfileActivitySocialError.malformed }
        }
        let result = try await load(); try check(c)
        if let current = result.rows.first(where: { $0.id == e.id }) {
            guard value.hidden_at == nil, current.read_at == value.read_at else { throw ProfileActivitySocialError.changed }
        }
        return result
    }
    func open(_ e: ProfileSocialInboxEvent) async throws -> AccountActivityFeedRow {
        let c = try begin()
        let fresh = try await load(); try check(c)
        guard let event = fresh.rows.first(where: { $0.id == e.id }),
              event.card_id == e.card_id, event.actor_id == e.actor_id, event.comment_id == e.comment_id, event.reason == e.reason,
              event.receipt.owner_id == e.receipt.owner_id, event.receipt.canonical_id == e.receipt.canonical_id,
              event.receipt.backing == e.receipt.backing, event.receipt.source_id == e.receipt.source_id, event.receipt.expected == e.receipt.expected else { throw ProfileActivitySocialError.changed }
        let card = try await transport.card(id: e.card_id); try check(c)
        guard card.releaseReady == !fixture,
              let row = try card.validateCandidate(expectedCardID: e.card_id, requestViewerID: c.viewerID,
                currentViewerID: context()?.viewerID, requestGeneration: c.generation, currentGeneration: context()?.generation ?? -1,
                latestPermittedDate: Date(), expectedOwnerID: event.receipt.owner_id, expectedPolicy: .profileOnlyV2),
              row.canonicalID == event.receipt.canonical_id, row.revision == event.receipt.projection_revision else { throw ProfileActivitySocialError.changed }
        let final = try await load(); try check(c)
        guard final.rows.contains(where: {
            $0.id == event.id && $0.card_id == row.cardID && $0.actor_id == event.actor_id &&
            $0.comment_id == event.comment_id && $0.reason == event.reason &&
            $0.receipt.projection_revision == row.revision && $0.receipt.owner_id == event.receipt.owner_id &&
            $0.receipt.canonical_id == event.receipt.canonical_id && $0.receipt.backing == event.receipt.backing &&
            $0.receipt.source_id == event.receipt.source_id && $0.receipt.expected == event.receipt.expected
        }) else { throw ProfileActivitySocialError.changed }
        return row
    }
}

/// Original notification rows/states are not mutated by this section. Event keys
/// keep their source namespace; canonical card IDs never enter legacy navigation.
struct ProfileSocialInboxSelection: Identifiable {
    let row: AccountActivityFeedRow
    let reaction: Bool
    let context: AccountActivityReadContext
    var id: UUID { row.cardID }
}

struct ProfileSocialInboxSection: View {
    var refreshRevision: Int
    var onRead: () -> Void = {}
    var onSelect: (ProfileSocialInboxSelection) -> Void = { _ in }
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.scenePhase) private var scene
    @State private var adapter: ProfileSocialInboxAdapter?
    @State private var rows: [ProfileSocialInboxEvent] = []
    @State private var hidden: ProfileSocialInboxEvent?
    @State private var loadedKey: String?
    @State private var message: String?
    @State private var busy = false
    private var key: String { "\(safety.viewerID?.uuidString ?? "none"):\(safety.accountGeneration):\(safety.revision):\(scene == .active):\(refreshRevision)" }
    var body: some View {
        Section("운동 알림") {
            if loadedKey == key, scene == .active {
                ForEach(rows) { event in
                    Button { Task { await open(event) } } label: {
                        HStack {
                            Image(systemName: event.read_at == nil ? "circle.fill" : "circle").font(.caption2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(label(event))
                                if let date = ProfileActivitySocialAdapter.date(event.created_at) { Text(SOOMKoreanRelativeTime.text(date)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }.disabled(busy).accessibilityIdentifier("notifications.profileSocial.row.\(event.id)")
                    .accessibilityValue(event.read_at == nil ? "읽지 않음" : "읽음")
                    .contextMenu {
                        Button(event.read_at == nil ? "읽음으로 표시" : "읽지 않음으로 표시") { Task { await change(event, action: event.read_at == nil ? "mark_read" : "mark_unread") } }
                        Button("알림 숨기기") { Task { await change(event, action: "hide") } }
                    }
                }
                if rows.isEmpty { Text("현재 확인되는 운동 알림이 없어요.").foregroundStyle(.secondary) }
                if let hidden { Button("숨기기 취소") { Task { await change(hidden, action: "undo_hide") } }.disabled(busy).accessibilityIdentifier("notifications.profileSocial.undo") }
                if let message { Text(message).font(.caption) }
            } else if let message {
                Text(message).font(.caption)
                Button("운동 알림 다시 확인") { Task { await reload() } }.disabled(busy)
            } else { ProgressView("운동 알림 확인 중") }
        }
        .task(id: key) { await reload() }

    }
    private func label(_ e: ProfileSocialInboxEvent) -> String {
        let name = e.actor_profile?.displayName ?? "회원"
        switch e.reason {
        case "mention": return "\(name)님이 운동 댓글에서 회원님을 언급했어요"
        case "reply": return "\(name)님이 운동 댓글에 답글을 남겼어요"
        case "reaction": return "\(name)님이 운동을 응원했어요"
        default: return "\(name)님이 운동에 댓글을 남겼어요"
        }
    }
    @MainActor private func reload() async {
        rows = []; hidden = nil; loadedKey = nil; message = nil; adapter = nil
        let expected = key
        guard scene == .active, safety.canUseSocial, ProfileActivitySocialReleaseGate.productionReady else { return }
        let api: ProfileSocialInboxAdapter
        #if DEBUG && targetEnvironment(simulator)
        if ProfileSocialInboxQA.enabled {
            api = .localFixture(transport: ProfileSocialInboxUIFixture.shared, context: {
                guard safety.canUseSocial, scene == .active, safety.viewerID == ReviewDemoMode.userID else { return nil }
                return .init(viewerID: ReviewDemoMode.userID, generation: safety.accountGeneration, safetyRevision: safety.revision)
            })
        } else {
            guard let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { return }
            api = ProfileSocialInboxAdapter.live(client: client)
        }
        #else
        guard let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { return }
        api = ProfileSocialInboxAdapter.live(client: client)
        #endif
        do {
            let result = try await api.load()
            guard !Task.isCancelled, key == expected else { return }
            adapter = api; rows = result.rows; loadedKey = expected
        } catch { if key == expected, !Task.isCancelled { message = "운동 알림을 확인하지 못했어요. 공개 범위와 연결을 확인해 주세요." } }
    }
    @MainActor private func change(_ event: ProfileSocialInboxEvent, action: String) async {
        guard !busy, let adapter, loadedKey == key else { return }
        let expected = key; busy = true; defer { busy = false }
        do {
            let result = try await adapter.change(event, action: action)
            guard expected == key, !Task.isCancelled else { return }
            rows = result.rows; hidden = action == "hide" ? event : nil; message = nil; onRead()
        } catch {
            guard expected == key, !Task.isCancelled else { return }
            rows = []; hidden = nil; message = "변경 결과를 확인하지 못했어요. 저장 상태를 다시 확인합니다."
            if let result = try? await adapter.load(), expected == key, !Task.isCancelled { rows = result.rows; onRead() }
        }
    }
    @MainActor private func open(_ event: ProfileSocialInboxEvent) async {
        guard !busy, let adapter, loadedKey == key else { return }
        let expected = key; busy = true; defer { busy = false }
        do {
            _ = try await adapter.open(event)
            if event.read_at == nil {
                let result = try await adapter.change(event, action: "mark_read")
                guard expected == key, !Task.isCancelled else { return }
                rows = result.rows; onRead()
            }
            let row = try await adapter.open(event)
            guard expected == key, !Task.isCancelled else { return }
            guard let viewer = safety.viewerID else { return }
            onSelect(.init(row: row, reaction: event.reason == "reaction",
                context: .init(viewerID: viewer, generation: safety.accountGeneration, safetyRevision: safety.revision)))
        } catch { if expected == key, !Task.isCancelled { rows = []; message = "공개 범위가 바뀌었거나 알림을 열 수 없어요." } }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Isolated synthetic notification states. No UserDefaults, production notification
/// rows, push delivery, or real Supabase transport is read or modified here.
@MainActor private final class ProfileSocialInboxUIFixture: ProfileSocialInboxTransport {
    static let shared = ProfileSocialInboxUIFixture()
    private let cardID = UUID(uuidString:"00000000-0000-4000-8000-000000000161")!
    private let canonicalID = UUID(uuidString:"00000000-0000-4000-8000-000000000162")!
    private let actorID = UUID(uuidString:"00000000-0000-4000-8000-000000000157")!
    private let eventIDs = [UUID(uuidString:"00000000-0000-4000-8000-000000000163")!,
                            UUID(uuidString:"00000000-0000-4000-8000-000000000164")!,
                            UUID(uuidString:"00000000-0000-4000-8000-000000000165")!]
    private let sources = ["profile_social_v2","approved_v2","legacy"]
    private let started = Date().addingTimeInterval(-120)
    private var read: [UUID:String] = [:]
    private var hidden: [UUID:String] = [:]
    private init() {
        read[eventIDs[2]] = ISO8601DateFormatter().string(from:started.addingTimeInterval(40))
    }
    private var receipt: ProfileActivitySocialReceipt {
        .init(version:2,viewer_id:ReviewDemoMode.userID,card_id:cardID,owner_id:actorID,canonical_id:canonicalID,
              projection_revision:1,profile_revision:1,backing:"legacy",source_id:canonicalID,release_ready:false, write_backing:"legacy", read_sources:[.init(source_kind:"legacy",source_id:canonicalID)], source_revision:String(repeating:"a",count:32))
    }
    private func object<T:Encodable>(_ value:T) throws -> Any { try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) }
    private func checkedIndex(source:String,id:UUID) throws -> Int {
        guard ProfileSocialInboxQA.enabled, let index = eventIDs.firstIndex(of:id), sources[index] == source else { throw ProfileActivitySocialError.invalidRequest }
        return index
    }
    private func row(_ index:Int) throws -> [String:Any] {
        let id = eventIDs[index]
        return ["source_kind":sources[index],"event_id":id.uuidString,"recipient_id":ReviewDemoMode.userID.uuidString,
                "actor_id":actorID.uuidString,"card_id":cardID.uuidString,"comment_id":"00000000-0000-4000-8000-000000000158",
                "reason":index == 0 ? "reply" : "comment",
                "created_at":ISO8601DateFormatter().string(from:started.addingTimeInterval(Double(2-index)*10)),
                "read_at":read[id] as Any? ?? NSNull(),"receipt":try object(receipt),
                "actor_profile":["id":actorID.uuidString,"display_name":index == 2 ? "기존 알림 친구" : "새 운동 친구",
                                 "handle":"soom_test","avatar_path":NSNull()]]
    }
    func inbox(limit:Int) async throws -> Data {
        guard ProfileSocialInboxQA.enabled else { throw ProfileActivitySocialError.disabled }
        let visible = eventIDs.indices.filter { hidden[eventIDs[$0]] == nil }
        return try JSONSerialization.data(withJSONObject:["version":2,"viewer_id":ReviewDemoMode.userID.uuidString,"release_ready":false,
            "rows":try visible.prefix(limit).map(row),"unread_count":visible.filter { read[eventIDs[$0]] == nil }.count,
            "push_delivery":"unchanged_no_new_scope_push"])
    }
    func state(source:String,eventID:UUID,action:String) async throws -> Data {
        _ = try checkedIndex(source:source,id:eventID)
        let now = ISO8601DateFormatter().string(from:Date())
        switch action {
        case "mark_read": if read[eventID] == nil { read[eventID] = now }
        case "mark_unread": read.removeValue(forKey:eventID)
        case "hide": if hidden[eventID] == nil { hidden[eventID] = now }
        case "undo_hide": hidden.removeValue(forKey:eventID)
        default: throw ProfileActivitySocialError.invalidRequest
        }
        return try JSONSerialization.data(withJSONObject:["version":2,"viewer_id":ReviewDemoMode.userID.uuidString,
            "source_kind":source,"event_id":eventID.uuidString,"card_id":cardID.uuidString,"receipt":object(receipt),
            "read_at":read[eventID] as Any? ?? NSNull(),"hidden_at":hidden[eventID] as Any? ?? NSNull(),"release_ready":false])
    }
    func card(id:UUID) async throws -> AccountActivityCardEnvelope {
        guard ProfileSocialInboxQA.enabled, id == cardID else { throw ProfileActivitySocialError.changed }
        let row = AccountActivityFeedRow(cardID:cardID,canonicalID:canonicalID,ownerID:actorID,sport:"running",
            activityAt:ISO8601DateFormatter().string(from:started.addingTimeInterval(-3600)),durationSeconds:600,distanceMeters:1500,revision:1,readPolicy:.profileOnlyV2)
        return .init(version:2,viewerID:ReviewDemoMode.userID,row:row,releaseReady:false)
    }
}
#endif
