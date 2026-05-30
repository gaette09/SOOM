import XCTest
@testable import SOOM

final class FeedDataSourceTests: XCTestCase {
    func testMockOnlyStrategyReturnsMockFeed() async {
        let dataSource = FeedDataSource(strategy: .mockOnly)

        let items = await dataSource.loadFeed()

        XCTAssertEqual(items.map(\.id), FeedMockData.items.sorted { $0.createdAt > $1.createdAt }.map(\.id))
    }

    func testUnconfiguredSupabaseFallsBackToMockFeed() async {
        let remote = SupabaseFeedRepository(clientProvider: SupabaseClientProvider(configuration: .empty))
        let dataSource = FeedDataSource(remoteRepository: remote)

        let items = await dataSource.loadFeed()

        XCTAssertEqual(items.map(\.id), FeedMockData.items.sorted { $0.createdAt > $1.createdAt }.map(\.id))
    }

    func testRemoteRepositorySuccessReturnsRemoteItems() async {
        let remoteItem = FeedPostBundleDTO(
            post: FeedPostDTO(
                id: UUID(uuidString: "6E8F601E-9190-4F26-B57C-27081DC7808F")!,
                userId: UUID(uuidString: "585B05E6-EFC0-4813-B018-B2325B0BA476")!,
                sport: .running,
                title: "짧은 저녁 러닝",
                body: "가볍게 이어간 날",
                distanceMeters: 5_000,
                durationSeconds: 1_680,
                visibility: .publicPost,
                createdAt: Date(timeIntervalSince1970: 1_800_500_000)
            )
        ).makeFeedItem(authorName: "테스트")
        let dataSource = FeedDataSource(
            remoteRepository: StubFeedRepository(result: .success([remoteItem])),
            fallbackRepository: MockFeedRepository(items: FeedMockData.items)
        )

        let items = await dataSource.loadFeed()

        XCTAssertEqual(items, [remoteItem])
    }

    func testRemoteFailureFallsBackToMockFeed() async {
        let dataSource = FeedDataSource(
            remoteRepository: StubFeedRepository(result: .failure(FeedRepositoryError.remoteFailed)),
            fallbackRepository: MockFeedRepository(items: FeedMockData.items)
        )

        let items = await dataSource.loadFeed()

        XCTAssertEqual(items.map(\.id), FeedMockData.items.sorted { $0.createdAt > $1.createdAt }.map(\.id))
    }

    func testSupabaseRepositoryWithoutFetcherDoesNotCompleteRemoteFetchYet() async {
        let configuration = SupabaseAuthConfiguration(
            projectURL: URL(string: "https://example.supabase.co"),
            anonKey: "test-anon-key"
        )
        let repository = SupabaseFeedRepository(clientProvider: SupabaseClientProvider(configuration: configuration))

        do {
            _ = try await repository.fetchFeed(limit: 10)
            XCTFail("Expected remote fetch placeholder to throw")
        } catch let error as FeedRepositoryError {
            XCTAssertEqual(error, .remoteFetchNotImplemented)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct StubFeedRepository: FeedRepositoryProtocol {
    let result: Result<[FeedItem], Error>

    func fetchFeed(limit: Int) async throws -> [FeedItem] {
        try result.get()
    }
}
