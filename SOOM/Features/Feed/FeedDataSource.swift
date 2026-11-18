import Foundation
import Auth
import OSLog

enum FeedSourceStrategy: Equatable {
    case remoteWithLocalDrafts
    case localDraftsOnly
    case mockOnly
}

enum FeedLoadFailure: Equatable {
    case unavailable
    case remoteFailed
    case signInRequired
    case contractPending

    var title: String {
        switch self {
        case .unavailable: return "온라인 피드를 사용할 수 없어요"
        case .remoteFailed: return "피드를 불러오지 못했어요"
        case .signInRequired: return "로그인이 필요해요"
        case .contractPending: return "팔로잉 피드 연결 준비 중"
        }
    }

    var message: String {
        switch self {
        case .contractPending:
            return "본인 운동은 자동으로 표시돼요. 새 계정 공개범위 계약을 검증하기 전에는 팔로잉 피드를 연결하거나 과거 운동을 추가 공개하지 않아요."
        case .signInRequired:
            return "로그인 상태를 확인하고 다시 연결해 주세요. 기기에 저장한 본인 운동은 계속 볼 수 있어요."
        case .unavailable, .remoteFailed:
            return "잠시 후 다시 시도해 주세요. 기기에 저장한 본인 운동은 계속 볼 수 있어요."
        }
    }

    static func classify(_ error: Error) -> Self {
        if let authError = error as? Auth.AuthError,
           [Auth.ErrorCode.sessionNotFound, .sessionExpired, .refreshTokenNotFound,
            .refreshTokenAlreadyUsed, .badJWT, .invalidJWT, .noAuthorization, .userNotFound].contains(authError.errorCode) {
            return .signInRequired
        }
        return (error as? FeedRepositoryError) == .unconfigured ? .unavailable : .remoteFailed
    }
}

struct FeedLoadResult: Equatable {
    let items: [FeedItem]
    var failure: FeedLoadFailure? = nil
    var hasMore: Bool = false
    /// Oldest server date actually covered by this page, before adding local
    /// history. Older local cards must not push the next server read to the end
    /// of the entire on-device history.
    var remoteCoverageStart: Date? = nil
    /// Exact server projection prefix before own/local merging or filtering.
    /// Nil means membership cannot be proven from this source.
    var remoteProjectionRows: [AccountActivityFeedRow]? = nil
}

enum FeedRemoteCoverage {
    static func visible(_ items: [FeedItem], since boundary: Date?, hasMore: Bool) -> [FeedItem] {
        guard hasMore, let boundary else { return items }
        return items.filter { !$0.isOwnerLocalWorkout || ($0.activityDate ?? $0.createdAt) >= boundary }
    }
}

final class FeedDataSource {
    /// Following uses the server-filtered, RLS-authorized page RPC. Deploy the
    /// prepared mutual-social migration before enabling this client in production.
    static let isFollowFilterEnabled = true
    private(set) var audience: FeedAudience = .all
    func setAudience(_ value: FeedAudience) { audience = value }

    private static let logger = Logger(subsystem: "app.soom.prototype", category: "FeedDataSource")
    private let remoteRepository: FeedRepositoryProtocol?
    private let mockRepository: FeedRepositoryProtocol
    private let draftStore: (any FeedShareDraftStoreProtocol)?
    private let homeContractAvailable: Bool
    private let ownerProjection: (@MainActor ([FeedItem]) -> [FeedItem])?
    private let strategy: FeedSourceStrategy
    private let filterItems: (@MainActor ([FeedItem]) -> [FeedItem])?

    init(
        remoteRepository: FeedRepositoryProtocol? = nil,
        mockRepository: FeedRepositoryProtocol = MockFeedRepository(),
        draftStore: (any FeedShareDraftStoreProtocol)? = nil,
        strategy: FeedSourceStrategy = .remoteWithLocalDrafts,
        filterItems: (@MainActor ([FeedItem]) -> [FeedItem])? = nil,
        ownerProjection: (@MainActor ([FeedItem]) -> [FeedItem])? = nil,
        homeContractAvailable: Bool = false
    ) {
        self.remoteRepository = remoteRepository
        self.mockRepository = mockRepository
        self.draftStore = draftStore
        self.strategy = strategy
        self.filterItems = filterItems
        self.ownerProjection = ownerProjection
        self.homeContractAvailable = homeContractAvailable
    }

    func loadFeed(limit: Int = 20) async -> FeedLoadResult {
        await loadFeedPage(limit: limit, offset: 0)
    }

