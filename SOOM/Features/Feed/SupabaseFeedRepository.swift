import Foundation

final class SupabaseFeedRepository: FeedRepositoryProtocol {
    private let clientProvider: SupabaseClientProvider
    private let remoteFetcher: FeedRemotePostFetching?

    init(
        clientProvider: SupabaseClientProvider,
        remoteFetcher: FeedRemotePostFetching? = nil
    ) {
        self.clientProvider = clientProvider
        self.remoteFetcher = remoteFetcher
    }

    func fetchFeed(limit: Int = 20) async throws -> [FeedItem] {
        guard clientProvider.state == .ready else {
            throw FeedRepositoryError.unconfigured
        }
        guard let remoteFetcher else {
            throw FeedRepositoryError.remoteFetchNotImplemented
        }
        return try await remoteFetcher.fetchFeedPosts(limit: limit).map { $0.makeFeedItem() }
    }
}
