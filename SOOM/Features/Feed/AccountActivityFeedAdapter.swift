import Foundation
import Supabase

struct AccountActivityReadContext: Equatable {
    let viewerID: UUID
    let generation: Int
    let safetyRevision: Int
}

enum AccountActivityAdapterError: Error, Equatable {
    case unreleased, accountChanged, changedDuringRead, invalidLegacyPost, unlinkedProjection
}

@MainActor
protocol AccountActivityFeedTransport {
    var readPolicy: AccountActivityReadPolicy { get }
    var context: AccountActivityReadContext? { get }
    func page(_ request: AccountActivityPageRequest) async throws -> AccountActivityFeedPage
    func card(_ id: UUID) async throws -> AccountActivityCardEnvelope
    func approvedOwners(_ ids: [UUID]) async throws -> Set<UUID>
    func legacy(cardID: UUID) async throws -> AccountActivityLegacyDetailReceipt?
    func post(id: UUID) async throws -> FeedItem?
    func legacyHome(_ request: AccountActivityPageRequest, postID: UUID?) async throws -> [FeedItem]
}
extension AccountActivityFeedTransport {
    var readPolicy: AccountActivityReadPolicy { .approvedFollowersV1 }
    func card(_ id: UUID) async throws -> AccountActivityCardEnvelope { throw AccountActivityAdapterError.unreleased }
    func legacyHome(_ request: AccountActivityPageRequest, postID: UUID? = nil) async throws -> [FeedItem] { [] }
}

struct AccountActivityHydratedCard {
    let projection: AccountActivityFeedRow
    let legacyItem: FeedItem?
}
struct AccountActivityHydratedPage {
    let cards: [AccountActivityHydratedCard]
    let nextCursor: AccountActivityCursor?
    let hasMore: Bool

    /// Never substitute a projection UUID for an existing post/comment FK.
    /// Until the independent summary UI is wired, missing links fail explicitly.
    func displayItems() -> [FeedItem] {
        cards.map { $0.legacyItem ?? Self.summaryItem($0.projection) }
    }
    private static func summaryItem(_ row: AccountActivityFeedRow) -> FeedItem {
        let sport = UnifiedWorkoutType(rawValue: row.sport) ?? .other
        let date = row.cursor?.activityAt ?? .distantPast
        let card = ShareableWorkoutCardModel(id: row.canonicalID, workoutType: sport,
            title: "운동 기록", distanceText: row.distanceMeters.map { String(format: "%.1f km", $0 / 1000) } ?? "거리 정보 없음",
            durationText: "\(row.durationSeconds / 60)분", averagePaceText: "—",
            primaryMessage: "계정 공개범위에 따라 공유된 운동 요약", growthMessage: "댓글과 사진 연결 준비 중", recoveryMessage: "",
            footerText: "SOOM", visibility: .privateOnly,
            staticRoutePreview: StaticRoutePreview(imageURL: nil, bounds: nil, routeExists: false,
                fallbackStyle: StaticRouteFallbackStyle(workoutType: sport)))
        return FeedItem(id: row.cardID, authorName: "SOOM 사용자", authorHandle: nil, authorId: row.ownerID,
            activityProjection: row, createdAt: date, itemType: .workoutSession, visibility: .privateOnly,
            cardData: .workoutSession(card), sourceWorkoutId: row.canonicalID, caption: nil,
            activityContext: "운동 요약", activityDate: date, workoutDistanceMeters: row.distanceMeters,
            workoutDurationSeconds: Double(row.durationSeconds))
    }
    func legacyFeedItems() throws -> [FeedItem] {
        guard cards.allSatisfy({ $0.legacyItem != nil }) else { throw AccountActivityAdapterError.unlinkedProjection }
        return cards.compactMap(\.legacyItem)
    }
}

@MainActor
final class AccountActivityFeedAdapter {
    private let transport: any AccountActivityFeedTransport
    private let synthetic: Bool
    private let preview: Bool
    init(transport: any AccountActivityFeedTransport, preview: Bool = false) { self.transport = transport; synthetic = false; self.preview = preview }
    #if DEBUG
    init(syntheticTransport: any AccountActivityFeedTransport) { transport = syntheticTransport; synthetic = true; preview = false }
    #endif

