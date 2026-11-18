import SwiftUI
import SwiftData
import Supabase

/// Explicit real-server preview. Does not enable the production feature gates.
struct AccountActivityPreviewCapability: Decodable {
    let version: Int
    let viewer_id: UUID
    let enabled: Bool
    let owner_rules_accepted: Bool?
    let account_scope: AccountAudience?
    let scope_revision: Int64?
    let share_measurements: Bool?
}
@MainActor struct AccountActivityPreviewService {
    let client: SupabaseClient
    let owner: UUID
    func checkOwner() throws {
        guard client.auth.currentSession?.user.id == owner,
              !AccountDeletionWriteFence.shared.isRetired(owner) else { throw AccountActivitySyncError.accountChanged }
    }
    func capability() async throws -> AccountActivityPreviewCapability {
        try checkOwner()
        let value: AccountActivityPreviewCapability = try await client.rpc("soom_activity_preview_status_v1").execute().value
        try checkOwner()
        guard value.version == 1, value.viewer_id == owner else { throw AccountActivitySyncError.invalidReceipt }
        return value
    }
    func acceptAndSync(_ inputs: [AccountActivityStageInput]) async throws -> Int {
        let capability = try await capability()
        guard capability.enabled else { throw AccountActivitySyncError.disabled }
        guard let scope = capability.account_scope, let revision = capability.scope_revision,
              revision > 0, capability.share_measurements == true else { throw AccountActivitySyncError.unauthorized }
        struct Consent: Encodable { let p_expected_scope_revision: Int64; let p_notice_version: String }
        let receipt: AccountActivityOwnerAcceptance = try await client.rpc("soom_activity_accept_profile_rules_preview_v1", params: Consent(
            p_expected_scope_revision: revision, p_notice_version: "profile-activity-sharing-v1")).execute().value
        try checkOwner()
        guard receipt.version == 1, receipt.viewer_id == owner, receipt.scope_revision == revision,
              receipt.account_scope == scope.rawValue, !receipt.release_ready else { throw AccountActivitySyncError.invalidReceipt }
        return try await syncAuthorized(inputs)
    }
    func syncAuthorized(_ inputs: [AccountActivityStageInput]) async throws -> Int {
        let cap = try await capability()
        guard cap.enabled, cap.owner_rules_accepted == true else { throw AccountActivitySyncError.unauthorized }
        var synced = 0
        for input in inputs {
            try Task.checkCancellation(); try checkOwner()
            struct Lookup: Encodable { let p_canonical_id: UUID }
            struct Envelope: Decodable { let version: Int; let viewer_id: UUID; let row: AccountActivityStageLookup?; let release_ready: Bool }
            let old: Envelope = try await client.rpc("soom_activity_owner_lookup_preview_v1", params: Lookup(p_canonical_id: input.canonicalID)).execute().value
            try checkOwner()
            guard old.version == 1, old.viewer_id == owner, !old.release_ready,
                  old.row == nil || old.row?.owner_id == owner else { throw AccountActivitySyncError.invalidReceipt }
            if let row = old.row {
                let replay = input.payload(expectedRevision: row.revision - 1)
                if row.confirms(replay, owner: owner) { synced += 1; continue }
            }
            let payload = input.payload(expectedRevision: old.row?.revision ?? 0)
            try payload.validate(now: Date())
            let stage: AccountActivityStageReceipt = try await client.rpc("soom_activity_stage_preview_v1", params: payload).execute().value
            try checkOwner()
            guard stage.version == 1, stage.staged, stage.canonical_id == payload.p_canonical_id,
                  stage.revision == payload.p_expected_revision + 1, !stage.release_ready else { throw AccountActivitySyncError.invalidReceipt }
            synced += 1
        }
        return synced
    }
    /// Called only by the existing explicit workout deletion action. Never
    /// infer a deletion from a partial HealthKit import or missing local rows.
    func deleteProjectionIfEnrolled(canonicalID: UUID) async throws {
        let cap = try await capability()
        guard cap.enabled else { return }
        struct P: Encodable { let p_canonical_id: UUID }
        struct E: Decodable { let version: Int; let viewer_id: UUID; let row: AccountActivityStageLookup?; let release_ready: Bool }
        let lookup: E = try await client.rpc("soom_activity_owner_lookup_preview_v1", params: P(p_canonical_id: canonicalID)).execute().value
        try checkOwner()
        guard lookup.version == 1, lookup.viewer_id == owner, !lookup.release_ready else { throw AccountActivitySyncError.invalidReceipt }
        guard let row = lookup.row else { return }
        guard row.owner_id == owner, row.canonical_id == canonicalID else { throw AccountActivitySyncError.invalidReceipt }
        if row.deleted { return }
        let payload = AccountActivityStagePayload(p_canonical_id: row.canonical_id, p_source_ids: row.source_ids,
            p_expected_revision: row.revision, p_sport: row.sport, p_activity_at: row.activity_at,
            p_duration_seconds: row.duration_seconds, p_distance_meters: row.distance_meters, p_deleted: true)
        let receipt: AccountActivityStageReceipt = try await client.rpc("soom_activity_stage_preview_v1", params: payload).execute().value
        try checkOwner()
        guard receipt.version == 1, receipt.staged, receipt.canonical_id == row.canonical_id,
              receipt.revision == row.revision + 1, !receipt.release_ready else { throw AccountActivitySyncError.invalidReceipt }
    }
    func page() async throws -> AccountActivityFeedPage {
        try checkOwner()
        struct P: Encodable { let p_scope = "home"; let p_limit = 100 }
        let result: AccountActivityFeedPage = try await client.rpc("soom_activity_page_preview_v1", params: P()).execute().value
        try checkOwner()
        guard result.version == 1, result.viewerID == owner, !result.releaseReady else { throw AccountActivitySyncError.invalidReceipt }
        // This first live preview is deliberately owner-only. Do not trust a
        // future enrollment change to silently expand what this client renders.
        try result.validateCandidate(request: .init(viewerID: owner, scope: .home,
            ownerID: nil, before: nil, limit: 100), currentViewerID: owner,
            allowedHomeOwners: [], latestPermittedDate: Date())
        return result
    }
    func ranking() async throws -> AccountActivityRankingWire {
        try checkOwner()
        let result: AccountActivityRankingWire = try await client.rpc("soom_activity_ranking_totals_preview_v1", params:
            AccountActivityRankingRequest(p_period: "week", p_sport: "running", p_metric: "duration")).execute().value
        try checkOwner()
        guard result.version == 1, result.viewer_id == owner, !result.release_ready else { throw AccountActivitySyncError.invalidReceipt }
        return result
    }
    func inbox() async throws -> AccountActivityNativeInboxEnvelope {
        try checkOwner()
        struct P: Encodable { let p_limit = 50 }
        let data = try await client.rpc("soom_activity_native_inbox_preview_v1", params: P()).execute().data
        let result = try AccountActivityNativeInboxEnvelope.decode(data)
        try checkOwner()
        _ = try result.validated(viewer: owner, limit: 50, fixture: true, now: Date())
        return result
    }
}

