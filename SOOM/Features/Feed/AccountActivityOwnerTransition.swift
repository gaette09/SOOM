import SwiftUI
import Supabase

struct AccountActivityOwnerAcceptance: Decodable, Equatable {
    let version: Int
    let viewer_id: UUID
    let scope_revision: Int64
    let account_scope: String
    let accepted_projection_count: Int
    let release_ready: Bool
}
@MainActor protocol AccountActivityOwnerTransitionServing {
    var viewerID: UUID? { get }
    func accept(revision: Int64) async throws -> AccountActivityOwnerAcceptance
}
@MainActor struct SupabaseAccountActivityOwnerTransitionService: AccountActivityOwnerTransitionServing {
    let client: SupabaseClient
    var viewerID: UUID? { client.auth.currentSession?.user.id }
    func accept(revision: Int64) async throws -> AccountActivityOwnerAcceptance {
        guard AccountActivityFeedReleaseGate.productionReady else { throw AccountActivitySyncError.disabled }
        struct Params: Encodable { let p_expected_scope_revision: Int64; let p_notice_version: String }
        return try await client.rpc("soom_activity_accept_profile_rules_candidate_v1", params: Params(
            p_expected_scope_revision: revision, p_notice_version: "profile-activity-sharing-v1")).execute().value
    }
}
@MainActor final class AccountActivityOwnerTransitionModel: ObservableObject {
    @Published var acknowledged = false
    @Published private(set) var busy = false
    @Published private(set) var acceptedCount: Int?
    @Published private(set) var errorMessage: String?
    let owner: UUID
    let privacy: AccountPrivacyReceipt
    private let service: any AccountActivityOwnerTransitionServing
    private let currentContext: () -> AccountActivitySyncContext?
    private let fixture: Bool
    init(owner: UUID, privacy: AccountPrivacyReceipt, service: any AccountActivityOwnerTransitionServing,
         currentContext: @escaping () -> AccountActivitySyncContext?, fixture: Bool = false) {
        self.owner = owner; self.privacy = privacy; self.service = service
        self.currentContext = currentContext; self.fixture = fixture
    }
    var canAccept: Bool {
        acknowledged && !busy && privacy.isSelected && privacy.shareMeasurements == true
        && service.viewerID == owner && valid(currentContext())
        && (fixture || AccountActivityFeedReleaseGate.productionReady)
    }
    private func valid(_ c: AccountActivitySyncContext?) -> Bool {
        guard let c else { return false }
        return c.ownerID == owner && c.scopeID == owner.uuidString.lowercased() && !c.retired
    }
    func accept() async {
        guard canAccept, let before = currentContext() else { return }
        busy = true; errorMessage = nil; acceptedCount = nil
        defer { busy = false }
        do {
            let receipt = try await service.accept(revision: privacy.revision)
            guard !Task.isCancelled, currentContext() == before, service.viewerID == owner,
                  receipt.version == 1, receipt.viewer_id == owner,
                  receipt.scope_revision == privacy.revision, receipt.account_scope == privacy.accountScope?.rawValue,
                  receipt.accepted_projection_count >= 0, receipt.release_ready == !fixture else {
                throw AccountActivitySyncError.invalidReceipt
            }
            acceptedCount = receipt.accepted_projection_count
        } catch {
            errorMessage = "적용 결과를 확인하지 못했어요. 다시 적용하기 전에 현재 설정을 확인해 주세요."
        }
    }
}
struct AccountActivityOwnerTransitionView: View {
    @ObservedObject var model: AccountActivityOwnerTransitionModel
    var body: some View {
        Form {
            Section("내 운동에 프로필 공개범위 적용") {
                Text(model.privacy.accountScope == .privateAccount
                     ? "내 과거 운동과 앞으로 동기화할 운동을 승인한 팔로워가 볼 수 있어요."
                     : "내 과거 운동과 앞으로 동기화할 운동의 종목·시간·거리를 공개 프로필에서 볼 수 있으며 공개 랭킹에 반영해요.")
                Text("피드에는 나와 내가 팔로우한 사람의 운동만 표시해요. 다른 사람의 기록이나 공개범위는 바꾸지 않아요.")
                Text("이 적용은 운동 요약에만 해당해요. 경로·심박 차트의 기존 별도 공유 선택과 AI·회복·체크인 비공개는 유지돼요.")
                Text("공개 또는 비공개는 프로필에서 선택하며 카드별 공개 설정을 추가하지 않아요. 프로필 설정이 달라지면 다시 확인하기 전까지 새 공유를 제한해요.")
                Toggle("내용을 확인했으며 내 운동에 적용합니다", isOn: $model.acknowledged)
                    .accessibilityIdentifier("activity.ownerRules.acknowledge")
                Button("내 운동에 적용") { Task { await model.accept() } }
                    .disabled(!model.canAccept)
                    .accessibilityIdentifier("activity.ownerRules.accept")
                if model.busy { ProgressView() }
                if let count = model.acceptedCount { Text("운동 \(count)개의 적용을 확인했어요.") }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            }
        }.navigationTitle("운동 공유 전환")
    }
}

/// Mounted only once the reviewed server and client release gates are enabled.
struct AccountActivityOwnerTransitionDestination: View {
    @StateObject private var model: AccountActivityOwnerTransitionModel
    init(owner: UUID, privacy: AccountPrivacyReceipt, client: SupabaseClient) {
        _model = StateObject(wrappedValue: AccountActivityOwnerTransitionModel(
            owner: owner, privacy: privacy, service: SupabaseAccountActivityOwnerTransitionService(client: client),
            currentContext: {
                guard client.auth.currentSession?.user.id == owner else { return nil }
                return .init(ownerID: owner, scopeID: owner.uuidString.lowercased(),
                             generation: CommunitySafetyStore.shared.accountGeneration,
                             retired: AccountDeletionWriteFence.shared.isRetired(owner))
            }))
    }
    var body: some View { AccountActivityOwnerTransitionView(model: model) }
}
