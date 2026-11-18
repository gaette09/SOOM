import XCTest
import Auth
@testable import SOOM

final class FeedDataSourceTests: XCTestCase {
    func testHomeUnavailableNeverFallsBackToGlobalAndKeepsOwnerProjection() async {
        let local = FeedMockData.items[0]
        let source = FeedDataSource(ownerProjection: { remote in
            XCTAssertTrue(remote.isEmpty)
            return [local]
        })
        source.setAudience(.home)
        let result = await source.loadFeed()
        XCTAssertEqual(result.items.map(\.id), [local.id])
        XCTAssertEqual(result.failure, .contractPending)
        XCTAssertFalse(result.hasMore)
    }

    func testMockFeedPagesDoNotRepeatEarlierPosts() async {
        let source = FeedDataSource(mockRepository: MockFeedRepository(items: FeedMockData.items), strategy: .mockOnly)
        let first = await source.loadFeedPage(limit: 2, offset: 0)
        let second = await source.loadFeedPage(limit: 2, offset: 2)
        XCTAssertEqual(first.items.count, 2)
        XCTAssertEqual(second.items.count, 1)
        XCTAssertTrue(first.hasMore)
        XCTAssertFalse(second.hasMore)
        XCTAssertTrue(Set(first.items.map(\.id)).isDisjoint(with: Set(second.items.map(\.id))))
    }

    func testGuestSkipsEveryRemoteLookupAndPreservesLocalDraftsWithoutFailure() async throws {
        let remote = CountingGuestFeedRepository()
        let drafts = InMemoryFeedShareDraftStore()
        let draft = makeDraft(createdAt: Date(timeIntervalSince1970: 1_900_000_000))
        try await drafts.saveDraft(draft)
        let source = FeedDataSource(remoteRepository: remote,
            mockRepository: MockFeedRepository(items: FeedMockData.items),
            draftStore: drafts, strategy: .localDraftsOnly)
        let result = await source.loadFeed()
        let post = await source.loadPost(id: UUID())
        let callCount = await remote.callCount
        XCTAssertEqual(result.items.map(\.id), [draft.id])
        XCTAssertTrue(result.items.allSatisfy(\.isLocalDraft))
        XCTAssertNil(result.failure)
        XCTAssertNil(post)
        XCTAssertEqual(callCount, 0)
        let persistedDrafts = try await drafts.fetchDrafts()
        XCTAssertEqual(persistedDrafts.map(\.id), [draft.id])
    }

    func testGuestWithoutRemoteConfigurationIsAnOrdinaryEmptyFeed() async {
        let result = await FeedDataSource(strategy: .localDraftsOnly).loadFeed()
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertNil(result.failure)
    }

    func testMissingAuthenticatedSessionRequestsSignInAndKeepsDrafts() async throws {
        let drafts = InMemoryFeedShareDraftStore()
        let draft = makeDraft(createdAt: Date(timeIntervalSince1970: 1_900_000_000))
        try await drafts.saveDraft(draft)
        let source = FeedDataSource(remoteRepository: StubFeedRepository(result: .failure(Auth.AuthError.sessionMissing)), draftStore: drafts)
        let result = await source.loadFeed()
        XCTAssertEqual(result.failure, .signInRequired)
        XCTAssertEqual(result.items.map(\.id), [draft.id])
    }

    func testExpiredOrRevokedSessionRequiresSignInWhileAuthServerFailureStillAllowsRetry() async throws {
        let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://example.invalid/auth")!, statusCode: 400, httpVersion: nil, headerFields: nil))
        for code in [Auth.ErrorCode.sessionExpired, .refreshTokenNotFound, .refreshTokenAlreadyUsed] {
            let error = Auth.AuthError.api(message: "Synthetic session failure", errorCode: code,
                underlyingData: Data(), underlyingResponse: response)
            let result = await FeedDataSource(remoteRepository: StubFeedRepository(result: .failure(error))).loadFeed()
            XCTAssertEqual(result.failure, .signInRequired)
        }
        let unavailable = Auth.AuthError.api(message: "Synthetic server failure", errorCode: .unexpectedFailure,
            underlyingData: Data(), underlyingResponse: response)
        let result = await FeedDataSource(remoteRepository: StubFeedRepository(result: .failure(unavailable))).loadFeed()
        XCTAssertEqual(result.failure, .remoteFailed)
    }

    func testMockOnlyStrategyReturnsMockFeed() async {
        let dataSource = FeedDataSource(strategy: .mockOnly)

        let result = await dataSource.loadFeed()
        let items = result.items

        XCTAssertEqual(items.map(\.id), FeedMockData.items.sorted { $0.createdAt > $1.createdAt }.map(\.id))
    }

    func testMixedSourceFeedUsesWorkoutDateBeforeImportDate() async {
        var importedLast = FeedMockData.items[0]
        var newerWorkout = FeedMockData.items[2]
        importedLast.activityDate = Date(timeIntervalSince1970: 1_000)
        newerWorkout.activityDate = Date(timeIntervalSince1970: 2_000)
        let source = FeedDataSource(mockRepository: MockFeedRepository(items: [importedLast, newerWorkout]), strategy: .mockOnly)

        let result = await source.loadFeed(limit: 2)

        XCTAssertEqual(result.items.map(\.id), [newerWorkout.id, importedLast.id])
    }