    func load(_ request: AccountActivityPageRequest, now: Date = Date()) async throws -> AccountActivityHydratedPage {
        guard !preview || transport.readPolicy == .approvedFollowersV1 else { throw AccountActivityAdapterError.unreleased }
        guard synthetic || (preview && transport.readPolicy == .approvedFollowersV1) || transport.readPolicy.productionReady else { throw AccountActivityAdapterError.unreleased }
        guard let initial = transport.context, initial.viewerID == request.viewerID else { throw AccountActivityAdapterError.accountChanged }
        func check() throws {
            guard transport.context == initial, !Task.isCancelled else { throw AccountActivityAdapterError.accountChanged }
        }
        let policy = transport.readPolicy
        let trace = LoadTrace("feed-page-chain")
        trace.mark("limit-\(request.limit)")
        defer { trace.mark("operation-ended") }
        let page = try await transport.page(request); try check(); trace.mark("page-read-1")
        guard transport.readPolicy == policy else { throw AccountActivityAdapterError.changedDuringRead }
        // Own rows are authorized by the viewer match, not a follow relation.
        // Keep both membership reads unchanged whenever any foreign row exists.
        let needsMembership = request.scope == .home && (policy != .profileOnlyV2 || page.rows.contains { $0.ownerID != initial.viewerID })
        let owners = needsMembership ? try await transport.approvedOwners(Array(Set(page.rows.map(\.ownerID)))) : []
        try check(); trace.mark("membership-read-1")
        try page.validateCandidate(request: request, currentViewerID: initial.viewerID, allowedHomeOwners: owners, latestPermittedDate: now, expectedPolicy: policy)
        guard synthetic || (preview ? !page.releaseReady : page.releaseReady) else { throw AccountActivityAdapterError.unreleased }
        var cards: [AccountActivityHydratedCard] = []
        var usedLegacy = Set<UUID>()
        for var row in page.rows {
            row.readPolicy = policy
            // A profile-only summary keeps canonical identity and never inherits
            // a legacy post's more permissive or stale detail payload.
            if policy == .profileOnlyV2 { cards.append(.init(projection: row, legacyItem: nil)); continue }
            let link = try await transport.legacy(cardID: row.cardID); try check()
            guard let link else {
                cards.append(.init(projection: row, legacyItem: nil)); continue
            }
            try link.validateCandidate(expectedCardID: row.cardID, requestViewerID: initial.viewerID,
                currentViewerID: transport.context?.viewerID, requestGeneration: initial.generation,
                currentGeneration: transport.context?.generation ?? -1)
            guard synthetic || (preview ? !link.releaseReady : link.releaseReady) else { throw AccountActivityAdapterError.unreleased }
            guard usedLegacy.insert(link.legacyPostID).inserted else { throw AccountActivityAdapterError.invalidLegacyPost }
            let post = try await transport.post(id: link.legacyPostID); try check()
            guard let post, post.id == link.legacyPostID, post.authorId == row.ownerID, !post.isLocalDraft else {
                throw AccountActivityAdapterError.invalidLegacyPost
            }
            // Fresh intersection after hydrated comments/photos. No stale cached
            // grant survives a privacy change or link reassignment mid-request.
            let finalLink = try await transport.legacy(cardID: row.cardID); try check()
            guard finalLink == link else { throw AccountActivityAdapterError.changedDuringRead }
            cards.append(.init(projection: row, legacyItem: post))
        }
        let finalPage = try await transport.page(request); try check(); trace.mark("page-read-2")
        guard finalPage.viewerID == page.viewerID, finalPage.scope == page.scope,
              finalPage.version == page.version, finalPage.rows == page.rows,
              finalPage.releaseReady == page.releaseReady else { throw AccountActivityAdapterError.changedDuringRead }
        let finalOwners = needsMembership ? try await transport.approvedOwners(Array(Set(page.rows.map(\.ownerID)))) : []
        try check(); trace.mark("membership-read-2")
        try finalPage.validateCandidate(request: request, currentViewerID: initial.viewerID,
            allowedHomeOwners: finalOwners, latestPermittedDate: now, expectedPolicy: policy)
        guard transport.readPolicy == policy else { throw AccountActivityAdapterError.changedDuringRead }
        return .init(cards: cards, nextCursor: page.nextCursor, hasMore: page.rows.count == request.limit)
    }
}

