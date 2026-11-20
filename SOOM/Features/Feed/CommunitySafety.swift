import Combine
import Foundation
import Supabase

enum CommunityReportTargetKind: String, Codable {
    case post, comment, user, club
}

struct CommunityReportTarget: Identifiable, Equatable {
    let kind: CommunityReportTargetKind
    let id: UUID
}

enum CommunityReportReason: String, CaseIterable, Identifiable, Codable {
    case spam, harassment, hate, sexual, violence, privacy, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spam: return "스팸 또는 광고"
        case .harassment: return "괴롭힘 또는 따돌림"
        case .hate: return "혐오 또는 차별"
        case .sexual: return "성적인 콘텐츠"
        case .violence: return "폭력 또는 위협"
        case .privacy: return "개인정보 침해"
        case .other: return "기타"
        }
    }
}

struct CommunityBlockedUser: Decodable, Identifiable, Equatable {
    let blockedUserID: UUID
    let displayName: String
    let blockedAt: Date
    var id: UUID { blockedUserID }
    enum CodingKeys: String, CodingKey {
        case blockedUserID = "blocked_user_id"
        case displayName = "display_name"
        case blockedAt = "blocked_at"
    }
}

struct CommunityClubIdentity: Decodable, Equatable {
    let id: UUID
    let ownerID: UUID
    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_user_id"
    }
}

enum CommunitySafetyError: LocalizedError, Equatable {
    case unavailable, signInRequired, accountChanged, invalidTarget, invalidDetails, socialUnverified, updateRequired
    var errorDescription: String? {
        switch self {
        case .socialUnverified: return "공개범위를 확인할 때까지 소셜 기능을 잠갔어요. 내 기록은 계속 사용할 수 있어요."
        case .updateRequired: return "공유 기능을 사용하려면 SOOM을 업데이트해 주세요. 기존 운동 원본은 그대로 보관돼요."
        case .unavailable: return "온라인 기능을 사용할 수 없어요. 잠시 후 다시 시도해 주세요."
        case .signInRequired: return "로그인한 후 다시 시도해 주세요."
        case .accountChanged: return "계정이 변경되었어요. 현재 계정에서 다시 시도해 주세요."
        case .invalidTarget: return "이 대상에는 요청을 보낼 수 없어요."
        case .invalidDetails: return "신고 내용은 2,000자 이내로 작성해 주세요."
        }
    }

    static func isPolicyRejection(_ error: Error) -> Bool {
        if error as? CommunitySafetyError == .socialUnverified || error as? CommunitySafetyError == .updateRequired { return true }
        let message = String(describing: error)
        return ["New client required", "SOOM_CONTENT_REJECTED", "SOOM_TEXT_TOO_LONG", "SOOM_ACCOUNT_SUSPENDED"].contains(where: message.contains)
    }

    static func message(for error: Error) -> String {
        if let safetyError = error as? CommunitySafetyError {
            return safetyError.errorDescription ?? "요청을 완료하지 못했어요."
        }
        let description = String(describing: error)
        if description.contains("New client required") { return CommunitySafetyError.updateRequired.errorDescription! }
        if description.contains("SOOM_CONTENT_REJECTED") {
            return "커뮤니티 규칙에 어긋날 수 있는 표현이 있어요. 내용을 수정한 뒤 다시 시도해 주세요."
        }
        if description.contains("SOOM_TEXT_TOO_LONG") { return "내용이 너무 길어요. 글자 수를 줄여 주세요." }
        if description.contains("SOOM_ACCOUNT_SUSPENDED") { return "현재 계정의 커뮤니티 이용이 제한되어 있어요. 문의: support@example.invalid" }
        if description.contains("SOOM_TARGET_UNAVAILABLE") { return "더 이상 볼 수 없는 콘텐츠예요. 피드를 새로 불러와 주세요." }
        if description.contains("SOOM_REPORT_RATE_LIMITED") { return "신고 요청이 많아요. 잠시 후 다시 시도해 주세요." }
        return "요청을 완료하지 못했어요. 연결 상태를 확인하고 다시 시도해 주세요."
    }
}

