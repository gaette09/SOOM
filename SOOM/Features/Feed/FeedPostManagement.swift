import Combine
import Foundation
import OSLog
import Supabase

@MainActor
protocol FeedPostRemoteManaging {
    var sessionUserID: UUID? { get }
    func fetchPost(id: UUID, viewerID: UUID) async throws -> FeedItem?
    func fetchAccess(id: UUID, viewerID: UUID) async throws -> FeedPostAccess?
    func setBookmark(postID: UUID, viewerID: UUID, isSaved: Bool) async throws
    func editPost(id: UUID, ownerID: UUID, title: String, description: String) async throws
    func setVisibility(postID: UUID, ownerID: UUID, visibility: FeedPostVisibility) async throws
    func deletePost(id: UUID, ownerID: UUID) async throws
}

/// A fresh authenticated RLS read, never a cached permission receipt.
struct FeedPostAccess {
    let id: UUID
    let authorID: UUID
    let visibility: FeedPostVisibility
    var post: FeedPostDTO? = nil
    var sharedDetailContractEnabled = false
    var sharedDetailAuthorized = false
}

extension FeedPostRemoteManaging {
    func fetchAccess(id: UUID, viewerID: UUID) async throws -> FeedPostAccess? {
        guard let item = try await fetchPost(id: id, viewerID: viewerID), !item.isLocalDraft else { return nil }
        return FeedPostAccess(id: item.id, authorID: item.authorId, visibility: item.visibility.feedPostVisibility,
                              post: item.serverPostSnapshot, sharedDetailContractEnabled: item.sharedDetailContractEnabled, sharedDetailAuthorized: item.permittedSharedDetail != nil)
    }
}

struct FeedPostAccessScope: Hashable {
    let clientIdentity: ObjectIdentifier
    let viewerID: UUID
    let accountGeneration: Int
    let safetyRevision: Int
}

/// Share only pending/live reads. Completed permission results are never cached.
/// Different accounts, safety epochs and authenticated clients cannot join.
@MainActor
final class FeedPostAccessBatcher {
    static let shared = FeedPostAccessBatcher()
    struct Statistics {
        var requests = 0
        var joinedRequests = 0
        var batches = 0
        var requestedRows = 0
        var failedBatches = 0
    }
    private struct Key: Hashable { let scope: FeedPostAccessScope; let postID: UUID }
    private struct Flight { let id: UUID; let task: Task<FeedPostAccess?, Error> }
    private final class Group {
        var waiters: [UUID: CheckedContinuation<FeedPostAccess?, Error>] = [:]
        var runner: Task<Void, Never>?
        let load: @MainActor ([UUID]) async throws -> [FeedPostAccess]
        init(load: @escaping @MainActor ([UUID]) async throws -> [FeedPostAccess]) { self.load = load }
    }
    private var flights: [Key: Flight] = [:]
    private var groups: [FeedPostAccessScope: Group] = [:]
    private let collectionNanoseconds: UInt64
    private let maximumBatchSize: Int
    private let logger = Logger(subsystem: "app.soom.prototype", category: "FeedCardAccess")
    private(set) var statistics = Statistics()
    var inFlightCount: Int { flights.count }

    init(collectionNanoseconds: UInt64 = 8_000_000, maximumBatchSize: Int = 32) {
        self.collectionNanoseconds = collectionNanoseconds
        self.maximumBatchSize = max(1, min(maximumBatchSize, 32))
    }

    func receipt(for postID: UUID, scope: FeedPostAccessScope,
                 load: @escaping @MainActor ([UUID]) async throws -> [FeedPostAccess]) async throws -> FeedPostAccess? {
        statistics.requests += 1
        let key = Key(scope: scope, postID: postID)
        if let flight = flights[key] {
            statistics.joinedRequests += 1
            return try await flight.task.value
        }
        let id = UUID()
        let task = Task { @MainActor [self] in
            defer { if flights[key]?.id == id { flights.removeValue(forKey: key) } }
            return try await withCheckedThrowingContinuation { continuation in
                let group = groups[scope] ?? Group(load: load)
                groups[scope] = group
                group.waiters[postID] = continuation
                schedule(group, scope: scope)
            }
        }
        flights[key] = Flight(id: id, task: task)
        return try await task.value
    }

