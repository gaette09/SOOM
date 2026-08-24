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

        async let bundlesTask = remoteFetcher.fetchFeedPosts(limit: limit)
        let currentUserId = await currentUserId()
        let bundles = try await bundlesTask
        let profilesByID = await fetchProfilesByID(for: bundles)

        return bundles.map { bundle in
            let profile = profilesByID[bundle.post.userId]
            return bundle.makeFeedItem(
                authorName: profile?.displayName ?? "SOOM 사용자",
                authorHandle: profile?.handle,
                currentUserId: currentUserId
            )
        }
    }

    func fetchPost(id: UUID) async throws -> FeedItem? {
        guard clientProvider.state == .ready else {
            throw FeedRepositoryError.unconfigured
        }
        guard let remoteFetcher else {
            throw FeedRepositoryError.remoteFetchNotImplemented
        }

        async let bundleTask = remoteFetcher.fetchFeedPost(id: id)
        let currentUserId = await currentUserId()
        guard let bundle = try await bundleTask else {
            return nil
        }

        let profile = await fetchProfilesByID(for: [bundle])[bundle.post.userId]
        return bundle.makeFeedItem(
            authorName: profile?.displayName ?? "SOOM 사용자",
            authorHandle: profile?.handle,
            currentUserId: currentUserId
        )
    }

    private func currentUserId() async -> UUID? {
        guard let client = clientProvider.makeClient() else {
            return nil
        }
        return try? await client.auth.session.user.id
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