@MainActor
protocol CommunitySafetyServicing {
    func authenticatedUserID() async throws -> UUID
    func report(target: CommunityReportTarget, reason: CommunityReportReason, details: String?) async throws -> UUID
    func block(userID: UUID) async throws
    func unblock(userID: UUID) async throws
    func listBlockedUsers() async throws -> [CommunityBlockedUser]
    func clubIdentity(id: UUID) async throws -> CommunityClubIdentity?
}

@MainActor
struct SupabaseCommunitySafetyClient: CommunitySafetyServicing {
    let client: SupabaseClient
    func authenticatedUserID() async throws -> UUID { try await client.auth.session.user.id }

    func report(target: CommunityReportTarget, reason: CommunityReportReason, details: String?) async throws -> UUID {
        struct Parameters: Encodable {
            let p_target_kind: String
            let p_target_id: UUID
            let p_reason: String
            let p_details: String?
        }
        return try await client.rpc("soom_report_content", params: Parameters(
            p_target_kind: target.kind.rawValue, p_target_id: target.id,
            p_reason: reason.rawValue, p_details: details
        )).execute().value
    }

    private struct BlockParameters: Encodable { let p_blocked_user_id: UUID }
    func block(userID: UUID) async throws {
        try await client.rpc("soom_block_user", params: BlockParameters(p_blocked_user_id: userID)).execute()
    }
    func unblock(userID: UUID) async throws {
        try await client.rpc("soom_unblock_user", params: BlockParameters(p_blocked_user_id: userID)).execute()
    }
    func listBlockedUsers() async throws -> [CommunityBlockedUser] {
        try await client.rpc("soom_list_blocked_users").execute().value
    }
    func clubIdentity(id: UUID) async throws -> CommunityClubIdentity? {
        let rows: [CommunityClubIdentity] = try await client.from("clubs")
            .select("id,owner_user_id")
            .eq("id", value: id)
            .limit(1)
            .execute().value
        return rows.first
    }

}

/// Account-scoped cache of server-confirmed safety changes. Revision changes
/// invalidate feed, saved, search, and detail snapshots, including in-flight loads.
@MainActor
final class CommunitySafetyStore: ObservableObject {
    static let shared = CommunitySafetyStore(client: nil, requiresSocialVerification: true)

    // Only synchronous verification transitions may preserve display-only bytes.
    // All unrelated revision writers default to destructive cache invalidation.
    private(set) var preservesPendingDisplayCache = false
    func withPendingDisplayCachePreserved(owner: UUID, _ action: () -> Void) {
        guard viewerID == owner else { action(); return }
        let previous = preservesPendingDisplayCache
        preservesPendingDisplayCache = true
        defer { preservesPendingDisplayCache = previous }
        action()
    }
    @Published private(set) var revision = 0
    @Published private(set) var blockedUsers: [CommunityBlockedUser] = []
    private(set) var viewerID: UUID?
    private(set) var accountGeneration = 0
    let requiresSocialVerification: Bool
    @Published private(set) var socialVerified = false
    var canUseSocial: Bool { !requiresSocialVerification || (socialVerified && viewerID != nil) }
    @Published private(set) var previewVerified = false
    private var previewOwner: UUID?
    private var previewGeneration: Int?
    private var previewRevision: Int?
    var canUseActivityPreview: Bool {
        guard previewVerified, let viewerID, previewOwner == viewerID,
              previewGeneration == accountGeneration, previewRevision == revision,
              !AccountDeletionWriteFence.shared.isRetired(viewerID) else { return false }
        return true
    }
    /// Only a freshly checked capability may grant native preview access.
    /// It never changes legacy socialVerified or authorizes a legacy operation.
    @discardableResult
    func setActivityPreviewVerified(_ verified: Bool, owner: UUID, generation: Int, expectedRevision: Int) -> Bool {
        guard viewerID == owner, accountGeneration == generation, revision == expectedRevision,
              !AccountDeletionWriteFence.shared.isRetired(owner) else { return false }
        if verified && canUseActivityPreview { return true }
        if !verified && !previewVerified { return true }
        revision += 1
        previewOwner = verified ? owner : nil
        previewGeneration = verified ? generation : nil
        previewRevision = verified ? revision : nil
        previewVerified = verified
        return true
    }
    private func resetActivityPreviewVerification() {
        previewVerified = false; previewOwner = nil; previewGeneration = nil; previewRevision = nil
    }