    private func schedule(_ group: Group, scope: FeedPostAccessScope) {
        guard group.runner == nil else { return }
        group.runner = Task { @MainActor [self] in
            // One short collection window, not a permission reuse interval.
            try? await Task.sleep(nanoseconds: collectionNanoseconds)
            await flush(group, scope: scope)
        }
    }

    private func flush(_ group: Group, scope: FeedPostAccessScope) async {
        let ids = Array(group.waiters.keys.sorted { $0.uuidString < $1.uuidString }.prefix(maximumBatchSize))
        let waiters = ids.compactMap { id -> (UUID, CheckedContinuation<FeedPostAccess?, Error>)? in
            guard let waiter = group.waiters.removeValue(forKey: id) else { return nil }
            return (id, waiter)
        }
        defer {
            group.runner = nil
            if group.waiters.isEmpty { groups.removeValue(forKey: scope) }
            else { schedule(group, scope: scope) }
        }
        statistics.batches += 1
        statistics.requestedRows += ids.count
        let started = ProcessInfo.processInfo.systemUptime
        do {
            let receipts = try await group.load(ids)
            var byID: [UUID: FeedPostAccess] = [:]
            for receipt in receipts where ids.contains(receipt.id) {
                guard byID[receipt.id] == nil else { throw FeedPostManagementError.changeNotConfirmed }
                byID[receipt.id] = receipt
            }
            for (id, waiter) in waiters { waiter.resume(returning: byID[id]) }
        } catch {
            statistics.failedBatches += 1
            for (_, waiter) in waiters { waiter.resume(throwing: error) }
        }
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        let joined = statistics.joinedRequests
        logger.debug("Access batch rows=\(ids.count, privacy: .public) elapsed_ms=\(elapsedMS, privacy: .public) joined_total=\(joined, privacy: .public)")
    }
}

enum FeedPostManagementError: LocalizedError {
    case contentUnavailable, changeNotConfirmed
    var errorDescription: String? {
        switch self {
        case .contentUnavailable:
            return "이 게시물을 더 이상 볼 수 없어요. 삭제되었거나 공개 범위가 변경되었을 수 있어요."
        case .changeNotConfirmed:
            return "서버의 변경 결과를 확인하지 못했어요. 다시 불러온 뒤 확인해 주세요."
        }
    }
}

/// Uses the same authenticated PostgREST/RLS path as the feed. The explicit
/// captured user_id filter also prevents a later SDK account from mutating its
/// own row through a view that was opened by a previous account.
@MainActor
struct SupabaseFeedPostManagementRemote: FeedPostRemoteManaging {
    let client: SupabaseClient
    var loadAllComments = false
    var loadAllReactions = false
    var sessionUserID: UUID? { client.auth.currentSession?.user.id }

    private func validate(_ viewerID: UUID) throws {
        try CommunitySafetyStore.shared.requireSocialAccess(viewerID: viewerID)
        guard sessionUserID == viewerID else { throw CommunitySafetyError.accountChanged }
    }
    private func authorize(_ viewerID: UUID) async throws {
        try validate(viewerID)
        let session = try await client.auth.session
        try validate(viewerID)
        guard session.user.id == viewerID else { throw CommunitySafetyError.accountChanged }
    }