    func testSameAuthorsCrossSourceWorkoutPostsShowOneCard() async {
        let owner = UUID()
        let start = Date(timeIntervalSince1970: 1_800_500_000)
        func post(_ id: UUID, startOffset: TimeInterval, distance: Double) -> FeedItem {
            FeedPostBundleDTO(post: FeedPostDTO(
                id: id, userId: owner, sourceWorkoutId: UUID(), sport: .cycling,
                title: "자전거", distanceMeters: distance, durationSeconds: 3_600,
                routeSummary: FeedRouteSummaryDTO(startedAt: start.addingTimeInterval(startOffset)),
                visibility: .publicPost, createdAt: start.addingTimeInterval(startOffset + 3_600)
            )).makeFeedItem(authorName: "테스트")
        }
        let apple = post(UUID(), startOffset: 0, distance: 40_000)
        let google = post(UUID(), startOffset: 30, distance: 40_100)
        let separate = post(UUID(), startOffset: 7_200, distance: 40_000)
        let source = FeedDataSource(remoteRepository: StubFeedRepository(result: .success([apple, google, separate])))

        let result = await source.loadFeed(limit: 10)

        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.items.contains { $0.id == separate.id })
    }

    func testUnconfiguredSupabaseShowsUnavailableWithoutMockFeed() async {
        let remote = SupabaseFeedRepository(clientProvider: SupabaseClientProvider(configuration: .empty))
        let dataSource = FeedDataSource(remoteRepository: remote)

        let result = await dataSource.loadFeed()
        let items = result.items

        XCTAssertTrue(items.isEmpty)
        XCTAssertEqual(result.failure, .unavailable)
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
            mockRepository: MockFeedRepository(items: FeedMockData.items)
        )

        let result = await dataSource.loadFeed()
        let items = result.items

        XCTAssertEqual(items, [remoteItem])
        XCTAssertNil(result.failure)
    }

    func testFallbackFeedCanIncludeLocalShareDrafts() async throws {
        let draft = makeDraft(createdAt: Date(timeIntervalSince1970: 1_900_000_000))
        let draftStore = InMemoryFeedShareDraftStore()
        try await draftStore.saveDraft(draft)
        let dataSource = FeedDataSource(
            mockRepository: MockFeedRepository(items: FeedMockData.items),
            draftStore: draftStore,
            strategy: .mockOnly
        )

        let result = await dataSource.loadFeed(limit: 10)
        let items = result.items

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
            mockRepository: MockFeedRepository(items: []),
            draftStore: draftStore
        )

        let result = await dataSource.loadFeed(limit: 10)
        let items = result.items

        XCTAssertEqual(items.map(\.id), [draft.id, remoteItem.id])
    }

    func testRemoteFailureDoesNotSubstituteMockFeed() async {
        let dataSource = FeedDataSource(
            remoteRepository: StubFeedRepository(result: .failure(FeedRepositoryError.remoteFailed)),
            mockRepository: MockFeedRepository(items: FeedMockData.items)
        )

        let result = await dataSource.loadFeed()
        let items = result.items

        XCTAssertTrue(items.isEmpty)
        XCTAssertEqual(result.failure, .remoteFailed)
    }

    func testDefaultProductionSourceNeverShowsMockFeed() async {
        let result = await FeedDataSource().loadFeed()

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.failure, .unavailable)
    }

    func testSuccessfulEmptyFeedIsEmptyWithoutFailureOrSamplePosts() async {
        let dataSource = FeedDataSource(
            remoteRepository: StubFeedRepository(result: .success([])),
            mockRepository: MockFeedRepository(items: FeedMockData.items)
        )

        let result = await dataSource.loadFeed()

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertNil(result.failure)
    }

    func testRemoteFailureRetainsOnlyPersistedLocalDrafts() async throws {
        let draft = makeDraft(createdAt: Date(timeIntervalSince1970: 1_900_000_000))
        let draftStore = InMemoryFeedShareDraftStore()
        try await draftStore.saveDraft(draft)
        let dataSource = FeedDataSource(
            remoteRepository: StubFeedRepository(result: .failure(FeedRepositoryError.remoteFailed)),
            mockRepository: MockFeedRepository(items: FeedMockData.items),
            draftStore: draftStore
        )

        let result = await dataSource.loadFeed()
        let savedDrafts = try await draftStore.fetchDrafts()

        XCTAssertEqual(result.items.map(\.id), [draft.id])
        XCTAssertTrue(result.items.allSatisfy(\.isLocalDraft))
        XCTAssertEqual(result.failure, .remoteFailed)
        XCTAssertEqual(savedDrafts.map(\.id), [draft.id])
    }

    func testEmptyRemoteFeedStillIncludesLocalDraftsWithoutError() async throws {
        let draft = makeDraft(createdAt: Date(timeIntervalSince1970: 1_900_000_000))
        let draftStore = InMemoryFeedShareDraftStore()
        try await draftStore.saveDraft(draft)
        let dataSource = FeedDataSource(
            remoteRepository: StubFeedRepository(result: .success([])),
            draftStore: draftStore
        )

        let result = await dataSource.loadFeed()

        XCTAssertEqual(result.items.map(\.id), [draft.id])
        XCTAssertNil(result.failure)
    }

    func testFailedMockRepositoryDoesNotInventAnotherFallbackFeed() async {
        let dataSource = FeedDataSource(
            mockRepository: StubFeedRepository(result: .failure(FeedRepositoryError.remoteFailed)),
            strategy: .mockOnly
        )

        let result = await dataSource.loadFeed()

        XCTAssertTrue(result.items.isEmpty)
    }

    func testFailedProductionPostLookupNeverReturnsMatchingMockPost() async {
        let mockPost = FeedMockData.items[0]
        let dataSource = FeedDataSource(
            remoteRepository: StubFeedRepository(result: .failure(FeedRepositoryError.remoteFailed)),
            mockRepository: MockFeedRepository(items: [mockPost])
        )

        let result = await dataSource.loadPost(id: mockPost.id)

        XCTAssertNil(result)
    }

    func testMissingProductionPostNeverReturnsMatchingMockPost() async {
        let mockPost = FeedMockData.items[0]
        let dataSource = FeedDataSource(
            remoteRepository: StubFeedRepository(result: .success([])),
            mockRepository: MockFeedRepository(items: [mockPost])
        )

        let result = await dataSource.loadPost(id: mockPost.id)

        XCTAssertNil(result)
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

    func testMockRepositoryFetchSavedPostsFiltersSavedItemsAndPreservesInputOrder() async throws {
        var firstSaved = FeedMockData.items[1]
        firstSaved.viewerHasSaved = true
        let unsaved = FeedMockData.items[0]
        var secondSaved = FeedMockData.items[2]
        secondSaved.viewerHasSaved = true
        let repository = MockFeedRepository(items: [firstSaved, unsaved, secondSaved])

        let items = try await repository.fetchSavedPosts()

        XCTAssertEqual(items.map(\.id), [firstSaved.id, secondSaved.id])
        XCTAssertTrue(items.allSatisfy(\.viewerHasSaved))
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

    func fetchSavedPosts() async throws -> [FeedItem] {
        try result.get().filter(\.viewerHasSaved)
    }

    func fetchPost(id: UUID) async throws -> FeedItem? {
        try result.get().first { $0.id == id }
    }
}

private actor CountingGuestFeedRepository: FeedRepositoryProtocol {
    private(set) var callCount = 0
    func fetchFeed(limit: Int) async throws -> [FeedItem] { callCount += 1; return [] }
    func fetchSavedPosts() async throws -> [FeedItem] { callCount += 1; return [] }
    func fetchPost(id: UUID) async throws -> FeedItem? { callCount += 1; return nil }
}

@MainActor
final class MutualSocialTests: XCTestCase {
    private let viewer = UUID(uuidString: "F0000000-0000-4000-8000-000000000001")!
    private let owner = UUID(uuidString: "F0000000-0000-4000-8000-000000000002")!

    func testAccessMatrixFailsClosedAndPreservesLegacyPrivate() {
        for visibility in [FeedPostVisibility.privatePost, .followers, .mutual, .publicPost] {
            XCTAssertTrue(SocialPostPolicy.allows(visibility, owner: owner, viewer: owner, following: nil, followsViewer: nil))
            XCTAssertFalse(SocialPostPolicy.allows(visibility, owner: owner, viewer: nil, following: true, followsViewer: true))
            XCTAssertFalse(SocialPostPolicy.allows(visibility, owner: owner, viewer: viewer, following: true, followsViewer: true, blocked: true))
            for outgoing in [Bool?.none, false, true] {
                for incoming in [Bool?.none, false, true] {
                    XCTAssertEqual(SocialPostPolicy.allows(visibility, owner: owner, viewer: viewer, following: outgoing, followsViewer: incoming),
                        visibility == .publicPost || (visibility == .mutual && outgoing == true && incoming == true))
                }
            }
        }
        XCTAssertEqual(ShareableWorkoutVisibility.privateOnly.feedPostVisibility, .privatePost)
        XCTAssertEqual(ShareableWorkoutVisibility.followers.feedPostVisibility, .followers)
        XCTAssertEqual(ShareableWorkoutVisibility.mutual.feedPostVisibility, .mutual)
        XCTAssertEqual(FeedPostVisibility.mutual.shareableVisibility, .mutual)
    }

    func testButtonsUseViewerOutgoingEdgeOnAnyProfile() {
        XCTAssertEqual(person(outgoing: false, incoming: true).actionTitle(viewerID: viewer), "팔로우")
        XCTAssertEqual(person(outgoing: true, incoming: true).actionTitle(viewerID: viewer), "팔로우해제")
        XCTAssertEqual(person(outgoing: true, incoming: false).actionTitle(viewerID: viewer), "팔로우해제")
        XCTAssertEqual(person(outgoing: false, incoming: false).actionTitle(viewerID: viewer), "팔로우")
        XCTAssertNil(person().actionTitle(viewerID: nil))
        XCTAssertNil(person().actionTitle(viewerID: owner))
    }

    func testSummaryUsesServerCountsNotLoadedPageCount() async {
        let remote = SocialStub(viewerID: viewer, rows: [person()])
        remote.counts = SocialSummary(postCount: 57, followerCount: 26, followingCount: 31)
        let model = ProfileSocialModel(ownerID: owner, service: remote, safety: CommunitySafetyStore(client: nil, viewerID: viewer))
        await model.load(kind: .followers)
        XCTAssertEqual(model.summary, remote.counts)
        XCTAssertEqual(model.people.count, 1)
        XCTAssertFalse(model.hasMore)
        XCTAssertNil(model.errorMessage)
    }

    func testReadFailureDoesNotInventCountsOrPeople() async {
        let remote = SocialStub(viewerID: viewer, rows: [person()]); remote.fails = true
        let model = ProfileSocialModel(ownerID: owner, service: remote, safety: CommunitySafetyStore(client: nil, viewerID: viewer))
        await model.load(kind: .followers)
        XCTAssertNil(model.summary); XCTAssertTrue(model.people.isEmpty); XCTAssertFalse(model.hasMore)
        XCTAssertNotNil(model.errorMessage); XCTAssertFalse(model.isLoading)
    }

    func testLogoutDuringReadRejectsLateSnapshot() async {
        let remote = SocialStub(viewerID: viewer, rows: [person()]); let gate = SocialGate(); remote.gate = gate
        let safety = CommunitySafetyStore(client: nil, viewerID: viewer)
        let model = ProfileSocialModel(ownerID: owner, service: remote, safety: safety)
        let task = Task { await model.load(kind: .followers) }
        while !gate.started { await Task.yield() }
        safety.setViewerID(nil); gate.open(); await task.value
        XCTAssertNil(model.summary); XCTAssertTrue(model.people.isEmpty); XCTAssertFalse(model.isLoading)
    }

    func testRelationshipChangeRejectsInFlightCountsAndPeople() async {
        let remote = SocialStub(viewerID: viewer, rows: [person()]); let gate = SocialGate(); remote.gate = gate
        let safety = CommunitySafetyStore(client: nil, viewerID: viewer)
        let model = ProfileSocialModel(ownerID: owner, service: remote, safety: safety)
        let task = Task { await model.load(kind: .followers) }
        while !gate.started { await Task.yield() }
        safety.invalidateRelationships(); gate.open(); await task.value
        XCTAssertNil(model.summary); XCTAssertTrue(model.people.isEmpty)
    }

    func testUnfollowPreservesIncomingEdgeAndFailureRestoresConfirmedState() async {
        let remote = SocialStub(viewerID: viewer, rows: [person(outgoing: true, incoming: true)])
        let model = ProfileSocialModel(ownerID: owner, service: remote, safety: CommunitySafetyStore(client: nil, viewerID: viewer))
        await model.load(kind: .followers); await model.toggle(model.people[0])
        XCTAssertEqual(remote.mutations, [false]); XCTAssertFalse(model.people[0].isFollowing)
        XCTAssertTrue(model.people[0].followsViewer)
        remote.mutationFails = true
        await model.toggle(model.people[0])
        XCTAssertFalse(model.people[0].isFollowing); XCTAssertTrue(model.people[0].followsViewer)
        XCTAssertNotNil(model.errorMessage)
    }

    func testDuplicateTapExecutesOneOutgoingMutation() async {
        let remote = SocialStub(viewerID: viewer, rows: [person()]); let gate = SocialGate(); remote.mutationGate = gate
        let model = ProfileSocialModel(ownerID: owner, service: remote, safety: CommunitySafetyStore(client: nil, viewerID: viewer))
        await model.load(kind: .followers); let target = model.people[0]
        let first = Task { await model.toggle(target) }
        while !gate.started { await Task.yield() }
        await model.toggle(target); XCTAssertEqual(remote.mutations.count, 1)
        gate.open(); await first.value
        XCTAssertTrue(model.people[0].isFollowing); XCTAssertTrue(model.busyIDs.isEmpty)
    }

    func testSocialPaginationUsesRawLastRowAndRemovesRepeatedIDs() async {
        let rows = (0..<20).map { index in
            SocialPerson(id: UUID(uuidString: String(format: "F0000000-0000-4000-8000-%012d", index+10))!,
                displayName: "합성 \(index)", handle: nil, avatarPath: nil,
                followedAt: Date(timeIntervalSince1970: 100), isFollowing: false, followsViewer: true)
        }
        let remote = SocialStub(viewerID: viewer, rows: rows)
        let model = ProfileSocialModel(ownerID: owner, service: remote, safety: CommunitySafetyStore(client: nil, viewerID: viewer))
        await model.load(kind: .followers); XCTAssertTrue(model.hasMore)
        remote.rows = [rows.last!, person()]
        await model.load(kind: .followers, reset: false)
        XCTAssertEqual(remote.lastCursor, rows.last?.id)
        XCTAssertEqual(model.people.count, 21); XCTAssertFalse(model.hasMore)
    }

    func testKeysetCursorRejectsAccountRevisionAndLateReset() async throws {
        let pages = FeedKeysetPages()
        let first = try await pages.begin(scope: "following", authorID: nil, offset: 0, viewer: viewer, revision: 1)
        let post = FeedPostDTO(id: owner, userId: owner, sport: .running, title: "합성", createdAt: Date(timeIntervalSince1970: 100))
        try await pages.finish(token: first, rows: [post], offset: 0)
        let second = try await pages.begin(scope: "following", authorID: nil, offset: 1, viewer: viewer, revision: 1)
        XCTAssertEqual(second.postID, owner); XCTAssertEqual(second.date, post.createdAt)
        do { _ = try await pages.begin(scope: "following", authorID: nil, offset: 1, viewer: viewer, revision: 2); XCTFail("stale relation") } catch {}
        do { _ = try await pages.begin(scope: "following", authorID: nil, offset: 1, viewer: owner, revision: 1); XCTFail("wrong account") } catch {}
        _ = try await pages.begin(scope: "following", authorID: nil, offset: 0, viewer: viewer, revision: 2)
        do { try await pages.finish(token: second, rows: [post], offset: 1); XCTFail("late page") } catch {}
    }

    func testUnavailableFollowingDoesNotFallBackToAllFeedOrLocalDrafts() async {
        let source = FeedDataSource(remoteRepository: MockFeedRepository(items: FeedMockData.items))
        source.setAudience(.following)
        let result = await source.loadFeedPage(limit: 8, offset: 0)
        XCTAssertTrue(result.items.isEmpty); XCTAssertNotNil(result.failure)
        let guest = FeedDataSource(strategy: .localDraftsOnly); guest.setAudience(.following)
        let guestResult = await guest.loadFeedPage(limit: 8, offset: 0)
        XCTAssertEqual(guestResult.failure, .signInRequired)
    }

    private func person(outgoing: Bool = false, incoming: Bool = true) -> SocialPerson {
        SocialPerson(id: owner, displayName: "합성", handle: nil, avatarPath: nil,
                     followedAt: Date(timeIntervalSince1970: 100), isFollowing: outgoing, followsViewer: incoming)
    }
}

@MainActor
private final class SocialStub: ProfileSocialServing {
    var viewerID: UUID?
    var rows: [SocialPerson]
    var counts = SocialSummary(postCount: 7, followerCount: 2, followingCount: 3)
    var fails = false
    var mutationFails = false
    var mutations: [Bool] = []
    var lastCursor: UUID?
    var gate: SocialGate?
    var mutationGate: SocialGate?
    init(viewerID: UUID?, rows: [SocialPerson]) { self.viewerID = viewerID; self.rows = rows }
    func summary(ownerID: UUID) async throws -> SocialSummary {
        if let gate { await gate.wait() }
        if fails { throw CommunitySafetyError.unavailable }
        return counts
    }
    func people(ownerID: UUID, kind: SocialPeopleKind, after: SocialPerson?, limit: Int) async throws -> [SocialPerson] {
        lastCursor = after?.id; return rows
    }
    func setFollowing(_ enabled: Bool, userID: UUID) async throws -> Bool {
        mutations.append(enabled)
        if let mutationGate { await mutationGate.wait() }
        if mutationFails { throw CommunitySafetyError.unavailable }
        for index in rows.indices where rows[index].id == userID { rows[index].isFollowing = enabled }
        return enabled
    }
}

@MainActor
private final class SocialGate {
    private var continuation: CheckedContinuation<Void,Never>?
    private(set) var started = false
    func wait() async { started = true; await withCheckedContinuation { continuation = $0 } }
    func open() { continuation?.resume(); continuation = nil }
}

import Supabase
import XCTest
@testable import SOOM

@MainActor
final class ProfileFollowParityTests: XCTestCase {
    private let viewer = UUID(uuidString: "FA150000-0000-4000-8000-000000000001")!
    private let target = UUID(uuidString: "FA150000-0000-4000-8000-000000000002")!
    private let listOwner = UUID(uuidString: "FA150000-0000-4000-8000-000000000003")!

    private func sdk(_ scope: String, state: ApprovedFollowState) async throws -> SupabaseClient {
        FollowParityHTTP.configure(scope: scope, state: state)
        let now = Date(), user = User(id: viewer, appMetadata: [:], userMetadata: [:], aud: "authenticated", createdAt: Date(), updatedAt: Date())
        let cached = Session(accessToken: "synthetic-noncredential", tokenType: "bearer", expiresIn: 3600,
            expiresAt: now.timeIntervalSince1970 + 3600, refreshToken: "synthetic-noncredential", user: user)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FollowParityHTTP.self]
        let client = SupabaseClient(supabaseURL: URL(string: "https://follow-parity.invalid")!, supabaseKey: "synthetic-noncredential",
            options: SupabaseClientOptions(auth: .init(storage: FollowParityMemoryStorage(data: try JSONEncoder().encode(cached)),
                storageKey: "follow-parity", autoRefreshToken: false, emitLocalSessionAsInitialSession: true),
                global: .init(headers: ["x-soom-feed-contract":"mutual-v1", "x-soom-social-contract":"approved-v1", "x-soom-workout-contract":"detail-v1"],
                    session: URLSession(configuration: config))))
        _ = try await SupabaseClientSessionReader(client: client, includesProfile: false).readCurrentSession()
        return client
    }
    private func withSharedViewer(_ operation: () async throws -> Void) async rethrows {
        let old = CommunitySafetyStore.shared.viewerID, verified = CommunitySafetyStore.shared.socialVerified
        CommunitySafetyStore.shared.setViewerID(viewer); CommunitySafetyStore.shared.setSocialVerified(true, owner: viewer)
        defer { CommunitySafetyStore.shared.setViewerID(old); if let old { CommunitySafetyStore.shared.setSocialVerified(verified, owner: old) } }
        try await operation()
    }
    func testV2ActualSDKPrivateFollowIsDirectAndPreservesOldPending() async throws {
        guard ProfileOnlyPrivacyReleaseGate.productionReady else { throw XCTSkip("Requires v2 release-mode factory") }
        let client = try await sdk("private", state: .pending)
        try await withSharedViewer {
            let service = SupabaseProfileSocialService(client: client, readPolicy: .profileOnlyV2)
            let followed = try await service.setFollowing(true, userID: target)
            XCTAssertTrue(followed); XCTAssertTrue(FollowParityHTTP.edge)
            XCTAssertEqual(FollowParityHTTP.state, .pending, "Historical request must not be accepted as a side effect")
            let rows = try await service.people(ownerID: listOwner, kind: .followers, after: nil, limit: 20)
            XCTAssertEqual(rows.first?.readPolicy, .profileOnlyV2)
            XCTAssertEqual(rows.first?.relationshipTitle, "팔로잉")
            let removed = try await service.setFollowing(false, userID: target)
            XCTAssertFalse(removed); XCTAssertFalse(FollowParityHTTP.edge)
            XCTAssertEqual(FollowParityHTTP.edgeRevision, 2)
            XCTAssertEqual(FollowParityHTTP.state, .pending)
        }
    }
    func testV2ActualSDKPublicFollowAndViewerRelativeListUseDirectEdges() async throws {
        guard ProfileOnlyPrivacyReleaseGate.productionReady else { throw XCTSkip("Requires v2 release-mode factory") }
        let client = try await sdk("public", state: .none)
        try await withSharedViewer {
            let service = SupabaseProfileSocialService(client: client, readPolicy: .profileOnlyV2)
            let initial = try await service.people(ownerID: listOwner, kind: .following, after: nil, limit: 20)
            XCTAssertEqual(initial.first?.isFollowing, false)
            XCTAssertEqual(initial.first?.relationshipTitle, "팔로우")
            let result = try await service.setFollowing(true, userID: target)
            XCTAssertTrue(result)
            let summary = try await service.summary(ownerID: target)
            XCTAssertEqual(summary.postCount, 1)
        }
    }
    func testV2PrivatePersonUsesFollowNotApprovalAndMutualRequiresBothEdges() {
        var person = SocialPerson(id: target, displayName: "Synthetic", handle: nil, avatarPath: nil,
            followedAt: Date(), isFollowing: false, followsViewer: true, approvedState: .pending, approvedAccountScope: "private")
        person.readPolicy = .profileOnlyV2
        XCTAssertEqual(person.relationshipTitle, "팔로우")
        XCTAssertEqual(person.actionTitle(viewerID: viewer), "팔로우")
        XCTAssertFalse(SocialPostPolicy.allows(.mutual, owner: target, viewer: viewer, following: false, followsViewer: true))
        person.isFollowing = true
        XCTAssertEqual(person.relationshipTitle, "팔로잉")
        XCTAssertTrue(SocialPostPolicy.allows(.mutual, owner: target, viewer: viewer, following: true, followsViewer: true))
        XCTAssertFalse(SocialPostPolicy.allows(.mutual, owner: target, viewer: viewer, following: true, followsViewer: false))
    }
    func testActualSDKPublicFollowThenUnfollowReturnsResultingIntent() async throws {
        let client = try await sdk("public", state: .none)
        try await withSharedViewer {
            let service = SupabaseProfileSocialService(client: client, readPolicy: .approvedFollowersV1)
            let followed = try await service.setFollowing(true, userID: target)
            XCTAssertTrue(followed); XCTAssertEqual(FollowParityHTTP.state, .accepted)
            let removed = try await service.setFollowing(false, userID: target)
            XCTAssertFalse(removed, "Successful removal returns false, not a true success marker")
            XCTAssertEqual(FollowParityHTTP.state, .none)
            XCTAssertEqual(FollowParityHTTP.mutations, [true,false])
        }
    }
    func testActualSDKPrivatePendingCancellationDoesNotBecomeFollowingOrFailure() async throws {
        let client = try await sdk("private", state: .none)
        try await withSharedViewer {
            let service = SupabaseProfileSocialService(client: client, readPolicy: .approvedFollowersV1)
            let requested = try await service.setFollowing(true, userID: target)
            XCTAssertTrue(requested); XCTAssertEqual(FollowParityHTTP.state, .pending)
            let rows = try await service.people(ownerID: listOwner, kind: .followers, after: nil, limit: 20)
            XCTAssertEqual(rows.first?.approvedState, .pending); XCTAssertEqual(rows.first?.isFollowing, false)
            let cancelled = try await service.setFollowing(false, userID: target)
            XCTAssertFalse(cancelled); XCTAssertEqual(FollowParityHTTP.state, .none)
        }
    }
    func testListRowsUseViewerToPersonInsteadOfViewedProfileRelation() async throws {
        let client = try await sdk("public", state: .none)
        try await withSharedViewer {
            let rows = try await SupabaseProfileSocialService(client: client, readPolicy: .approvedFollowersV1).people(ownerID: listOwner, kind: .following, after: nil, limit: 20)
            XCTAssertEqual(rows.first?.id, target)
            XCTAssertEqual(rows.first?.isFollowing, false, "Raw row reports true but fresh viewer approval state is none")
            XCTAssertEqual(rows.first?.relationshipTitle, "팔로우")
        }
    }
    func testAuthorizedListSearchFindsHandlePastFirstPageWithoutChangingServerCounts() async {
        let remote = ParityPeopleService(viewer: viewer)
        let safety = CommunitySafetyStore(client: nil, viewerID: viewer)
        let model = ProfileSocialModel(ownerID: listOwner, service: remote, safety: safety)
        await model.load(kind: .followers, query: "@later_USER")
        XCTAssertEqual(model.people.map(\.id), [remote.rows[29].id]); XCTAssertEqual(remote.pageReads, 2)
        XCTAssertEqual(model.summary?.followerCount, 35); XCTAssertFalse(model.hasMore)
        await model.load(kind: .followers, query: "")
        XCTAssertEqual(model.people.count, 20); XCTAssertTrue(model.hasMore)
    }
    func testChangingSearchRejectsDelayedEarlierListSnapshot() async {
        let remote = ParityPeopleService(viewer: viewer); remote.holdFirstSummary = true
        let model = ProfileSocialModel(ownerID: listOwner, service: remote, safety: CommunitySafetyStore(client: nil, viewerID: viewer))
        let old = Task { await model.load(kind: .followers, query: "old") }
        for _ in 0..<100 where remote.continuation == nil { await Task.yield() }
        await model.load(kind: .followers, query: "later_user")
        remote.continuation?.resume(); await old.value
        XCTAssertEqual(model.people.map(\.id), [remote.rows[29].id]); XCTAssertFalse(model.isLoading)
    }
    func testUnverifiedViewerCannotLoadCountsOrSearchProtectedList() async {
        let remote = ParityPeopleService(viewer: viewer)
        let safety = CommunitySafetyStore(client: nil, requiresSocialVerification: true); safety.setViewerID(viewer)
        let model = ProfileSocialModel(ownerID: listOwner, service: remote, safety: safety)
        await model.load(kind: .followers, query: "later_user")
        XCTAssertEqual(remote.pageReads, 0); XCTAssertEqual(remote.summaryReads, 0); XCTAssertTrue(model.people.isEmpty)
    }
    func testIncomingIdentitySearchAndStateDoNotRepresentOutgoingFollowing() {
        let request = IncomingFollowRequest(userID: target, requestID: UUID(), displayName: "Runner Name", handle: "runner_id", avatarPath: "synthetic.jpg", state: .accepted, createdAt: Date())
        XCTAssertTrue(request.matches(search: "@RUNNER_id")); XCTAssertTrue(request.matches(search: "runner name"))
        XCTAssertFalse(request.matches(search: "another")); XCTAssertEqual(request.profile.id, target)
        let outgoing = SocialPerson(id: target, displayName: "Runner Name", handle: "runner_id", avatarPath: nil,
            followedAt: Date(), isFollowing: false, followsViewer: true, approvedState: .none, approvedAccountScope: "private")
        XCTAssertEqual(outgoing.relationshipTitle, "팔로우 요청", "Accepted inbound does not follow back or grant mutual requirement")
    }
}