/// Real read-only RPC transport. The gate is checked inside this transport too:
/// a DEBUG injected adapter cannot accidentally enable network access.
@MainActor
struct SupabaseAccountActivityFeedTransport: AccountActivityFeedTransport {
    let client: SupabaseClient
    let legacyRepository: any FeedRepositoryProtocol
    var preview: Bool = false
    var readPolicy: AccountActivityReadPolicy = .approvedFollowersV1
    var context: AccountActivityReadContext? {
        let safety = CommunitySafetyStore.shared
        guard let id = client.auth.currentSession?.user.id, safety.viewerID == id, (safety.canUseSocial || (preview && safety.canUseActivityPreview)) else { return nil }
        return .init(viewerID: id, generation: safety.accountGeneration, safetyRevision: safety.revision)
    }
    private func authorize() async throws {
        guard !preview || readPolicy == .approvedFollowersV1 else { throw AccountActivityAdapterError.unreleased }
        if preview {
            guard let owner = context?.viewerID, try await AccountActivityPreviewService(client: client, owner: owner).capability().enabled else { throw AccountActivityAdapterError.unreleased }
        }
        guard preview || readPolicy.productionReady else { throw AccountActivityAdapterError.unreleased }
        guard context != nil else { throw AccountActivityAdapterError.accountChanged }
    }
    func page(_ request: AccountActivityPageRequest) async throws -> AccountActivityFeedPage {
        try await authorize(); try request.validate()
        guard context?.viewerID == request.viewerID else { throw AccountActivityAdapterError.accountChanged }
        struct Params: Encodable { let p_scope: String; let p_owner: UUID?; let p_before_at: Date?; let p_before_id: UUID?; let p_limit: Int }
        return try await client.rpc(try readPolicy.pageRPC(preview: preview), params: Params(p_scope: request.scope.rawValue,
            p_owner: request.ownerID, p_before_at: request.before?.activityAt, p_before_id: request.before?.cardID, p_limit: request.limit)).execute().value
    }
    func card(_ id: UUID) async throws -> AccountActivityCardEnvelope {
        try await authorize()
        struct Params: Encodable { let p_card_id: UUID }
        return try await client.rpc(try readPolicy.cardRPC(preview: preview), params: Params(p_card_id: id)).execute().value
    }
    func approvedOwners(_ ids: [UUID]) async throws -> Set<UUID> {
        try await authorize()
        if readPolicy == .profileOnlyV2 {
            struct Params: Encodable { let p_owners: [UUID] }
            let owners: [UUID] = try await client.rpc("soom_activity_following_candidate_v2", params: Params(p_owners: ids)).execute().value
            return Set(owners)
        }
        if preview {
            struct Params: Encodable { let p_owners: [UUID] }
            let owners: [UUID] = try await client.rpc("soom_activity_preview_following_v1", params: Params(p_owners: ids)).execute().value
            return Set(owners)
        }
        let rows = try await SupabaseAccountPrivacyService(client: client).states(ids)
        return Set(rows.filter { $0.state == .accepted }.map(\.userID))
    }
    func legacy(cardID: UUID) async throws -> AccountActivityLegacyDetailReceipt? {
        try await authorize()
        struct Params: Encodable { let p_card_id: UUID }
        return try await client.rpc(preview ? "soom_activity_legacy_detail_preview_v1" : readPolicy.interactionRPC("soom_activity_legacy_detail_candidate_v1"), params: Params(p_card_id: cardID)).execute().value
    }
    func legacyHome(_ request: AccountActivityPageRequest, postID: UUID?) async throws -> [FeedItem] {
        guard context?.viewerID == request.viewerID else { throw AccountActivityAdapterError.accountChanged }
        return try await SupabaseFeedRemoteClient(client: client).previewLegacyHome(request, postID: postID)
    }
    func post(id: UUID) async throws -> FeedItem? {
        try await authorize()
        return try await legacyRepository.fetchPost(id: id)
    }
}