    func fetchPost(id: UUID, viewerID: UUID) async throws -> FeedItem? {
        try await authorize(viewerID)
        try validate(viewerID)
        let remote = SupabaseFeedRemoteClient(client: client)
        let bundle = try await remote.fetchFeedPost(id: id, loadAllComments: loadAllComments, loadAllReactions: loadAllReactions)
        try validate(viewerID)
        guard let bundle else { return nil }
        let profileIDs = bundle.previewProfileIDs + (loadAllComments ? bundle.comments.map(\.userId) : [])
        let profiles = try await remote.fetchProfiles(ids: Array(Set(profileIDs)))
        try validate(viewerID)
        let profile = profiles.first { $0.id == bundle.post.userId }
        return bundle.makeFeedItem(authorName: profile?.displayName ?? "SOOM 사용자",
                                   authorHandle: profile?.handle, avatarPath: profile?.avatarPath, currentUserId: viewerID,
                                   profilesByID: Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) }))
    }

    func fetchAccess(id: UUID, viewerID: UUID) async throws -> FeedPostAccess? {
        let safety = CommunitySafetyStore.shared
        let scope = FeedPostAccessScope(clientIdentity: ObjectIdentifier(client), viewerID: viewerID,
            accountGeneration: safety.accountGeneration, safetyRevision: safety.revision)
        func validateAccessScope() throws {
            try validate(viewerID)
            guard safety.viewerID == viewerID, safety.accountGeneration == scope.accountGeneration,
                  safety.revision == scope.safetyRevision else { throw CommunitySafetyError.accountChanged }
        }
        try validateAccessScope()
        return try await FeedPostAccessBatcher.shared.receipt(for: id, scope: scope) { ids in
            try validateAccessScope()
            try await authorize(viewerID)
            try validateAccessScope()
            let rows: [FeedPostDTO] = try await client.from("feed_posts")
                .select().in("id", values: ids).limit(ids.count).execute().value
            try validateAccessScope()
            let sharedEnabled = try await SupabaseWorkoutSharedDetailService(client: client).enabled()
            let sharedAuthorized = try await SupabaseWorkoutSharedDetailService(client: client).authorizedPosts(rows)
            try validateAccessScope()
            return rows.map { FeedPostAccess(id: $0.id, authorID: $0.userId, visibility: $0.visibility, post: $0, sharedDetailContractEnabled: sharedEnabled, sharedDetailAuthorized: sharedAuthorized.contains($0.id)) }
        }
    }

    func setBookmark(postID: UUID, viewerID: UUID, isSaved: Bool) async throws {
        try await authorize(viewerID)
        try validate(viewerID)
        if isSaved {
            // Insert-or-ignore is safe after a timeout and requires no bookmark UPDATE policy.
            try await client.from("feed_bookmarks")
                .upsert(Bookmark(postId: postID, userId: viewerID), onConflict: "post_id,user_id", ignoreDuplicates: true)
                .execute()
        } else {
            try await client.from("feed_bookmarks").delete()
                .eq("post_id", value: postID).eq("user_id", value: viewerID).execute()
        }
        try validate(viewerID)
    }

    func editPost(id: UUID, ownerID: UUID, title: String, description: String) async throws {
        try await authorize(ownerID)
        try validate(ownerID)
        let rows: [Receipt] = try await client.from("feed_posts")
            .update(Edit(title: title, body: description))
            .eq("id", value: id).eq("user_id", value: ownerID).select("id").execute().value
        try validate(ownerID)
        guard rows.contains(where: { $0.id == id }) else { throw FeedPostManagementError.contentUnavailable }
    }

    func setVisibility(postID: UUID, ownerID: UUID, visibility: FeedPostVisibility) async throws {
        try await authorize(ownerID)
        try validate(ownerID)
        let rows: [Receipt] = try await client.from("feed_posts")
            .update(FeedPostVisibilityUpdateDTO(visibility: visibility))
            .eq("id", value: postID).eq("user_id", value: ownerID).select("id").execute().value
        try validate(ownerID)
        guard rows.contains(where: { $0.id == postID }) else { throw FeedPostManagementError.contentUnavailable }
    }

    func deletePost(id: UUID, ownerID: UUID) async throws {
        try await authorize(ownerID)
        try validate(ownerID)
        let rows: [Receipt] = try await client.from("feed_posts").delete()
            .eq("id", value: id).eq("user_id", value: ownerID).select("id").execute().value
        try validate(ownerID)
        guard rows.contains(where: { $0.id == id }) else { throw FeedPostManagementError.contentUnavailable }
    }

    private struct Receipt: Decodable { let id: UUID }
    private struct Edit: Encodable { let title: String; let body: String }
    private struct Bookmark: Encodable {
        let postId: UUID
        let userId: UUID
        enum CodingKeys: String, CodingKey { case postId = "post_id", userId = "user_id" }
    }
}

