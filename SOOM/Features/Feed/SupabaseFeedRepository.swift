import Foundation

final class SupabaseFeedRepository: FeedRepositoryProtocol {
    private let clientProvider: SupabaseClientProvider
    private let remoteFetcher: FeedRemotePostFetching?
    private let profileFetcher: FeedRemoteProfileFetching?

    init(
        clientProvider: SupabaseClientProvider,
        remoteFetcher: FeedRemotePostFetching? = nil,
        profileFetcher: FeedRemoteProfileFetching? = nil
    ) {
        self.clientProvider = clientProvider
        self.remoteFetcher = remoteFetcher
        self.profileFetcher = profileFetcher
    }

    func fetchFeed(limit: Int = 20) async throws -> [FeedItem] {
        guard clientProvider.state == .ready else {
            throw FeedRepositoryError.unconfigured
        }
        guard let remoteFetcher else {
            throw FeedRepositoryError.remoteFetchNotImplemented
        }

        let bundles = try await remoteFetcher.fetchFeedPosts(limit: limit)
        let profilesByID = await fetchProfilesByID(for: bundles)

        return bundles.map { bundle in
            let profile = profilesByID[bundle.post.userId]
            return bundle.makeFeedItem(
                authorName: profile?.displayName ?? "SOOM 사용자",
                authorHandle: profile?.handle
            )
        }
    }

    private func fetchProfilesByID(for bundles: [FeedPostBundleDTO]) async -> [UUID: FeedProfileDTO] {
        guard let profileFetcher else {
            return [:]
        }

        let userIDs = Array(Set(bundles.map(\.post.userId)))
        guard let profiles = try? await profileFetcher.fetchProfiles(ids: userIDs) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }
}