/// Offset-compatible bridge keeps a keyset only after a fully validated page.
/// Unknown offsets never trigger an unscoped/global query.
@MainActor
final class AccountActivityHomeRepository: FeedRepositoryProtocol {
    private let legacy: any FeedRepositoryProtocol
    private let transport: any AccountActivityFeedTransport
    private let adapter: AccountActivityFeedAdapter
    private var emittedLegacyKeys = Set<String>()
    private var includesLegacyPreview = false
    private var pageGeneration = 0
    private var epoch: AccountActivityReadContext?
    private var cursors: [Int: AccountActivityCursor] = [:]
    init(legacy: any FeedRepositoryProtocol, transport: any AccountActivityFeedTransport, preview: Bool = false, legacyFallback: Bool = false) {
        self.legacy = legacy; self.transport = transport; includesLegacyPreview = transport.readPolicy == .approvedFollowersV1 && (preview || legacyFallback); adapter = AccountActivityFeedAdapter(transport: transport, preview: preview)
    }
    #if DEBUG
    init(legacy: any FeedRepositoryProtocol, syntheticTransport: any AccountActivityFeedTransport) {
        self.legacy = legacy; transport = syntheticTransport; adapter = AccountActivityFeedAdapter(syntheticTransport: syntheticTransport)
    }
    #endif
    func fetchFeed(limit: Int) async throws -> [FeedItem] { try await fetchFeedPage(limit: limit, offset: 0, audience: .home) }
    func fetchFeedPage(limit: Int, offset: Int) async throws -> [FeedItem] { try await fetchFeedPage(limit: limit, offset: offset, audience: .home) }
    func fetchFeedPage(limit: Int, offset: Int, audience: FeedAudience) async throws -> [FeedItem] {
        guard audience == .home else { return try await legacy.fetchFeedPage(limit: limit, offset: offset, audience: audience) }
        guard limit > 0, offset >= 0 else { throw AccountActivityContractError.invalidRequest }
        guard let current = transport.context else { throw AccountActivityAdapterError.accountChanged }
        // A changed authorization epoch must never regain an old cursor. A refresh
        // in the same epoch supersedes in-flight work but preserves committed state
        // until its entire replacement range has been verified successfully.
        if epoch != current { epoch = current; cursors = [:]; emittedLegacyKeys = []; pageGeneration += 1 }
        if offset == 0 { pageGeneration += 1 }
        let generation = pageGeneration
        let policy = transport.readPolicy
        guard offset == 0 || cursors[offset] != nil else { throw AccountActivityContractError.invalidRequest }
        var stagedCursors = offset == 0 ? [:] : cursors
        var seen = offset == 0 ? Set<String>() : emittedLegacyKeys
        var boundary = offset == 0 ? nil : cursors[offset]
        var output: [FeedItem] = []
        func check() throws {
            try Task.checkCancellation()
            guard transport.context == current, pageGeneration == generation,
                  transport.readPolicy == policy else { throw AccountActivityAdapterError.accountChanged }
        }
        while output.count < limit {
            try check()
            let count = min(100, limit - output.count)
            let items: [FeedItem]
            let next: AccountActivityCursor?
            if includesLegacyPreview {
                let page = try await mergedPage(limit: count, boundary: boundary, seen: seen,
                    current: current, generation: generation)
                items = page.items; next = page.cursor; seen = page.seen
            } else {
                let page = try await adapter.load(.init(viewerID: current.viewerID, scope: .home,
                    ownerID: nil, before: boundary, limit: count))
                items = page.displayItems(); next = page.hasMore ? page.nextCursor : nil
            }
            try check()
            guard items.count <= count else { throw AccountActivityContractError.invalidRequest }
            output.append(contentsOf: items)
            if items.count < count { break }
            // A full page must supply a progressing cursor; otherwise never spin.
            guard let next, next != boundary else { throw AccountActivityContractError.invalidRequest }
            boundary = next
            stagedCursors[offset + output.count] = next
        }
        try check()
        cursors = stagedCursors; emittedLegacyKeys = seen
        return output
    }
    private func mergedPage(limit: Int, boundary initialBoundary: AccountActivityCursor?, seen initialSeen: Set<String>,
                            current: AccountActivityReadContext, generation: Int) async throws
        -> (items: [FeedItem], cursor: AccountActivityCursor?, seen: Set<String>) {
        var boundary = initialBoundary, output: [FeedItem] = [], seen = initialSeen
        for _ in 0..<10 {
            let request = AccountActivityPageRequest(viewerID: current.viewerID, scope: .home, ownerID: nil, before: boundary, limit: limit)
            // Each source proves its own access. A failing optional projection
            // must not discard independently RLS-authorized existing posts.
            var old: [FeedItem] = []
            var projected: [FeedItem] = []
            var projectionRows: [AccountActivityFeedRow] = []
            var oldSucceeded = false
            var previewSucceeded = false
            var sourceError: Error = AccountActivityAdapterError.unreleased
            do {
                old = try await transport.legacyHome(request, postID: nil)
                oldSucceeded = true
            } catch { sourceError = error }
            guard transport.context == current, pageGeneration == generation, !Task.isCancelled else { throw AccountActivityAdapterError.accountChanged }
            do {
                let page = try await adapter.load(request)
                projected = page.displayItems()
                projectionRows = page.cards.map(\.projection)
                previewSucceeded = true
            } catch { sourceError = error }
            guard transport.context == current, pageGeneration == generation, !Task.isCancelled else { throw AccountActivityAdapterError.accountChanged }
            guard oldSucceeded || previewSucceeded else { throw sourceError }
            // Refresh successful legacy rows after the other source's network work.
            // Failed refresh removes only that source, never revives a cached grant.
            if oldSucceeded && !old.isEmpty {
                do { old = try await transport.legacyHome(request, postID: nil) }
                catch { old = []; oldSucceeded = false; sourceError = error }
            }
            guard transport.context == current, pageGeneration == generation, !Task.isCancelled else { throw AccountActivityAdapterError.accountChanged }
            guard oldSucceeded || previewSucceeded else { throw sourceError }
            if previewSucceeded {
                do {
                    let final = try await transport.page(request)
                    let owners = try await transport.approvedOwners(Array(Set(final.rows.map(\.ownerID))))
                    try final.validateCandidate(request: request, currentViewerID: current.viewerID, allowedHomeOwners: owners, latestPermittedDate: Date())
                    guard !final.releaseReady, final.rows == projectionRows else { throw AccountActivityAdapterError.changedDuringRead }
                } catch { projected = []; previewSucceeded = false; sourceError = error }
            }
            guard transport.context == current, pageGeneration == generation, !Task.isCancelled else { throw AccountActivityAdapterError.accountChanged }
            guard oldSucceeded || previewSucceeded else { throw sourceError }
            let candidates = Self.mergePreviewAndLegacy(projected, old, limit: limit)
            guard !candidates.isEmpty else { return (output, nil, seen) }
            for item in candidates {
                boundary = .init(activityAt: item.activityDate ?? item.createdAt, cardID: item.activityProjection?.cardID ?? item.id)
                let identity = "post:\(item.id)"
                let canonical = item.activityProjection?.canonicalID ?? item.sourceWorkoutId
                let workout = canonical.map { "workout:\(item.authorId):\($0)" }
                if seen.contains(identity) || workout.map({ seen.contains($0) }) == true { continue }
                seen.insert(identity); if let workout { seen.insert(workout) }; output.append(item)
                if output.count == limit {
                    return (output, boundary, seen)
                }
            }
            if candidates.count < limit { return (output, nil, seen) }
        }
        // Bounded work; no partial page/cursor is committed after excessive duplication.
        throw AccountActivityContractError.invalidRequest
    }
    static func mergePreviewAndLegacy(_ preview: [FeedItem], _ legacy: [FeedItem], limit: Int) -> [FeedItem] {
        // Exact identities only: nearby dates can describe genuinely different workouts.
        var seen = Set<UUID>()
        let legacyKeys = Set(legacy.compactMap { item in item.sourceWorkoutId.map { "\(item.authorId):\($0)" } })
        let rows = legacy + preview.filter { item in
            guard let row = item.activityProjection else { return true }
            return !legacyKeys.contains("\(row.ownerID):\(row.canonicalID)")
        }
        return Array(rows.filter { seen.insert($0.id).inserted }.sorted {
            let a = $0.activityDate ?? $0.createdAt, b = $1.activityDate ?? $1.createdAt
            return a == b ? $0.id.uuidString > $1.id.uuidString : a > b
        }.prefix(limit))
    }
    func fetchSavedPosts() async throws -> [FeedItem] { try await legacy.fetchSavedPosts() }
    func fetchPost(id: UUID) async throws -> FeedItem? {
        if includesLegacyPreview {
            guard let initial = transport.context else { throw AccountActivityAdapterError.accountChanged }
            let items = try await transport.legacyHome(.init(viewerID: initial.viewerID, scope: .home, ownerID: nil, before: nil, limit: 1), postID: id)
            guard transport.context == initial else { throw AccountActivityAdapterError.accountChanged }
            return items.first
        }
        return try await legacy.fetchPost(id: id)
    }
}