@MainActor
private final class ParityPeopleService: ProfileSocialServing {
    var viewerID: UUID?
    let rows: [SocialPerson]
    var pageReads = 0, summaryReads = 0
    var holdFirstSummary = false
    var continuation: CheckedContinuation<Void,Never>?
    init(viewer: UUID) {
        viewerID = viewer
        var generated: [SocialPerson] = []
        for index in 0..<35 {
            let identifier = UUID(uuidString: String(format: "FA150000-0000-4000-8001-%012d", index + 1))!
            let name = "Synthetic Person \(index)"
            let handle: String = index == 29 ? "later_user" : "user_\(index)"
            let date = Date(timeIntervalSince1970: Double(1000 - index))
            generated.append(SocialPerson(id: identifier, displayName: name, handle: handle, avatarPath: nil,
                followedAt: date, isFollowing: false, followsViewer: true))
        }
        rows = generated
    }
    func summary(ownerID: UUID) async throws -> SocialSummary {
        summaryReads += 1
        if holdFirstSummary && summaryReads == 1 { await withCheckedContinuation { continuation = $0 } }
        return .init(postCount: 8, followerCount: 35, followingCount: 9)
    }
    func people(ownerID: UUID, kind: SocialPeopleKind, after: SocialPerson?, limit: Int) async throws -> [SocialPerson] {
        pageReads += 1; let start = after.flatMap { value in rows.firstIndex { $0.id == value.id } }.map { $0+1 } ?? 0
        return Array(rows.dropFirst(start).prefix(limit))
    }
    func setFollowing(_ enabled: Bool, userID: UUID) async throws -> Bool { enabled }
}
private final class FollowParityMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock(); private var data: Data?
    init(data: Data?) { self.data = data }
    func store(key: String,value: Data) throws { lock.lock(); defer { lock.unlock() }; if key == "follow-parity" { data = value } }
    func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return key == "follow-parity" ? data : nil }
    func remove(key: String) throws { lock.lock(); defer { lock.unlock() }; if key == "follow-parity" { data = nil } }
}
private final class FollowParityHTTP: URLProtocol {
    static let lock = NSLock()
    static var scope = "public"
    static var state: ApprovedFollowState = .none
    static var mutations: [Bool] = []
    static var edge = false
    static var edgeRevision = 0
    static let target = "fa150000-0000-4000-8000-000000000002"
    static func configure(scope: String,state: ApprovedFollowState) { lock.lock(); defer { lock.unlock() }; self.scope = scope; self.state = state; mutations = []; edge = false; edgeRevision = 0 }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "follow-parity.invalid",request.value(forHTTPHeaderField:"x-soom-social-contract") == "approved-v1" else {
            client?.urlProtocol(self,didFailWithError:URLError(.unsupportedURL));return
        }
        Self.lock.lock()
        let body: String
        switch request.url?.lastPathComponent {
        case "soom_profile_privacy_candidate_v2":
            body = "{\"version\":2,\"owner_id\":\"fa150000-0000-4000-8000-000000000001\",\"enabled\":true,\"account_scope\":\"public\",\"revision\":1,\"share_measurements\":false,\"release_ready\":true}"
        case "soom_follow_state_candidate_v2": body = v2Receipt()
        case "soom_request_follow_candidate_v2":
            var bytes = request.httpBody ?? Data()
            if bytes.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; bytes.append(buffer, count: n) }
            }
            let params = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
            guard let following = params?["p_following"] as? Bool, params?["p_expected_revision"] as? Int == Self.edgeRevision else {
                Self.lock.unlock(); client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse)); return
            }
            if Self.edge != following { Self.edge = following; Self.edgeRevision += 1 }
            body = v2Receipt()
        case "soom_social_people_candidate_v2":
            body = v2Envelope("[{\"id\":\"\(Self.target)\",\"display_name\":\"Synthetic row\",\"handle\":null,\"avatar_path\":null,\"followed_at\":\"2026-10-13T00:00:00Z\",\"is_following\":\(Self.edge),\"follows_viewer\":false}]")
        case "soom_social_summary_candidate_v2": body = v2Envelope("[{\"post_count\":1,\"follower_count\":1,\"following_count\":0}]")
        case "soom_privacy_v1": body = #"[{"enabled":true,"account_scope":"public","workout_default":"public","revision":1,"share_measurements":true}]"#
        case "soom_shared_detail_enabled_v1", "soom_full_detail_consent_ready_v1": body = "true"
        case "soom_follow_state_v1": body = receipt()
        case "soom_social_people": body = "[{\"id\":\"\(Self.target)\",\"display_name\":\"Synthetic row\",\"handle\":\"synthetic\",\"avatar_path\":null,\"followed_at\":\"2026-10-13T00:00:00Z\",\"is_following\":true,\"follows_viewer\":false}]"
        case "soom_request_follow_v1":
            var bytes = request.httpBody ?? Data()
            if bytes.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating:0,count:1024)
                while stream.hasBytesAvailable { let n=stream.read(&buffer,maxLength:buffer.count); if n<=0 { break }; bytes.append(buffer,count:n) }
            }
            let params = (try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any]
            guard let following = params?["p_following"] as? Bool else { Self.lock.unlock();client?.urlProtocol(self,didFailWithError:URLError(.cannotParseResponse));return }
            Self.mutations.append(following); Self.state = following ? (Self.scope == "private" ? .pending : .accepted) : .none
            body = receipt()
        default: Self.lock.unlock(); client?.urlProtocol(self,didFailWithError:URLError(.unsupportedURL));return
        }
        Self.lock.unlock()
        let response = HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:Data(body.utf8));client?.urlProtocolDidFinishLoading(self)
    }
    private func v2Envelope(_ rows: String) -> String {
        "{\"version\":2,\"viewer_id\":\"fa150000-0000-4000-8000-000000000001\",\"rows\":\(rows),\"release_ready\":true}"
    }
    private func v2Receipt() -> String {
        v2Envelope("[{\"user_id\":\"\(Self.target)\",\"state\":\"\(Self.edge ? "accepted" : "none")\",\"request_id\":null,\"account_scope\":\"\(Self.scope)\",\"follows_viewer\":false,\"legacy_pending\":\(Self.state == .pending),\"revision\":\(Self.edgeRevision)}]")
    }
    private func receipt() -> String {
        let requestID = Self.state == .none ? "null" : "\"fa150000-0000-4000-8000-000000000099\""
        return "[{\"user_id\":\"\(Self.target)\",\"state\":\"\(Self.state.rawValue)\",\"request_id\":\(requestID),\"account_scope\":\"\(Self.scope)\"}]"
    }
    override func stopLoading() {}
}

