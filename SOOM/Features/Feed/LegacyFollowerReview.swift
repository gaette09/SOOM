import Combine
import Foundation
import Supabase
import SwiftUI

/// This is a preserved incoming raw edge, never an approval or a health-data grant.
struct LegacyFollowerCandidate: Decodable, Equatable, Identifiable {
    let userID: UUID
    let edgeID: UUID
    let displayName: String
    let handle: String?
    let avatarPath: String?
    let followedAt: Date
    var id: UUID { edgeID }
    enum CodingKeys: String, CodingKey {
        case userID = "user_id", edgeID = "edge_id", displayName = "display_name", handle
        case avatarPath = "avatar_path", followedAt = "followed_at"
    }
}

enum LegacyFollowerReviewAction: String { case approve, dismiss }

@MainActor
protocol LegacyFollowerReviewServing {
    var viewerID: UUID? { get }
    func legacyReviewEnabled(owner: UUID) async throws -> Bool
    func legacyCandidates(owner: UUID, after: LegacyFollowerCandidate?) async throws -> [LegacyFollowerCandidate]
    func reviewLegacy(_ candidate: LegacyFollowerCandidate, owner: UUID, action: LegacyFollowerReviewAction) async throws
}

extension SupabaseAccountPrivacyService: LegacyFollowerReviewServing {
    func legacyReviewEnabled(owner: UUID) async throws -> Bool {
        try CommunitySafetyStore.shared.requireSocialAccess(viewerID: owner)
        guard viewerID == owner else { throw CommunitySafetyError.accountChanged }
        struct Params: Encodable { let p_owner: UUID }
        let value: Bool = try await client.rpc("soom_legacy_follow_review_enabled_v1", params: Params(p_owner: owner)).execute().value
        guard viewerID == owner else { throw CommunitySafetyError.accountChanged }
        try CommunitySafetyStore.shared.requireSocialAccess(viewerID: owner)
        return value
    }
    func legacyCandidates(owner: UUID, after: LegacyFollowerCandidate?) async throws -> [LegacyFollowerCandidate] {
        try CommunitySafetyStore.shared.requireSocialAccess(viewerID: owner)
        guard viewerID == owner else { throw CommunitySafetyError.accountChanged }
        struct Params: Encodable { let p_owner: UUID; let p_after_edge: UUID?; let p_limit: Int }
        let rows: [LegacyFollowerCandidate] = try await client.rpc("soom_legacy_follow_candidates_v1", params: Params(p_owner: owner,
            p_after_edge: after?.edgeID, p_limit: 50)).execute().value
        guard viewerID == owner else { throw CommunitySafetyError.accountChanged }
        try CommunitySafetyStore.shared.requireSocialAccess(viewerID: owner)
        return rows
    }
    func reviewLegacy(_ candidate: LegacyFollowerCandidate, owner: UUID, action: LegacyFollowerReviewAction) async throws {
        try CommunitySafetyStore.shared.requireSocialAccess(viewerID: owner)
        guard viewerID == owner else { throw CommunitySafetyError.accountChanged }
        struct Params: Encodable { let p_actor: UUID; let p_follower: UUID; let p_edge: UUID; let p_action: String }
        let approved: Bool = try await client.rpc("soom_review_legacy_follower_v1", params: Params(p_actor: owner,
            p_follower: candidate.userID, p_edge: candidate.edgeID, p_action: action.rawValue)).execute().value
        guard viewerID == owner, approved == (action == .approve) else { throw FeedPostManagementError.changeNotConfirmed }
        try CommunitySafetyStore.shared.requireSocialAccess(viewerID: owner)
    }
}

@MainActor
final class LegacyFollowerReviewModel: ObservableObject {
    @Published private(set) var candidates: [LegacyFollowerCandidate] = []
    @Published private(set) var loading = false
    @Published private(set) var enabled = false
    @Published private(set) var hasMore = false
    @Published private(set) var busyIDs = Set<UUID>()
    @Published private(set) var errorMessage: String?
    private let owner: UUID
    private let service: (any LegacyFollowerReviewServing)?
    private let safety: CommunitySafetyStore
    private let generation: Int
    private var loadToken = UUID()
    private var cursor: LegacyFollowerCandidate?
    private var subscription: AnyCancellable?
    init(owner: UUID, service: (any LegacyFollowerReviewServing)?, safety: CommunitySafetyStore = .shared) {
        self.owner = owner; self.service = service; self.safety = safety; generation = safety.accountGeneration
        subscription = safety.$revision.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            self.loadToken = UUID(); self.candidates = []; self.cursor = nil
            self.loading = false; self.hasMore = false; self.enabled = false
        }
    }
    private var current: Bool {
        safety.canUseSocial && safety.viewerID == owner && service?.viewerID == owner && safety.accountGeneration == generation
    }
    func load(reset: Bool = true) async {
        guard current, let service else { candidates = []; enabled = false; return }
        guard reset || (!loading && hasMore) else { return }
        let token = UUID(); loadToken = token; let revision = safety.revision
        if reset { candidates = []; cursor = nil; hasMore = false; enabled = false }
        loading = true; errorMessage = nil
        defer { if loadToken == token { loading = false } }
        do {
            let available = try await service.legacyReviewEnabled(owner: owner)
            guard current, loadToken == token, safety.revision == revision, !Task.isCancelled else { return }
            enabled = available
            guard available else { errorMessage = "기존 팔로워 확인 기능이 아직 준비되지 않았어요. 기존 관계와 기록은 그대로 보관합니다."; return }
            let rows = try await service.legacyCandidates(owner: owner, after: cursor)
            guard current, loadToken == token, safety.revision == revision, !Task.isCancelled else { return }
            var ids = Set(candidates.map(\.userID))
            candidates += rows.filter { $0.userID != owner && !safety.isBlocked($0.userID) && ids.insert($0.userID).inserted }
            cursor = rows.last ?? cursor; hasMore = rows.count == 50
        } catch {
            guard current, loadToken == token, safety.revision == revision else { return }
            candidates = []; enabled = false; hasMore = false
            errorMessage = "기존 팔로워 상태를 확인하지 못했어요. 다시 불러와 주세요."
        }
    }
    func review(_ candidate: LegacyFollowerCandidate, action: LegacyFollowerReviewAction) async {
        guard current, enabled, let service, candidates.contains(candidate), busyIDs.insert(candidate.id).inserted else { return }
        defer { busyIDs.remove(candidate.id) }
        let revision = safety.revision
        do {
            try await service.reviewLegacy(candidate, owner: owner, action: action)
            guard current, safety.revision == revision, !Task.isCancelled else { return }
            safety.invalidateRelationships()
            NotificationCenter.default.post(name: FeedFollowingStore.didChange, object: nil, userInfo: ["viewerID": owner])
            await load()
        } catch {
            guard current else { return }
            await load()
            errorMessage = "변경을 확인하지 못했어요. 관계가 바뀌었을 수 있으니 새 목록을 확인해 주세요."
        }
    }
}