    func loadFeedPage(limit: Int, offset: Int) async -> FeedLoadResult {
        guard limit > 0, offset >= 0 else { return FeedLoadResult(items: []) }
        if audience == .home && !homeContractAvailable {
            return FeedLoadResult(items: await mergedWithDrafts([], limit: limit, includeDrafts: offset == 0),
                failure: strategy == .localDraftsOnly ? nil : .contractPending)
        }
        // Being a guest is a normal local state. Do not start authenticated
        // requests just to turn the missing session into a server-error card.
        if strategy == .localDraftsOnly {
            if audience == .following { return FeedLoadResult(items: [], failure: .signInRequired) }
            return FeedLoadResult(items: await mergedWithDrafts([], limit: limit, includeDrafts: offset == 0 && audience != .following))
        }
        if strategy == .mockOnly {
            let items = (try? await mockRepository.fetchFeedPage(limit: limit, offset: offset)) ?? []
            return FeedLoadResult(items: await mergedWithDrafts(items, limit: limit, includeDrafts: offset == 0 && audience != .following),
                hasMore: items.count == limit)
        }

        guard let remoteRepository else {
            return FeedLoadResult(items: await mergedWithDrafts([], limit: limit, includeDrafts: offset == 0 && audience != .following), failure: .unavailable)
        }

        do {
            // A successful empty response is a real empty feed, not a reason to
            // substitute sample posts. Local drafts remain available in either case.
            let trace = LoadTrace("feed-source-local-merge")
            let items = try await remoteRepository.fetchFeedPage(limit: limit, offset: offset, audience: audience)
            trace.mark("remote-page-complete")
            let merged = await mergedWithDrafts(items, limit: limit, includeDrafts: offset == 0 && audience != .following)
            trace.mark("local-merge-filter-complete")
            return FeedLoadResult(items: merged,
                hasMore: items.count == limit,
                remoteCoverageStart: items.map { $0.activityDate ?? $0.createdAt }.min(),
                remoteProjectionRows: audience == .home && items.allSatisfy({ $0.activityProjection?.readPolicy == .profileOnlyV2 })
                    ? items.compactMap(\.activityProjection) : nil)
        } catch {
            let failure = FeedLoadFailure.classify(error)
            if failure != .signInRequired {
                Self.logger.error("Feed fetch failed: \(String(describing: error), privacy: .private)")
            }
            return FeedLoadResult(items: await mergedWithDrafts([], limit: limit, includeDrafts: offset == 0 && audience != .following), failure: failure)
        }
    }

    /// Notification deep links only point at real server posts. A failed or
    /// missing production lookup must never resolve to a sample post instead.
    func loadPost(id: UUID) async -> FeedItem? {
        guard strategy != .localDraftsOnly else { return nil }
        if strategy == .mockOnly {
            return try? await mockRepository.fetchPost(id: id)
        }
        guard let remoteRepository else { return nil }
        do {
            return try await remoteRepository.fetchPost(id: id)
        } catch {
            Self.logger.error("Feed post fetch failed: \(String(describing: error), privacy: .private)")
            return nil
        }
    }

    private func mergedWithDrafts(_ items: [FeedItem], limit: Int, includeDrafts: Bool) async -> [FeedItem] {
        if audience == .home, includeDrafts, let ownerProjection {
            let projected = await ownerProjection(items)
            return await filterItems?(projected) ?? projected
        }
        guard includeDrafts, let draftStore else {
            let visible = Array(Self.uniqueWorkoutCards(items.sorted(by: Self.newestActivityFirst)).prefix(max(0, limit)))
            return await filterItems?(visible) ?? visible
        }

        let draftItems = ((try? await draftStore.fetchDrafts()) ?? []).map { draft in
            draft.makeFeedItem()
        }
        let visible = Self.uniqueWorkoutCards((draftItems + items).sorted(by: Self.newestActivityFirst))
        return await filterItems?(visible) ?? visible
    }

    static func uniqueWorkoutCards(_ items: [FeedItem]) -> [FeedItem] {
        var visible: [FeedItem] = []
        for item in items {
            guard let index = visible.firstIndex(where: { sameWorkoutCard($0, item) }) else {
                visible.append(item)
                continue
            }
            let current = visible[index]
            let currentDetail = current.reactions.count + current.comments.count + current.photos.count
            let newDetail = item.reactions.count + item.comments.count + item.photos.count
            if newDetail > currentDetail { visible[index] = item }
        }
        return visible
    }

    private static func sameWorkoutCard(_ a: FeedItem, _ b: FeedItem) -> Bool {
        guard a.itemType == .workoutSession, b.itemType == .workoutSession,
              !a.isLocalDraft, !b.isLocalDraft, a.authorId == b.authorId,
              let firstDate = a.activityDate, let secondDate = b.activityDate,
              abs(firstDate.timeIntervalSince(secondDate)) <= 120,
              case let .workoutSession(firstCard) = a.cardData,
              case let .workoutSession(secondCard) = b.cardData,
              firstCard.workoutType == secondCard.workoutType,
              let firstDuration = a.workoutDurationSeconds,
              let secondDuration = b.workoutDurationSeconds,
              ratio(firstDuration, secondDuration) <= 0.05 else { return false }
        if let firstDistance = a.workoutDistanceMeters, let secondDistance = b.workoutDistanceMeters,
           firstDistance > 0, secondDistance > 0 {
            return ratio(firstDistance, secondDistance) <= 0.08
        }
        return false
    }

    private static func ratio(_ a: Double, _ b: Double) -> Double {
        let largest = max(abs(a), abs(b))
        return largest > 0 ? abs(a - b) / largest : 0
    }

    private static func newestActivityFirst(_ lhs: FeedItem, _ rhs: FeedItem) -> Bool {
        FeedDisplayOrder.newestFirst(lhs, rhs)
    }
}
