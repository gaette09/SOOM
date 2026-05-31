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

    func testFallbackFeedCanIncludeLocalShareDrafts() async throws {
        let draft = makeDraft(createdAt: Date(timeIntervalSince1970: 1_900_000_000))
        let draftStore = InMemoryFeedShareDraftStore()
        try await draftStore.saveDraft(draft)
        let dataSource = FeedDataSource(
            fallbackRepository: MockFeedRepository(items: FeedMockData.items),
            draftStore: draftStore,
            strategy: .mockOnly
        )

        let items = await dataSource.loadFeed(limit: 10)

        XCTAssertEqual(items.first?.id, draft.id)
        XCTAssertEqual(items.first?.contextLabels.first?.title, "초안")
        XCTAssertEqual(items.count, FeedMockData.items.count + 1)
    }

    func testRemoteFeedCanIncludeLocalShareDraftsWithoutRemoteWrite() async throws {
        let remoteItem = FeedMockData.items[0]
        let draft = makeDraft(createdAt: remoteItem.createdAt.addingTimeInterval(60))
        let draftStore = InMemoryFeedShareDraftStore()
        try await draftStore.saveDraft(draft)
        let dataSource = FeedDataSource(
            remoteRepository: StubFeedRepository(result: .success([remoteItem])),
            fallbackRepository: MockFeedRepository(items: []),
            draftStore: draftStore
        )

        let items = await dataSource.loadFeed(limit: 10)

        XCTAssertEqual(items.map(\.id), [draft.id, remoteItem.id])
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

private func makeDraft(createdAt: Date) -> FeedShareDraft {
    FeedShareDraft(
        id: UUID(uuidString: "29F55747-64C8-4F28-9F61-C8F88D6AD209")!,
        sourceWorkoutId: UUID(uuidString: "4F6F96BE-40D0-42D7-AEDC-4E4B064DC8E3")!,
        sport: .running,
        title: "오늘의 러닝",
        body: "가볍게 리듬을 이어간 기록.",
        distanceMeters: 5_000,
        durationSeconds: 1_700,
        averagePaceSecondsPerKm: 340,
        routePreviewPayload: FeedShareDraftRoutePreviewPayload(
            routeExists: true,
            distanceText: "5.0 km",
            fallbackStyleRawValue: StaticRouteFallbackStyle.running.rawValue
        ),
        photoPlaceholders: [],
        tags: ["러닝", "기록", "SOOM"],
        visibility: .draft,
        createdAt: createdAt
    )
}

private struct StubFeedRepository: FeedRepositoryProtocol {
    let result: Result<[FeedItem], Error>

    func fetchFeed(limit: Int) async throws -> [FeedItem] {
        try result.get()
    }
}