/// The v2 summary grant never authorizes the historical post by itself. This
/// independent tap intersects fresh card + mapping + original post RLS twice.
@MainActor final class AccountActivityLinkedLegacyDetailAdapter {
    private let transport: any AccountActivityFeedTransport
    private let fixture: Bool
    init(transport: any AccountActivityFeedTransport) { self.transport = transport; fixture = false }
    #if DEBUG
    init(syntheticTransport: any AccountActivityFeedTransport) { transport = syntheticTransport; fixture = true }
    #endif
    func load(row: AccountActivityFeedRow, now: Date = Date()) async throws -> FeedItem {
        guard let item = try await loadIfLinked(row: row, now: now) else { throw AccountActivityAdapterError.unlinkedProjection }
        return item
    }
    /// Nil means a freshly verified summary has no accessible historical thread.
    /// Network errors and mid-read revocation never silently choose a different thread.
    func loadIfLinked(row: AccountActivityFeedRow, now: Date = Date()) async throws -> FeedItem? {
        let policy = transport.readPolicy
        guard row.readPolicy == policy, fixture || policy.productionReady else { throw AccountActivityAdapterError.unreleased }
        guard let initial = transport.context else { throw AccountActivityAdapterError.accountChanged }
        func check() throws {
            guard !Task.isCancelled, transport.context == initial, transport.readPolicy == policy else { throw AccountActivityAdapterError.accountChanged }
        }
        func card() async throws {
            let envelope = try await transport.card(row.cardID); try check()
            guard envelope.releaseReady == !fixture,
                  try envelope.validateCandidate(expectedCardID: row.cardID, requestViewerID: initial.viewerID,
                    currentViewerID: transport.context?.viewerID, requestGeneration: initial.generation,
                    currentGeneration: transport.context?.generation ?? -1, latestPermittedDate: now,
                    expectedOwnerID: row.ownerID, expectedPolicy: policy) == row else { throw AccountActivityAdapterError.changedDuringRead }
        }
        try await card()
        guard let link = try await transport.legacy(cardID: row.cardID) else {
            try check(); try await card(); return nil
        }
        try check()
        // The reviewed v2 mapping intentionally retains the original v1 detail
        // receipt format. It is NOT a version-1 summary authorization.
        try link.validateCandidate(expectedCardID: row.cardID, requestViewerID: initial.viewerID,
            currentViewerID: transport.context?.viewerID, requestGeneration: initial.generation,
            currentGeneration: transport.context?.generation ?? -1)
        guard link.releaseReady == !fixture else { throw AccountActivityAdapterError.unreleased }
        guard let post = try await transport.post(id: link.legacyPostID), post.id == link.legacyPostID,
              post.authorId == row.ownerID, !post.isLocalDraft, post.activityProjection == nil else { throw AccountActivityAdapterError.invalidLegacyPost }
        try check()
        let confirmed = try await transport.legacy(cardID: row.cardID); try check()
        guard confirmed == link else { throw AccountActivityAdapterError.changedDuringRead }
        try await card()
        return post
    }
}