@MainActor
final class ProfileSearchUXRegressionTests: XCTestCase {
    private func person(_ number: Int) -> ProfileSearchPerson {
        ProfileSearchPerson(id: UUID(uuidString: String(format: "c0170000-0000-4000-8000-%012d", number))!,
            displayName: "Synthetic \(number)", handle: "synthetic_\(number)", avatarPath: nil)
    }
    private func makeModel(_ service: SearchUXTestService, safety: CommunitySafetyStore? = nil) -> ProfileSearchModel {
        ProfileSearchModel(service: service, safety: safety ?? CommunitySafetyStore(client: nil, viewerID: service.viewerID))
    }

    func testDebounceIsWaitingAndNeverACompletedEmptyResult() async {
        let service = SearchUXTestService(); service.firstPages["query"] = []
        let model = makeModel(service)
        XCTAssertTrue(model.prepareSearch(query: " query "))
        XCTAssertTrue(model.isSearching)
        XCTAssertTrue(model.isWaiting)
        XCTAssertNil(model.completedQuery)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(service.calls.count, 0)
        await model.load(query: "query")
        XCTAssertFalse(model.isSearching)
        XCTAssertEqual(model.completedQuery, "query")
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.error)
    }

    func testFirstPageFailureIsNotAnEmptySuccessAndCanRetry() async {
        let service = SearchUXTestService(); service.failure = CommunitySafetyError.unavailable
        let model = makeModel(service)
        await model.load(query: "query")
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.completedQuery)
        XCTAssertFalse(model.isSearching)
        service.failure = nil; service.firstPages["query"] = [person(1)]
        await model.load(query: "query")
        XCTAssertEqual(model.rows.map(\.id), [person(1).id])
        XCTAssertNil(model.error)
    }

    func testPageFailureRetainsResultsAndCursorThenRetryDeduplicates() async {
        let service = SearchUXTestService(); service.firstPages["query"] = (1...20).map(person)
        service.nextPage = [person(20), person(21)]
        let model = makeModel(service)
        await model.load(query: "query")
        XCTAssertTrue(model.hasMore)
        service.failure = CommunitySafetyError.unavailable
        await model.load(query: "query", reset: false)
        XCTAssertEqual(model.rows.map(\.id), (1...20).map { person($0).id })
        XCTAssertNotNil(model.pageError)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.hasMore)
        service.failure = nil
        await model.load(query: "query", reset: false)
        XCTAssertEqual(service.calls.map(\.after), [nil, person(20).id, person(20).id])
        XCTAssertEqual(model.rows.map(\.id), (1...21).map { person($0).id })
        XCTAssertNil(model.pageError)
        XCTAssertFalse(model.hasMore)
    }

    func testOldQueryResponseCannotOverwriteNewQuery() async {
        let service = SearchUXTestService(); service.firstPages["old"] = [person(1)]; service.firstPages["new"] = [person(2)]
        let started = expectation(description: "old search")
        var resume: CheckedContinuation<Void, Never>?
        service.beforeResponse = { query, _ in if query == "old" { await withCheckedContinuation { resume = $0; started.fulfill() } } }
        let model = makeModel(service)
        let old = Task { await model.load(query: "old") }
        await fulfillment(of: [started], timeout: 2)
        await model.load(query: "new")
        resume?.resume(); await old.value
        XCTAssertEqual(model.rows.map(\.id), [person(2).id])
        XCTAssertEqual(model.completedQuery, "new")
        XCTAssertNil(model.error)
    }

    func testOldQueryErrorCannotEraseNewQueryResults() async {
        let service = SearchUXTestService(); service.failure = CommunitySafetyError.unavailable; service.firstPages["new"] = [person(2)]
        let started = expectation(description: "old error")
        var resume: CheckedContinuation<Void, Never>?
        service.beforeResponse = { query, _ in if query == "old" { await withCheckedContinuation { resume = $0; started.fulfill() } } }
        let model = makeModel(service)
        let old = Task { await model.load(query: "old") }
        await fulfillment(of: [started], timeout: 2)
        service.failure = nil; await model.load(query: "new")
        resume?.resume(); await old.value
        XCTAssertEqual(model.rows.map(\.id), [person(2).id])
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isSearching)
    }

    func testAccountChangeDuringPageDropsPreviousAccountResults() async {
        let service = SearchUXTestService(); service.firstPages["query"] = (1...20).map(person)
        let safety = CommunitySafetyStore(client: nil, viewerID: service.viewerID)
        let model = makeModel(service, safety: safety)
        await model.load(query: "query")
        let started = expectation(description: "old account page")
        var resume: CheckedContinuation<Void, Never>?
        service.beforeResponse = { _, _ in await withCheckedContinuation { resume = $0; started.fulfill() } }
        let page = Task { await model.load(query: "query", reset: false) }
        await fulfillment(of: [started], timeout: 2)
        let newOwner = UUID(); safety.setViewerID(newOwner); service.viewerID = newOwner
        resume?.resume(); await page.value
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertFalse(model.hasMore)
        XCTAssertNil(model.completedQuery)
    }

    func testRelationshipRevisionDuringPageDropsStaleResults() async {
        let service = SearchUXTestService(); service.firstPages["query"] = (1...20).map(person)
        let safety = CommunitySafetyStore(client: nil, viewerID: service.viewerID)
        let model = makeModel(service, safety: safety)
        await model.load(query: "query")
        let started = expectation(description: "page before revocation")
        var resume: CheckedContinuation<Void, Never>?
        service.beforeResponse = { _, _ in await withCheckedContinuation { resume = $0; started.fulfill() } }
        let page = Task { await model.load(query: "query", reset: false) }
        await fulfillment(of: [started], timeout: 2)
        safety.invalidateRelationships()
        resume?.resume(); await page.value
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertFalse(model.hasMore)
        XCTAssertNil(model.pageError)
    }

    func testUnverifiedSocialSessionNeverStartsSearch() async {
        let service = SearchUXTestService()
        let safety = CommunitySafetyStore(client: nil, viewerID: service.viewerID, requiresSocialVerification: true)
        let model = makeModel(service, safety: safety)
        XCTAssertFalse(model.prepareSearch(query: "query"))
        await model.load(query: "query")
        XCTAssertEqual(service.calls.count, 0)
        XCTAssertFalse(model.isSearching)
        XCTAssertNil(model.completedQuery)
    }

    func testPolicyRejectionDuringPageDoesNotPreservePreviousResults() async {
        let service = SearchUXTestService(); service.firstPages["query"] = (1...20).map(person)
        let model = makeModel(service)
        await model.load(query: "query")
        service.failure = CommunitySafetyError.socialUnverified
        await model.load(query: "query", reset: false)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertFalse(model.hasMore)
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.pageError)
    }

    func testDuplicatePageTapDoesNotSendConcurrentPageRead() async {
        let service = SearchUXTestService(); service.firstPages["query"] = (1...20).map(person)
        let model = makeModel(service)
        await model.load(query: "query")
        let started = expectation(description: "page read")
        var resume: CheckedContinuation<Void, Never>?
        service.beforeResponse = { _, _ in await withCheckedContinuation { resume = $0; started.fulfill() } }
        let page = Task { await model.load(query: "query", reset: false) }
        await fulfillment(of: [started], timeout: 2)
        await model.load(query: "query", reset: false)
        XCTAssertEqual(service.calls.count, 2)
        XCTAssertEqual(model.rows.count, 20)
        resume?.resume(); await page.value
        XCTAssertFalse(model.isSearching)
    }

    func testCancelledOldLoadCannotClearCurrentResultsOrStartRequest() async {
        let service = SearchUXTestService(); service.firstPages["new"] = [person(2)]
        let model = makeModel(service)
        await model.load(query: "new")
        let old = Task { await Task.yield(); await model.load(query: "old") }
        old.cancel(); await old.value
        XCTAssertEqual(service.calls.count, 1)
        XCTAssertEqual(model.rows.map(\.id), [person(2).id])
        XCTAssertEqual(model.completedQuery, "new")
    }

    func testBlankAndOverlongQueriesNeverHitServerOrShowStaleEmptyResult() async {
        let service = SearchUXTestService(); service.firstPages["query"] = [person(1)]
        let model = makeModel(service)
        await model.load(query: "query")
        await model.load(query: "  ")
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.completedQuery)
        await model.load(query: String(repeating: "q", count: 81))
        XCTAssertNotNil(model.error)
        XCTAssertEqual(service.calls.count, 1)
        XCTAssertFalse(model.isSearching)
    }
}