@MainActor
final class FeedPostManagement: ObservableObject {
    @Published private(set) var item: FeedItem
    @Published private(set) var isWorking = false
    @Published private(set) var isDeleted = false
    @Published private(set) var isAvailable = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var isCheckingAccess = false
    @Published private(set) var showsAccessProgress = false
    @Published var errorMessage: String?
    @Published var notice: String?
    static let didChange = Notification.Name("SOOM.FeedPostManagement.didChange")

    private let remote: (any FeedPostRemoteManaging)?
    private let safetyStore: CommunitySafetyStore
    private let viewerID: UUID?
    private let accountGeneration: Int
    private var safetySubscription: AnyCancellable?
    private var verificationGeneration = 0
    private var lastAppearanceRevision: Int?
    private var hasVerifiedArticle = false
    struct AppearanceStatistics {
        var joinedRequests = 0
        var accessReads = 0
        var listSnapshotsReused = 0
        var fullArticleReads = 0
    }
    private(set) var appearanceStatistics = AppearanceStatistics()
    private struct AppearanceFlight {
        let id: UUID
        let revision: Int
        let task: Task<Void, Never>
    }
    private var appearanceFlight: AppearanceFlight?

    convenience init(item: FeedItem, loadAllComments: Bool = false, loadAllReactions: Bool = false) {
        if ReviewDemoMode.isActive {
            self.init(item: item, remote: ReviewDemoCommunityStore.shared, safetyStore: .shared)
            return
        }
        let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient()
        self.init(item: item, remote: client.map { SupabaseFeedPostManagementRemote(client: $0, loadAllComments: loadAllComments, loadAllReactions: loadAllReactions) },
                  safetyStore: .shared)
    }

    init(item: FeedItem, remote: (any FeedPostRemoteManaging)?, safetyStore: CommunitySafetyStore) {
        self.item = item
        self.remote = remote
        self.safetyStore = safetyStore
        viewerID = safetyStore.viewerID
        accountGeneration = safetyStore.accountGeneration
        safetySubscription = safetyStore.$revision.dropFirst().sink { [weak self] _ in
            self?.invalidateForSafetyChange()
        }
    }

    var title: String {
        if case .workoutSession(let card) = item.cardData { return card.title }
        return item.activityContext
    }
    var description: String { item.caption ?? "" }
    var visibility: FeedPostVisibility { item.visibility.feedPostVisibility }
    var isBookmarked: Bool { item.viewerHasSaved }
    var canManage: Bool {
        isAvailable && !isCheckingAccess && !isDeleted && !item.isLocalDraft && viewerID == item.authorId && scopeIsCurrent
    }
    var canBookmark: Bool { isAvailable && !isCheckingAccess && !isDeleted && !item.isLocalDraft && scopeIsCurrent }
    var canDisplayContent: Bool { isAvailable && !isWorking && !isCheckingAccess && !isDeleted && scopeIsCurrent }
    /// Layout retention is separate from permission. The view must keep this
    /// subtree invisible, untappable and hidden from VoiceOver until authorized.
    var canRetainArticle: Bool { scopeIsCurrent && !isDeleted && (hasVerifiedArticle || item.serverPostSnapshot != nil) }