struct LegacyFollowerReviewView: View {
    @StateObject private var model: LegacyFollowerReviewModel
    @State private var selected: LegacyFollowerCandidate?
    @ObservedObject private var safety = CommunitySafetyStore.shared
    init(service: (any LegacyFollowerReviewServing)? = nil) {
        let owner = CommunitySafetyStore.shared.viewerID ?? UUID()
        let source = service ?? SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient().map { SupabaseAccountPrivacyService(client:$0) }
        _model = StateObject(wrappedValue: LegacyFollowerReviewModel(owner: owner, service: source))
    }
    var body: some View {
        SocialAccessBoundary {
            List {
                Section {
                    Text("이전에 나를 팔로우한 사람을 한 명씩 확인해 주세요. 승인 전에는 승인된 팔로워로 계산하지 않아요.")
                    Text("승인하면 앞으로의 운동뿐 아니라 이미 열람이 허용된 과거 운동과 선택한 사진도 볼 수 있어요. 나만 보기 원본과 AI·회복·과거 비교는 공유하지 않아요.")
                }
                if let error = model.errorMessage { Text(error).foregroundStyle(SOOMColor.warning) }
                if model.loading && model.candidates.isEmpty { SOOMSkeleton(layout: .list, label: "기존 팔로워 확인 중") }
                ForEach(model.candidates) { person in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            SOOMAvatarView(userID: person.userID, avatarPath: person.avatarPath, size: 40)
                            VStack(alignment: .leading) { Text(person.displayName).font(.headline); if let handle = person.handle { Text(handle).font(.caption) } }
                        }
                        HStack {
                            Button("확인하고 승인") { selected = person }.accessibilityIdentifier("legacy.follow.select.\(person.userID)")
                            Button("이번에 승인 안 함") { Task { await model.review(person, action: .dismiss) } }.accessibilityIdentifier("legacy.follow.dismiss.\(person.userID)")
                        }.buttonStyle(.bordered).disabled(!model.busyIDs.isEmpty)
                    }.padding(.vertical, 8)
                }
                if model.enabled && model.candidates.isEmpty && !model.loading { Text("확인할 기존 팔로워가 없어요.").accessibilityIdentifier("legacy.follow.empty") }
                if model.hasMore { Button("더 보기") { Task { await model.load(reset: false) } }.disabled(model.loading) }
                Section("기존 기록 공개범위") {
                    Text("이미 공유한 전체공개·승인된 팔로워 기록은 승인 날짜보다 오래됐어도 볼 수 있어요. 기존 나만 보기 기록은 그대로 본인 전용이에요.")
                    Text("옛 팔로워 전용과 맞팔 전용 기록은 다른 계약이에요. 팔로워 승인만으로 공개범위를 바꾸지 않으며, 기록별 공유범위 확인이 필요해요.")
                    Text("이번에 승인 안 함은 후보 목록에서만 제외해요. 기존 관계와 기록을 삭제하지 않으며 새 요청은 별도로 확인할 수 있어요.")
                }
                Button("새로고침") { Task { await model.load() } }.disabled(model.loading || !model.busyIDs.isEmpty)
            }
            .navigationTitle("기존 팔로워 확인")
            .task { await model.load() }
            .onChange(of: safety.revision) { _, _ in selected = nil; if model.busyIDs.isEmpty { Task { await model.load() } } }
            .alert("이 팔로워를 승인할까요?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                if let person = selected {
                    Button("\(person.displayName) 승인") { selected = nil; Task { await model.review(person, action: .approve) } }
                        .accessibilityIdentifier("legacy.follow.confirm")
                }
                Button("취소", role: .cancel) { selected = nil }
            } message: { Text("열람을 허용한 기존 운동도 볼 수 있어요. 나만 보기 원본·AI·회복 분석은 그대로 본인 전용이에요.") }
        }
    }
}