@MainActor
private final class SearchUXTestService: ProfileSearchServing {
    var viewerID: UUID? = UUID(uuidString: "c0170000-0000-4000-8000-999999999999")!
    struct Call { let query: String; let after: UUID? }
    var calls: [Call] = []
    var firstPages: [String: [ProfileSearchPerson]] = [:]
    var nextPage: [ProfileSearchPerson] = []
    var failure: Error?
    var beforeResponse: ((String, UUID?) async -> Void)?
    func search(query: String, after: ProfileSearchPerson?, limit: Int) async throws -> [ProfileSearchPerson] {
        calls.append(Call(query: query, after: after?.id))
        let error = failure
        let values = after == nil ? firstPages[query, default: []] : nextPage
        await beforeResponse?(query, after?.id)
        if let error { throw error }
        return values
    }
}

@MainActor
final class LegacyFollowersRLSHTTPTests: XCTestCase {
    private let viewer = UUID(uuidString: "F0180000-0000-4000-8000-000000000001")!
    private func run(_ mode: String) async throws -> [FeedItem] {
        LegacyFollowersHTTP.reset(mode)
        let user = User(id: viewer, appMetadata: [:], userMetadata: [:], aud: "authenticated", createdAt: Date(), updatedAt: Date())
        let cached = Session(accessToken: "synthetic-noncredential", tokenType: "bearer", expiresIn: 3600, expiresAt: Date().timeIntervalSince1970 + 3600, refreshToken: "synthetic-noncredential", user: user)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [LegacyFollowersHTTP.self]
        let client = SupabaseClient(supabaseURL: URL(string: "https://followers-rls.invalid")!, supabaseKey: "synthetic-noncredential", options: .init(
            auth: .init(storage: FollowParityMemoryStorage(data: try JSONEncoder().encode(cached)), storageKey: "follow-parity", autoRefreshToken: false, emitLocalSessionAsInitialSession: true),
            global: .init(headers: ["x-soom-social-contract":"approved-v1", "x-soom-workout-contract":"detail-v1"], session: URLSession(configuration: config))))
        _ = try await SupabaseClientSessionReader(client: client, includesProfile: false).readCurrentSession()
        let safety = CommunitySafetyStore.shared, previous = safety.viewerID, verified = safety.socialVerified
        safety.configure(client: nil); safety.setViewerID(viewer); safety.setSocialVerified(true, owner: viewer)
        defer { safety.setViewerID(previous); if let previous { safety.setSocialVerified(verified, owner: previous) } }
        return try await SupabaseFeedRemoteClient(client: client).previewLegacyHome(.init(viewerID: viewer, scope: .home, ownerID: nil, before: nil, limit: 8))
    }
    func testActualSDKQueriesFollowersAndDisplaysRLSAuthorizedRow() async throws {
        let rows = try await run("allowed")
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.visibility, .followers)
        XCTAssertNotNil(rows.first?.previewLegacyReadContext)
        XCTAssertTrue(LegacyFollowersHTTP.queries.contains { $0.contains("visibility.eq.followers") })
        XCTAssertFalse(LegacyFollowersHTTP.paths.contains { $0.contains("shared_detail") })
        XCTAssertTrue(LegacyFollowersHTTP.methods.allSatisfy { $0 == "GET" })
    }
    func testActualSDKServerRLSOmissionCannotBeInventedLocally() async throws {
        let rows = try await run("rlsDenied"); XCTAssertTrue(rows.isEmpty)
    }
    func testActualSDKRevokedRLSRowDuringHydrationIsDiscarded() async {
        do { _ = try await run("revokePost"); XCTFail("Revoked row must fail closed") } catch { }
    }
    func testActualSDKUnfollowDuringHydrationIsDiscarded() async {
        do { _ = try await run("revokeFollow"); XCTFail("Unfollow must fail closed") } catch { }
    }
    func testActualSDKUnexpectedPrivateRowFailsLocalHomeCeiling() async {
        do { _ = try await run("private"); XCTFail("Private other-owner row must never pass local home ceiling") } catch { }
    }
}
private final class LegacyFollowersHTTP: URLProtocol {
    static let lock = NSLock()
    static var mode = "allowed", postReads = 0, followReads = 0
    static var queries: [String] = [], paths: [String] = [], methods: [String] = []
    static let author = "f0180000-0000-4000-8000-000000000002"
    static func reset(_ value: String) { lock.lock(); defer { lock.unlock() }; mode=value;postReads=0;followReads=0;queries=[];paths=[];methods=[] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "followers-rls.invalid",request.value(forHTTPHeaderField: "x-soom-social-contract") == "approved-v1",
              request.value(forHTTPHeaderField: "x-soom-workout-contract") == "detail-v1" else { client?.urlProtocol(self,didFailWithError:URLError(.unsupportedURL));return }
        Self.lock.lock()
        let path = request.url?.lastPathComponent ?? ""
        Self.paths.append(path);Self.queries.append(request.url?.absoluteString.removingPercentEncoding ?? "");Self.methods.append(request.httpMethod ?? "")
        var body = "[]"
        switch path {
        case "user_follows":
            Self.followReads += 1
            if !(Self.mode == "revokeFollow" && Self.followReads > 1) { body="[{\"followed_id\":\"\(Self.author)\"}]" }
        case "feed_posts":
            Self.postReads += 1
            if Self.mode != "rlsDenied" && !(Self.mode == "revokePost" && Self.postReads > 1) {
                let visibility = Self.mode == "private" ? "private" : "followers"
                body="[{\"id\":\"f0180000-0000-4000-8000-000000000003\",\"user_id\":\"\(Self.author)\",\"sport\":\"running\",\"title\":\"Synthetic permitted workout\",\"visibility\":\"\(visibility)\",\"created_at\":\"2026-11-01T00:00:00Z\",\"activity_at\":\"2026-11-01T00:00:00Z\",\"audience_contract\":1,\"duration_seconds\":1800,\"distance_meters\":5000}]"
            }
        case "profiles", "feed_post_media", "feed_reactions", "feed_comments", "feed_bookmarks": break
        default: Self.lock.unlock();client?.urlProtocol(self,didFailWithError:URLError(.unsupportedURL));return
        }
        Self.lock.unlock()
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(body.utf8));client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