    private var scopeIsCurrent: Bool {
        guard let viewerID else { return false }
        return safetyStore.canUseSocial && safetyStore.viewerID == viewerID && safetyStore.accountGeneration == accountGeneration
            && remote?.sessionUserID == viewerID && !safetyStore.isBlocked(item.authorId)
    }

    private func validateScope() throws -> UUID {
        guard safetyStore.canUseSocial else { throw CommunitySafetyError.socialUnverified }
        guard !item.isLocalDraft else { throw CommunitySafetyError.invalidTarget }
        guard let viewerID else { throw CommunitySafetyError.signInRequired }
        guard remote != nil else { throw CommunitySafetyError.unavailable }
        guard safetyStore.viewerID == viewerID, safetyStore.accountGeneration == accountGeneration,
              remote?.sessionUserID == viewerID else { throw CommunitySafetyError.accountChanged }
        guard !safetyStore.isBlocked(item.authorId) else { throw FeedPostManagementError.contentUnavailable }
        return viewerID
    }

    private func loadVerifiedItem() async throws -> FeedItem {
        let generation = verificationGeneration
        let viewerID = try validateScope()
        guard let remote else { throw CommunitySafetyError.unavailable }
        appearanceStatistics.fullArticleReads += 1
        let fetched = try await remote.fetchPost(id: item.id, viewerID: viewerID)
        guard generation == verificationGeneration, !Task.isCancelled else { throw CancellationError() }
        _ = try validateScope()
        guard let fetched, fetched.id == item.id, fetched.authorId == item.authorId, !fetched.isLocalDraft,
              fetched.authorId == viewerID || fetched.visibility == .publicFeed || fetched.visibility == .mutual || (fetched.visibility == .followers && fetched.serverPostSnapshot?.audienceContract == 1),
              let filtered = safetyStore.filtered([fetched]).first else {
            throw FeedPostManagementError.contentUnavailable
        }
        return filtered
    }

    func refresh() async {
        guard !isWorking, !isDeleted else { return }
        isWorking = true; isAvailable = false; errorMessage = nil
        defer { isWorking = false; hasLoaded = true }
        do {
            let refreshed = try await loadVerifiedItem()
            _ = try validateScope()
            item = refreshed
            hasVerifiedArticle = true
            isAvailable = true
        } catch {
            fail(error)
        }
    }

    /// SwiftUI may restart a row task merely because it scrolled offscreen.
    /// Reuse only this still-mounted presentation's verified state. Explicit
    /// refresh, foreground/tab return, safety/account changes and mutations
    /// invalidate it; independent callers still use fresh refreshForAppearance.
    func refreshForVisiblePresentation(revalidationRevision: Int) async {
        if lastAppearanceRevision == revalidationRevision, canDisplayContent { return }
        await refreshForAppearance(revalidationRevision: revalidationRevision)
    }