/// Preserve the original photo identity and bucket; never relabel legacy media
/// as native. The renderer still authorizes storage metadata and download.
enum AccountActivityLegacyMedia {
    static func photos(from item: FeedItem, ownerID: UUID) -> [WorkoutPhotoReference] {
        guard item.authorId == ownerID, !item.isLocalDraft, item.activityProjection == nil else { return [] }
        var seen = Set<UUID>()
        return Array(item.photos.filter { photo in
            photo.nativeCardID == nil && WorkoutPhotoPolicy.validPath(photo.storagePath)
                && photo.storagePath == WorkoutPhotoPolicy.path(ownerID: ownerID, postID: item.id, photoID: photo.id)
                && seen.insert(photo.id).inserted
        }.prefix(WorkoutPhotoPolicy.maximumCount))
    }
}


extension AccountActivityLinkedLegacyDetailAdapter {
    /// Card-only optional decoration. Preserve card/link permission fences but
    /// never invoke the full legacy post/photos/social/telemetry loader.
    func loadCardPreview(row: AccountActivityFeedRow, now: Date = Date(),
        read: @MainActor (UUID, AccountActivityReadContext) async throws -> FeedCardPreviewRead?) async throws -> FeedLinkedCardPresentation? {
        let policy = transport.readPolicy
        guard row.readPolicy == policy, fixture || policy.productionReady else { throw AccountActivityAdapterError.unreleased }
        guard let initial = transport.context else { throw AccountActivityAdapterError.accountChanged }
        func check() throws {
            guard !Task.isCancelled, transport.context == initial, transport.readPolicy == policy else { throw AccountActivityAdapterError.accountChanged }
        }
        func card() async throws {
            let envelope = try await transport.card(row.cardID); try check()
            guard envelope.releaseReady == !fixture,
                  try envelope.validateCandidate(expectedCardID: row.cardID, requestViewerID: initial.viewerID,
                    currentViewerID: transport.context?.viewerID, requestGeneration: initial.generation,
                    currentGeneration: transport.context?.generation ?? -1, latestPermittedDate: now,
                    expectedOwnerID: row.ownerID, expectedPolicy: policy) == row else { throw AccountActivityAdapterError.changedDuringRead }
        }
        try await card()
        guard let link = try await transport.legacy(cardID: row.cardID) else {
            try check(); try await card(); return nil
        }
        try check()
        try link.validateCandidate(expectedCardID: row.cardID, requestViewerID: initial.viewerID,
            currentViewerID: transport.context?.viewerID, requestGeneration: initial.generation,
            currentGeneration: transport.context?.generation ?? -1)
        guard link.releaseReady == !fixture else { throw AccountActivityAdapterError.unreleased }
        let preview = try await read(link.legacyPostID, initial)
        try check()
        if let preview {
            guard preview.postID == link.legacyPostID, preview.ownerID == row.ownerID else { throw AccountActivityAdapterError.invalidLegacyPost }
        }
        let confirmed = try await transport.legacy(cardID: row.cardID); try check()
        guard confirmed == link else { throw AccountActivityAdapterError.changedDuringRead }
        try await card()
        return preview?.presentation
    }
}

/// Freshly verified absence of a historical link is not a detail-load error.
/// The adapter owns remote authorization; the caller owns current UI/account scope.
@MainActor enum AccountActivityDetailNavigation {
    static func perform(
        loadIfLinked: () async throws -> FeedItem?,
        isCurrent: () -> Bool,
        openLegacy: (FeedItem) -> Void,
        openSummary: () -> Void
    ) async throws {
        try Task.checkCancellation()
        guard isCurrent() else { return }
        let item = try await loadIfLinked()
        try Task.checkCancellation()
        guard isCurrent() else { return }
        if let item { openLegacy(item) } else { openSummary() }
    }
}
