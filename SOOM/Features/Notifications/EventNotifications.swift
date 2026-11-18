import Foundation
import CoreFoundation
import SwiftUI
import Supabase

// Enable only in a separately reviewed app/server rollout. No persisted opt-in override.
enum EventNotificationFeature { static let enabled = false }
enum EventNotificationError: Error { case unavailable, accountChanged, invalidContract }
enum EventCategory: String, Codable { case event, marketing }
enum EventDestination: String, Codable { case none, home }
struct EventPreferences: Codable, Equatable {
    var eventConsent = false, marketingConsent = false, eventPush = false, marketingPush = false
    var consentRevision: Int64 = 0, settingsRevision: Int64 = 0
    var proofVersion = "event-consent-v1"
    var valid: Bool { proofVersion == "event-consent-v1" && consentRevision >= 0 && settingsRevision >= 0
        && (!marketingConsent || eventConsent) && (!eventPush || eventConsent) && (!marketingPush || (marketingConsent && eventPush)) }
}
struct EventRegistration: Codable, Equatable { let registryId: UUID; let registrationId: UUID; let registrationEpoch: Int64 }
struct EventInboxItem: Codable, Identifiable, Equatable {
    struct Destination: Codable, Equatable { let kind: EventDestination }
    let id: UUID; let campaignId: UUID; let recipientId: UUID; let category: EventCategory
    let title: String; let body: String; let destination: Destination; let createdAt: String; var readAt: String?
}
struct EventInboxPage: Codable { let notifications: [EventInboxItem]; let nextCursor: UUID?; let badge: String }
struct EventPush: Equatable {
    let notificationID: UUID, deliveryID: UUID, recipientID: UUID, campaignID: UUID
    let category: EventCategory; let destination: EventDestination
    init?(userInfo v: [AnyHashable: Any]) {
        guard let bytes=try? JSONSerialization.data(withJSONObject:v),bytes.count<=3500, v["notification_type"] as? String == "event",
              let version = v["soom_event_version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1,
              let n = (v["notification_id"] as? String).flatMap(UUID.init(uuidString:)),
              let d = (v["event_delivery_id"] as? String).flatMap(UUID.init(uuidString:)),
              let r = (v["recipient_id"] as? String).flatMap(UUID.init(uuidString:)),
              let c = (v["event_campaign_id"] as? String).flatMap(UUID.init(uuidString:)),
              let cat = (v["event_category"] as? String).flatMap(EventCategory.init(rawValue:)),
              let target = v["event_destination"] as? [String: Any], target.count == 1,
              let kind = (target["kind"] as? String).flatMap(EventDestination.init(rawValue:)),
              v["post_id"] == nil, let aps = v["aps"] as? [String: Any], let alert=aps["alert"] as? [String:String],
              let title=alert["title"], !title.isEmpty, title.count<=60,
              let body=alert["body"], !body.isEmpty, body.count<=300, aps["badge"] == nil,
              aps["content-available"] == nil else { return nil }
        notificationID=n; deliveryID=d; recipientID=r; campaignID=c; category=cat; destination=kind
    }
}
@MainActor protocol EventNotificationServing {
    func preferences() async throws -> EventPreferences
    func update(_ v: EventPreferences) async throws -> EventPreferences
    func registration(token: String) async throws -> EventRegistration
    func capability(_ r: EventRegistration) async throws
    func receipt(_ p: EventPush, registration: EventRegistration, kind: String) async throws
    func inbox(after: UUID?) async throws -> EventInboxPage
    func read(_ id: UUID) async throws -> String
    func unread() async throws -> Int
}
@MainActor struct SupabaseEventNotifications: EventNotificationServing {
    let client: SupabaseClient; let userID: UUID
    private func check() throws { guard !Task.isCancelled, client.auth.currentSession?.user.id == userID else { throw EventNotificationError.accountChanged } }
    private func call<P: Encodable, R: Decodable>(_ name: String, _ params: P) async throws -> R {
        try check(); let result: R = try await client.rpc(name, params: params).execute().value; try check(); return result
    }
    func preferences() async throws -> EventPreferences { try await call("soom_event_preferences_v1", [String: String]()) }
    func update(_ v: EventPreferences) async throws -> EventPreferences {
        struct P: Encodable { let p_expected_consent_revision: Int64; let p_expected_settings_revision: Int64; let p_event_consent: Bool; let p_marketing_consent: Bool; let p_event_push: Bool; let p_marketing_push: Bool; let p_proof_version: String }
        guard v.valid else { throw EventNotificationError.invalidContract }
        return try await call("soom_event_preferences_update_v1", P(p_expected_consent_revision:v.consentRevision,p_expected_settings_revision:v.settingsRevision,p_event_consent:v.eventConsent,p_marketing_consent:v.marketingConsent,p_event_push:v.eventPush,p_marketing_push:v.marketingPush,p_proof_version:v.proofVersion))
    }
    func registration(token: String) async throws -> EventRegistration { try await call("soom_event_current_registration_v1", ["p_token":token]) }
    func capability(_ r: EventRegistration) async throws {
        struct P: Encodable { let p_registry_id: UUID; let p_registration_id: UUID; let p_registration_epoch: Int64; let p_contract = "event-v1" }
        struct R: Decodable { let contract: String; let registrationEpoch: Int64; let expiresInSeconds: Int }
        let value: R = try await call("soom_event_capabilities_v1", P(p_registry_id:r.registryId,p_registration_id:r.registrationId,p_registration_epoch:r.registrationEpoch))
        guard value.contract == "event-v1", value.registrationEpoch == r.registrationEpoch, value.expiresInSeconds == 86400 else { throw EventNotificationError.invalidContract }
    }
    func receipt(_ p: EventPush, registration r: EventRegistration, kind: String) async throws {
        struct P: Encodable { let p_delivery_id: UUID; let p_registration_id: UUID; let p_registration_epoch: Int64; let p_kind: String }
        struct R: Decodable { let recorded: Bool; let kind: String; let displayedConfirmed: Bool }
        guard ["observed","tapped"].contains(kind) else { throw EventNotificationError.invalidContract }
        let result: R = try await call("soom_event_receipt_v1", P(p_delivery_id:p.deliveryID,p_registration_id:r.registrationId,p_registration_epoch:r.registrationEpoch,p_kind:kind))
        guard result.recorded, result.kind == kind, !result.displayedConfirmed else { throw EventNotificationError.invalidContract }
    }
    func inbox(after: UUID?) async throws -> EventInboxPage {
        struct P: Encodable { let p_limit = 50; let p_after: UUID? }
        return try await call("soom_event_inbox_page_v1", P(p_after:after))
    }
    func read(_ id: UUID) async throws -> String {
        struct R: Decodable { let id: UUID; let readAt: String }
        let r: R = try await call("soom_event_inbox_read_v1", ["p_id":id]); guard r.id == id else { throw EventNotificationError.invalidContract }; return r.readAt
    }
    func unread() async throws -> Int { try await call("soom_event_inbox_count_v1", [String:String]()) }
}
@MainActor final class EventNotificationCenter: ObservableObject {
    static let shared = EventNotificationCenter()
    let enabled: Bool
    @Published private(set) var preferences: EventPreferences?
    @Published var draft = EventPreferences()
    @Published private(set) var items: [EventInboxItem] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var error: String?
    @Published private(set) var busy = false
    @Published var homeRequest: UUID?
    @Published var showsInbox = false
    private(set) var owner: UUID?
    private var service: (any EventNotificationServing)?
    private var generation = UUID(), registrationRequest = UUID(), pageRequest = UUID()
    private(set) var currentRegistration: EventRegistration?
    private var capabilityExpires: Date?
    private var pendingTap: EventPush?
    private var receipts = Set<String>(), reading = Set<UUID>(), routedTaps = Set<UUID>()
    private var cursor: UUID?
    init(enabled: Bool = EventNotificationFeature.enabled) { self.enabled=enabled }
    func bind(user: UUID?, service: (any EventNotificationServing)?) {
        guard owner != user || self.service == nil else { return }
        let old = owner
        generation=UUID();registrationRequest=UUID();pageRequest=UUID();owner=user;self.service=service
        preferences=nil;draft=EventPreferences();items=[];unreadCount=0;self.error=nil;busy=false
        currentRegistration=nil;capabilityExpires=nil;receipts=[];reading=[];routedTaps=[];cursor=nil;homeRequest=nil;showsInbox=false
        if old != nil { pendingTap=nil }
    }
    private func valid(_ g: UUID) -> Bool { enabled && !Task.isCancelled && generation == g && owner != nil }
    func loadPreferences() async {
        guard enabled, owner != nil, let service, !busy else { self.error="이벤트 알림은 아직 사용할 수 없어요.";return }
        let g=generation;busy=true;defer { if generation == g { busy=false } }
        do { let p=try await service.preferences(); guard valid(g) else { return };guard p.valid else {throw EventNotificationError.invalidContract};preferences=p;draft=p;self.error=nil }
        catch { if valid(g) { self.error="이벤트 설정을 확인하지 못했어요. 로그인과 서비스 지원 상태를 확인해 주세요." } }
    }
    func savePreferences() async {
        guard enabled, !busy, preferences != nil, draft.valid, let service else { return }
        let g=generation;let selection=draft;busy=true;defer { if generation == g { busy=false } }
        do { let p=try await service.update(selection);guard valid(g) else { return };guard p.valid else {throw EventNotificationError.invalidContract};preferences=p;draft=p;self.error=nil }
        catch { if valid(g) { preferences=nil;draft=EventPreferences();self.error="저장하지 못했어요. 설정을 다시 불러온 뒤 선택을 확인해 주세요." } }
    }
    func registrationSucceeded(token: String, userID: UUID) async {
        guard enabled, owner == userID, let service else { return }
        let g=generation, request=UUID();registrationRequest=request;currentRegistration=nil;capabilityExpires=nil
        do {
            let r=try await service.registration(token:token)
            guard valid(g),owner==userID,request==registrationRequest,r.registrationEpoch>0 else { return }
            try await service.capability(r)
            guard valid(g),request==registrationRequest else { return }
            currentRegistration=r;capabilityExpires=Date().addingTimeInterval(86400)
            if let tap=pendingTap { pendingTap=nil;await handle(tap,tapped:true) }
        } catch { /* No fallback registration, token logging or automatic retry. */ }
    }
    func accepts(_ p: EventPush) -> Bool { enabled && owner == p.recipientID }
    func handle(_ p: EventPush, tapped: Bool) async {
        guard enabled else { return }
        if owner == nil { if tapped { pendingTap=p };return }
        guard accepts(p) else { return }
        if tapped, routedTaps.insert(p.deliveryID).inserted { if p.destination == .home { homeRequest=UUID() } else { showsInbox=true } }
        guard let r=currentRegistration, let expires=capabilityExpires,expires>Date(),let service else { if tapped {pendingTap=p};return }
        let g=generation,key="\(p.deliveryID):\(r.registrationId):\(r.registrationEpoch):\(tapped ? "tapped":"observed")"
        guard receipts.insert(key).inserted else { return }
        do { try await service.receipt(p,registration:r,kind:tapped ? "tapped":"observed");guard valid(g),r==currentRegistration else {return} }
        catch { /* Unknown response is not reissued automatically. */ }
    }
    func loadInbox(more: Bool = false) async {
        guard enabled, owner != nil, let service,!busy, !more || cursor != nil else { self.error="이벤트 알림은 아직 사용할 수 없어요.";return }
        let g=generation,request=UUID();pageRequest=request;busy=true;let after=more ? cursor:nil
        defer { if generation==g,pageRequest==request {busy=false} }
        do {
            let page=try await service.inbox(after:after)
            guard valid(g),pageRequest==request else{return};guard page.badge=="omitted",page.notifications.allSatisfy({$0.recipientId==owner}) else {throw EventNotificationError.invalidContract}
            var seen=Set<UUID>();items=((more ? items:[]) + page.notifications).filter{seen.insert($0.id).inserted};cursor=page.nextCursor;self.error=nil
            let count=try await service.unread();guard valid(g),pageRequest==request,count>=0 else{return};unreadCount=count
        } catch {if valid(g) {self.error="이벤트 알림을 불러오지 못했어요. 로그인 또는 서비스 지원 상태를 확인해 주세요."} }
    }
    func select(_ item: EventInboxItem) async {
        guard enabled,item.recipientId==owner,items.contains(where:{$0.id==item.id}),reading.insert(item.id).inserted,let service else{return}
        let g=generation;defer {if generation==g{reading.remove(item.id)}}
        do {
            let at=try await service.read(item.id);guard valid(g) else{return}
            if let i=items.firstIndex(where:{$0.id==item.id}){items[i].readAt=at}
            if item.destination.kind == .home {showsInbox=false;homeRequest=UUID()}
            let count=try await service.unread();guard valid(g),count>=0 else{return};unreadCount=count
        } catch {if valid(g){self.error="이 알림을 열 수 없어요. 삭제 또는 접근 상태를 다시 확인해 주세요."} }
    }
}
struct EventNotificationSettingsView: View {
    @ObservedObject var model: EventNotificationCenter = .shared
    var body: some View {
        Form {
            if let error=model.error {Text(error).accessibilityIdentifier("event.error")}
            Section("선택 동의") {
                Toggle("이벤트 알림 수신에 동의합니다. 선택 사항이며 언제든 설정에서 철회할 수 있습니다.",isOn:$model.draft.eventConsent).accessibilityIdentifier("event.consent")
                    .onChange(of:model.draft.eventConsent){_,v in if !v {model.draft.marketingConsent=false;model.draft.eventPush=false;model.draft.marketingPush=false} }
                Toggle("광고·홍보성 알림 수신에 별도로 동의합니다. 선택 사항이며 언제든 설정에서 철회할 수 있습니다.",isOn:$model.draft.marketingConsent).disabled(!model.draft.eventConsent).accessibilityIdentifier("event.marketing")
                    .onChange(of:model.draft.marketingConsent){_,v in if !v {model.draft.marketingPush=false} }
            }
            Section("푸시 설정") {
                Toggle("이벤트 푸시",isOn:$model.draft.eventPush).disabled(!model.draft.eventConsent)
                    .onChange(of:model.draft.eventPush){_,v in if !v {model.draft.marketingPush=false} }
                Toggle("광고·홍보 푸시",isOn:$model.draft.marketingPush).disabled(!model.draft.marketingConsent || !model.draft.eventPush)
                Text("기기의 알림 권한과 별개로 저장됩니다. 이벤트 알림은 앱 아이콘 배지에 합산하지 않습니다.")
            }
            Button("선택 저장"){Task{await model.savePreferences()}}.disabled(model.busy || model.preferences == nil || !model.draft.valid).accessibilityIdentifier("event.save")
            Button("설정 다시 불러오기"){Task{await model.loadPreferences()}}
        }.disabled(!model.enabled).navigationTitle("이벤트 알림 설정").task{await model.loadPreferences()}
    }
}
struct EventNotificationInboxView: View {
    @ObservedObject var model: EventNotificationCenter = .shared
    var body: some View {
        List {
            if let error=model.error {Text(error).accessibilityIdentifier("event.error")}
            if model.busy && model.items.isEmpty {ProgressView("이벤트 알림 불러오는 중")}
            if !model.busy && model.items.isEmpty && model.error == nil {Text("이벤트 알림이 없어요")}
            ForEach(model.items){item in Button {Task{await model.select(item)}} label:{VStack(alignment:.leading){Text(item.title).bold();Text(item.body);Text(item.readAt == nil ? "안읽음":"읽음").font(.caption)}}}
            Button("다음 이벤트 알림"){Task{await model.loadInbox(more:true)}}.disabled(model.busy)
        }.navigationTitle("이벤트 알림").task{await model.loadInbox()}.refreshable{await model.loadInbox()}
    }
}