struct AccountActivityPreviewScreen: View {
    let service: AccountActivityPreviewService
    @EnvironmentObject private var healthStorage: HealthAccountStorageController
    @Environment(\.modelContext) private var modelContext
    @State private var enabled = false
    @State private var busy = false
    @State private var consent = false
    @State private var status = "서버 연결 확인 중"
    @State private var cards: [AccountActivityFeedRow] = []
    @State private var rankingText = "아직 조회하지 않았어요."
    @State private var inboxRows: [AccountActivityNativeInboxRow] = []
    var body: some View {
        List {
            Section("본인 계정 · 실데이터 테스트") {
                Text("새 서버에 실제 연결합니다. 기존 피드와 다른 이용자의 기록은 바꾸지 않아요. 새 푸시 발송은 아직 연결하지 않았어요.")
                Text(status)
                if enabled {
                    Toggle("내 과거·새 운동 요약을 현재 프로필 규칙으로 적용합니다", isOn: $consent)
                    Text("종목·시작 시각·시간·거리만 보냅니다. 경로·심박·사진은 전송하지 않아요. 테스트가 허용된 계정에만 표시하며 공개 계정은 랭킹에 반영해요.").font(.footnote)
                    Button("내 운동 연결 · 새로고침") { Task { await sync() } }.disabled(!consent || busy)
                    Button("서버 결과 새로고침") { Task { await load() } }.disabled(busy)
                }
            }
            Section("새 피드") {
                if cards.isEmpty { Text("표시할 운동이 없어요.") }
                ForEach(cards, id: \.cardID) { row in
                    VStack(alignment: .leading) {
                        Text(row.sport)
                        Text("\(row.durationSeconds / 60)분").font(.subheadline)
                    }
                }
            }
            Section("이번 주 러닝 · 시간 랭킹") { Text(rankingText) }
            Section("새 알림함") {
                if inboxRows.isEmpty { Text("아직 받은 새 댓글 알림이 없어요. 알림을 만들기 위해 다른 사람 계정을 추가하지 않아요.") }
                ForEach(inboxRows) { row in Text(row.reason == "reply" ? "새 답글" : "새 댓글") }
            }
        }.navigationTitle("새 기능 연결 테스트")
            .task { await load() }
    }
    @MainActor private func load() async {
        busy = true; defer { busy = false }
        do {
            let cap = try await service.capability(); enabled = cap.enabled
            guard enabled else { status = "현재 로그인 계정은 아직 테스트 대상으로 확인되지 않았어요."; return }
            cards = try await service.page().rows
            let ranking = try await service.ranking()
            rankingText = "참여 \(ranking.total)명 · 내 순위 \(ranking.my_rank.map(String.init) ?? "없음")"
            inboxRows = try await service.inbox().rows
            status = "새 서버의 피드·랭킹·알림 조회를 확인했어요."
        } catch { status = "조회하지 못했어요. 기존 앱 기능은 유지됩니다." }
    }
    @MainActor private func sync() async {
        guard consent, !busy, enabled, healthStorage.userID == service.owner,
              modelContext.container === healthStorage.container, !HealthCloudJournal.isRetired(modelContext) else { return }
        busy = true
        do {
            let records = try modelContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>())
            let inputs = try AccountActivityStageInput.canonicalInputs(records.map { UnifiedWorkoutPersistenceMapper().makeWorkout(from: $0) })
            let count = try await service.acceptAndSync(inputs)
            status = "운동 \(count)개 연결 확인"; busy = false
            await load()
        } catch { busy = false; status = "연결 결과를 확인하지 못했어요. 다시 누르기 전에 서버 결과를 새로고침해 주세요." }
    }
}

private struct SOOMActivityPreviewKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var soomActivityPreview: Bool {
        get { self[SOOMActivityPreviewKey.self] }
        set { self[SOOMActivityPreviewKey.self] = newValue }
    }
}
