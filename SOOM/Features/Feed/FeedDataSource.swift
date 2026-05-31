import Foundation

struct FeedSourceStrategy: Equatable {
    let useRemoteWhenAvailable: Bool

    static let remoteWithMockFallback = FeedSourceStrategy(useRemoteWhenAvailable: true)
    static let mockOnly = FeedSourceStrategy(useRemoteWhenAvailable: false)
}

final class FeedDataSource {
    private let remoteRepository: FeedRepositoryProtocol?
    private let fallbackRepository: FeedRepositoryProtocol
    private let draftStore: (any FeedShareDraftStoreProtocol)?
    private let strategy: FeedSourceStrategy

    init(
        remoteRepository: FeedRepositoryProtocol? = nil,
        fallbackRepository: FeedRepositoryProtocol = MockFeedRepository(),
        draftStore: (any FeedShareDraftStoreProtocol)? = nil,
        strategy: FeedSourceStrategy = .remoteWithMockFallback
    ) {
        self.remoteRepository = remoteRepository
        self.fallbackRepository = fallbackRepository
        self.draftStore = draftStore
        self.strategy = strategy
    }

    func loadFeed(limit: Int = 20) async -> [FeedItem] {
        if strategy.useRemoteWhenAvailable, let remoteRepository {
            do {
                let remoteItems = try await remoteRepository.fetchFeed(limit: limit)
                if remoteItems.isEmpty == false {
                    return await mergedWithDrafts(remoteItems, limit: limit)
                }
            } catch {
                return await fallbackFeed(limit: limit)
            }
        }

        return await fallbackFeed(limit: limit)
    }

    private func fallbackFeed(limit: Int) async -> [FeedItem] {
        let fallbackItems = (try? await fallbackRepository.fetchFeed(limit: limit)) ?? Array(FeedMockData.items.prefix(limit))
        return await mergedWithDrafts(fallbackItems, limit: limit)
    }

    private func mergedWithDrafts(_ items: [FeedItem], limit: Int) async -> [FeedItem] {
        guard let draftStore else {
            return Array(items.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
        }

        let draftItems = ((try? await draftStore.fetchDrafts()) ?? []).map { draft in
            draft.makeFeedItem()
        }
        return Array((draftItems + items).sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }
}