    /// The verified article survives scrolling. Each explicit revalidation still needs
    /// a fresh RLS receipt before it can be displayed; no permission TTL exists.
    /// Missing/changed row provenance and feed/safety epochs require full reads.
    func refreshForAppearance(revalidationRevision: Int) async {
        while let flight = appearanceFlight {
            appearanceStatistics.joinedRequests += 1
            await flight.task.value
            guard !Task.isCancelled else { return }
            if flight.revision == revalidationRevision, lastAppearanceRevision == revalidationRevision { return }
        }
        guard !Task.isCancelled, !isDeleted else { return }
        let id = UUID()
        let generation = verificationGeneration
        let task = Task { @MainActor [self] in
            guard generation == verificationGeneration, !Task.isCancelled else {
                if appearanceFlight?.id == id { appearanceFlight = nil }
                return
            }
            isCheckingAccess = true
            let progress = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
                guard let self, self.verificationGeneration == generation, !Task.isCancelled else { return }
                self.showsAccessProgress = true
            }
            defer {
                progress.cancel()
                if showsAccessProgress { showsAccessProgress = false }
                isCheckingAccess = false
                if !hasLoaded { hasLoaded = true }
                if appearanceFlight?.id == id { appearanceFlight = nil }
            }
            if (hasLoaded && !isAvailable)
                || (lastAppearanceRevision != nil && lastAppearanceRevision != revalidationRevision) {
                await refresh()
            } else {
                do {
                    let viewer = try validateScope()
                    guard let remote else { throw CommunitySafetyError.unavailable }
                    appearanceStatistics.accessReads += 1
                    let receipt = try await remote.fetchAccess(id: item.id, viewerID: viewer)
                    guard generation == verificationGeneration, !Task.isCancelled else { throw CancellationError() }
                    _ = try validateScope()
                    guard let receipt, receipt.id == item.id, receipt.authorID == item.authorId,
                          receipt.authorID == viewer || receipt.visibility == .publicPost || receipt.visibility == .mutual || (receipt.visibility == .followers && receipt.post?.audienceContract == 1) else {
                        throw FeedPostManagementError.contentUnavailable
                    }
                    // Match the entire current row, not updated_at alone: the
                    // repository does not guarantee an update trigger for it.
                    // Missing/changed provenance requires the original full read.
                    if let post = receipt.post, let snapshot = item.serverPostSnapshot,
                       post == snapshot, receipt.visibility == item.visibility.feedPostVisibility,
                       receipt.sharedDetailContractEnabled == item.sharedDetailContractEnabled,
                       receipt.sharedDetailAuthorized == (item.permittedSharedDetail != nil),
                       let filtered = safetyStore.filtered([item]).first {
                        if !hasLoaded {
                            item = filtered
                            hasVerifiedArticle = true
                            appearanceStatistics.listSnapshotsReused += 1
                            hasLoaded = true
                            isAvailable = true
                            errorMessage = nil
                        }
                    } else { await refresh() }
                } catch { fail(error) }
            }
            guard generation == verificationGeneration, !Task.isCancelled else {
                isAvailable = false
                return
            }
            if isAvailable { lastAppearanceRevision = revalidationRevision }
        }
        appearanceFlight = AppearanceFlight(id: id, revision: revalidationRevision, task: task)
        await task.value
    }

    /// Revocation is immediate. Late checks cannot revive an earlier scope.
    func invalidateAppearanceVerification() {
        verificationGeneration += 1
        lastAppearanceRevision = nil
        if isAvailable { isAvailable = false }
        appearanceFlight?.task.cancel()
    }

    /// Incoming list snapshots may update already-verified content, but cannot
    /// make an unavailable item readable or retarget a model to another author.
    func adoptIfIdle(_ updatedItem: FeedItem) {
        guard !isWorking, !isDeleted, scopeIsCurrent, updatedItem.id == item.id,
              updatedItem.authorId == item.authorId, !updatedItem.isLocalDraft,
              updatedItem.authorId == viewerID || updatedItem.visibility == .publicFeed || ((updatedItem.visibility == .mutual || updatedItem.visibility == .followers) && hasVerifiedArticle && isAvailable),
              let filtered = safetyStore.filtered([updatedItem]).first else { return }
        item = filtered
    }

    func toggleBookmark() async {
        let desired = !item.viewerHasSaved
        _ = await mutate(requiresOwnership: false, success: desired ? "저장한 기록에 추가했어요." : "저장한 기록에서 해제했어요.",
            operation: { remote, viewerID in
                try await remote.setBookmark(postID: self.item.id, viewerID: viewerID, isSaved: desired)
            }, confirmed: { $0.viewerHasSaved == desired })
    }

    @discardableResult
    func edit(title: String, description: String) async -> Bool {
        do { try WorkoutRecordEditPolicy.validate(title: title, description: description) }
        catch { errorMessage = (error as? LocalizedError)?.errorDescription; return false }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return await mutate(requiresOwnership: true, success: "제목과 설명을 저장했어요.", operation: { remote, ownerID in
            try await remote.editPost(id: self.item.id, ownerID: ownerID, title: title, description: description)
        }, confirmed: { result in
            let refreshedTitle: String
            if case .workoutSession(let card) = result.cardData { refreshedTitle = card.title }
            else { refreshedTitle = result.activityContext }
            return refreshedTitle == title && (result.caption ?? "") == description
        })
    }

    func setVisibility(_ visibility: FeedPostVisibility) async {
        guard visibility == .publicPost || visibility == .mutual || visibility == .followers || visibility == .privatePost else {
            errorMessage = "전체공개, 맞팔공개 또는 나만보기를 선택해 주세요."
            return
        }
        _ = await mutate(requiresOwnership: true,
            success: visibility == .publicPost ? "게시물을 공개했어요."
                : visibility == .mutual ? "게시물을 맞팔공개로 변경했어요." : visibility == .followers ? "승인된 팔로워 공개로 변경했어요." : "게시물을 비공개로 변경했어요.",
            operation: { remote, ownerID in
                try await remote.setVisibility(postID: self.item.id, ownerID: ownerID, visibility: visibility)
            }, confirmed: { $0.visibility == visibility.shareableVisibility })
    }

    func delete() async {
        guard !isWorking, !isDeleted else { return }
        isWorking = true; errorMessage = nil; notice = nil
        defer { isWorking = false; hasLoaded = true }
        do {
            let ownerID = try validateScope()
            guard ownerID == item.authorId, let remote else { throw CommunitySafetyError.invalidTarget }
            let refreshed = try await loadVerifiedItem()
            _ = try validateScope()
            item = refreshed
            try await remote.deletePost(id: item.id, ownerID: ownerID)
            _ = try validateScope()
            isDeleted = true; isAvailable = false
            notice = "게시물을 삭제했어요."
            publishChange()
        } catch { fail(error) }
    }

    private func mutate(requiresOwnership: Bool, success: String,
                        operation: (any FeedPostRemoteManaging, UUID) async throws -> Void,
                        confirmed: (FeedItem) -> Bool) async -> Bool {
        guard !isWorking, !isDeleted else { return false }
        isWorking = true; errorMessage = nil; notice = nil
        defer { isWorking = false; hasLoaded = true }
        do {
            let viewerID = try validateScope()
            guard let remote, !requiresOwnership || viewerID == item.authorId else {
                throw CommunitySafetyError.invalidTarget
            }
            let current = try await loadVerifiedItem()
            _ = try validateScope()
            item = current
            try await operation(remote, viewerID)
            _ = try validateScope()
            // A confirmed mutation should also invalidate other lists when the
            // following read fails. The UI still must not claim final success.
            publishChange()
            let refreshed = try await loadVerifiedItem()
            _ = try validateScope()
            item = refreshed
            guard confirmed(refreshed) else { throw FeedPostManagementError.changeNotConfirmed }
            isAvailable = true; notice = success
            return true
        } catch {
            fail(error)
            return false
        }
    }

    private func fail(_ error: Error) {
        isAvailable = false
        notice = nil
        errorMessage = (error as? FeedPostManagementError)?.errorDescription
            ?? (error as? WorkoutRecordManagementError)?.errorDescription
            ?? CommunitySafetyError.message(for: error)
    }

    private func publishChange() {
        guard scopeIsCurrent else { return }
        NotificationCenter.default.post(name: Self.didChange, object: viewerID, userInfo: ["postID": item.id])
    }

    private func invalidateForSafetyChange() {
        invalidateAppearanceVerification()
        guard scopeIsCurrent else {
            isAvailable = false; notice = nil
            errorMessage = safetyStore.isBlocked(item.authorId)
                ? FeedPostManagementError.contentUnavailable.errorDescription
                : CommunitySafetyError.accountChanged.errorDescription
            return
        }
        if let filtered = safetyStore.filtered([item]).first { item = filtered }
    }
}
