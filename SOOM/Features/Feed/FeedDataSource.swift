import Foundation

struct FeedSourceStrategy: Equatable {
    let useRemoteWhenAvailable: Bool

    static let remoteWithMockFallback = FeedSourceStrategy(useRemoteWhenAvailable: true)
    static let mockOnly = FeedSourceStrategy(useRemoteWhenAvailable: false)
}

final class FeedDataSource {
    private let remoteRepository: FeedRepositoryProtocol?
    private let fallbackRepository: FeedRepositoryProtocol
    private let strategy: FeedSourceStrategy

    init(
        remoteRepository: FeedRepositoryProtocol? = nil,
        fallbackRepository: FeedRepositoryProtocol = MockFeedRepository(),
        strategy: FeedSourceStrategy = .remoteWithMockFallback
    ) {
        self.remoteRepository = remoteRepository
        self.fallbackRepository = fallbackRepository
        self.strategy = strategy
    }

    func loadFeed(limit: Int = 20) async -> [FeedItem] {
        if strategy.useRemoteWhenAvailable, let remoteRepository {
            do {
                let remoteItems = try await remoteRepository.fetchFeed(limit: limit)
                if remoteItems.isEmpty == false {
                    return remoteItems
                }
            } catch {
                return await fallbackFeed(limit: limit)
            }
        }

        return await fallbackFeed(limit: limit)
    }

    private func fallbackFeed(limit: Int) async -> [FeedItem] {
        (try? await fallbackRepository.fetchFeed(limit: limit)) ?? Array(FeedMockData.items.prefix(limit))
    }
}
