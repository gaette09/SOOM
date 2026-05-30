import Foundation

enum FeedRepositoryError: Error, Equatable {
    case unconfigured
    case remoteFetchNotImplemented
    case remoteFailed
}

protocol FeedRepositoryProtocol {
    func fetchFeed(limit: Int) async throws -> [FeedItem]
}

protocol FeedRemotePostFetching {
    func fetchFeedPosts(limit: Int) async throws -> [FeedPostBundleDTO]
}

struct MockFeedRepository: FeedRepositoryProtocol {
    let items: [FeedItem]

    init(items: [FeedItem] = FeedMockData.items) {
        self.items = items
    }

    func fetchFeed(limit: Int) async throws -> [FeedItem] {
        Array(items.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }
}