    func requireSocialAccess(viewerID expected: UUID) throws {
        guard viewerID == expected else { throw CommunitySafetyError.accountChanged }
        guard canUseSocial else { throw CommunitySafetyError.socialUnverified }
    }
    func setSocialVerified(_ verified: Bool, owner: UUID) {
        guard viewerID == owner else { return }
        guard socialVerified != verified else { return }
        resetActivityPreviewVerification()
        socialVerified = verified
        revision += 1
    }
    private func resetSocialVerification() { socialVerified = false; resetActivityPreviewVerification() }

    private var blockedIDs: Set<UUID> = []
    private var client: (any CommunitySafetyServicing)?
    private var beforeDemo: (client: (any CommunitySafetyServicing)?, viewerID: UUID?, blockedIDs: Set<UUID>, blockedUsers: [CommunityBlockedUser])?

    init(client: (any CommunitySafetyServicing)?, viewerID: UUID? = nil, requiresSocialVerification: Bool = false) {
        self.client = client
        self.viewerID = viewerID
        self.requiresSocialVerification = requiresSocialVerification
    }

    /// SOOMApp supplies the exact authenticated client owned by its auth provider.
    /// Constructing another client would create a separate in-memory auth session.
    func configure(client: SupabaseClient?) {
        resetSocialVerification()
        self.client = client.map { SupabaseCommunitySafetyClient(client: $0) }
        accountGeneration += 1
        blockedIDs = []
        blockedUsers = []
        revision += 1
    }

    func configureForDemo() {
        if beforeDemo == nil { beforeDemo = (client, viewerID, blockedIDs, blockedUsers) }
        resetActivityPreviewVerification()
        client = ReviewDemoCommunityStore.shared
        viewerID = ReviewDemoMode.userID
        socialVerified = true
        accountGeneration += 1
        blockedIDs = []
        blockedUsers = []
        revision += 1
    }

    func restoreAfterDemo() {
        guard let previous = beforeDemo else { return }
        beforeDemo = nil
        resetSocialVerification()
        client = previous.client
        viewerID = previous.viewerID
        blockedIDs = previous.blockedIDs
        blockedUsers = previous.blockedUsers
        accountGeneration += 1
        revision += 1
    }

    func setViewerID(_ id: UUID?) {
        guard viewerID != id else { return }
        resetSocialVerification()
        viewerID = id
        accountGeneration += 1
        blockedIDs = []
        blockedUsers = []
        revision += 1
    }

    /// Changing a follow edge invalidates RLS receipts and photo pixels immediately.
    func invalidateRelationships() { revision += 1 }

    func isBlocked(_ authorID: UUID) -> Bool { blockedIDs.contains(authorID) }

    func filtered(_ items: [FeedItem]) -> [FeedItem] {
        let permitted = canUseSocial ? items : items.filter { $0.isLocalDraft || (canUseActivityPreview && ($0.activityProjection != nil || ($0.previewLegacyReadContext != nil && $0.previewLegacyReadContext == viewerID.map { AccountActivityReadContext(viewerID: $0, generation: accountGeneration, safetyRevision: revision) }))) }
        return permitted.compactMap { item in
            guard item.isLocalDraft || !isBlocked(item.authorId) else { return nil }
            var result = item
            result.comments.removeAll { isBlocked($0.authorId) }
            return result
        }
    }

    /// Local/seed IDs never become remote moderation targets. Both IDs are
    /// taken from a fresh RLS-protected server row, not a fallback view model.
    func verifiedClubIdentity(clubID: String) async throws -> CommunityClubIdentity? {
        let resolvedID = ReviewDemoMode.isActive ? ReviewDemoCommunityStore.shared.clubID(for: clubID) : UUID(uuidString: clubID)
        guard let id = resolvedID else { return nil }
        let generation = accountGeneration
        let service = try await authenticatedClient(generation: generation)
        let identity = try await service.clubIdentity(id: id)
        try requireCurrentAccount(generation)
        guard identity?.id == id else { return nil }
        return identity
    }

    func refreshBlockedUsers() async throws {
        let startingRevision = revision
        let generation = accountGeneration
        let service = try await authenticatedClient(generation: generation)
        let users = try await service.listBlockedUsers()
        try requireCurrentAccount(generation)
        guard revision == startingRevision else { return }
        let ids = Set(users.map(\.blockedUserID))
        blockedUsers = users
        if ids != blockedIDs {
            blockedIDs = ids
            revision += 1
        }
    }

    func report(target: CommunityReportTarget, reason: CommunityReportReason, details: String) async throws -> UUID {
        let text = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 2_000 else { throw CommunitySafetyError.invalidDetails }
        if target.kind == .user, target.id == viewerID { throw CommunitySafetyError.invalidTarget }
        let generation = accountGeneration
        let service = try await authenticatedClient(generation: generation)
        let id = try await service.report(target: target, reason: reason, details: text.isEmpty ? nil : text)
        try requireCurrentAccount(generation)
        return id
    }

    func block(userID: UUID, displayName: String) async throws {
        guard userID != viewerID else { throw CommunitySafetyError.invalidTarget }
        let generation = accountGeneration
        let service = try await authenticatedClient(generation: generation)
        try await service.block(userID: userID)
        try requireCurrentAccount(generation)
        blockedIDs.insert(userID)
        if !blockedUsers.contains(where: { $0.id == userID }) {
            blockedUsers.append(CommunityBlockedUser(blockedUserID: userID, displayName: displayName, blockedAt: Date()))
        }
        revision += 1
    }

    func unblock(userID: UUID) async throws {
        let generation = accountGeneration
        let service = try await authenticatedClient(generation: generation)
        try await service.unblock(userID: userID)
        try requireCurrentAccount(generation)
        blockedIDs.remove(userID)
        blockedUsers.removeAll { $0.id == userID }
        revision += 1
    }

    private func authenticatedClient(generation: Int) async throws -> any CommunitySafetyServicing {
        guard let viewerID else { throw CommunitySafetyError.signInRequired }
        guard let client else { throw CommunitySafetyError.unavailable }
        let authenticatedID: UUID
        do { authenticatedID = try await client.authenticatedUserID() }
        catch { throw CommunitySafetyError.signInRequired }
        try requireCurrentAccount(generation)
        guard authenticatedID == viewerID else { throw CommunitySafetyError.accountChanged }
        return client
    }

    private func requireCurrentAccount(_ generation: Int) throws {
        guard generation == accountGeneration else { throw CommunitySafetyError.accountChanged }
    }
}

@MainActor
final class CommunityReportViewModel: ObservableObject {
    @Published var reason: CommunityReportReason? = nil
    @Published var details = ""
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var receiptID: UUID?
    let target: CommunityReportTarget
    private let store: CommunitySafetyStore
    private let openingAccountGeneration: Int
    var canSubmit: Bool { reason != nil && details.count <= 2_000 && !isSubmitting && receiptID == nil }

    init(target: CommunityReportTarget, store: CommunitySafetyStore) {
        self.target = target
        self.store = store
        self.openingAccountGeneration = store.accountGeneration
    }
    func submit() async {
        guard canSubmit, let reason else { return }
        guard openingAccountGeneration == store.accountGeneration else {
            errorMessage = CommunitySafetyError.message(for: CommunitySafetyError.accountChanged)
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do { receiptID = try await store.report(target: target, reason: reason, details: details) }
        catch { errorMessage = CommunitySafetyError.message(for: error) }
    }
}

@MainActor
final class FeedCommentComposeViewModel: ObservableObject {
    @Published var text = ""
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSubmit: Bool { !trimmedText.isEmpty && trimmedText.count <= 500 && !isSubmitting }

    func submit(using onSubmit: (String) async throws -> Void) async -> Bool {
        guard canSubmit else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await onSubmit(trimmedText)
            return true
        } catch {
            errorMessage = CommunitySafetyError.message(for: error)
            return false
        }
    }
}
