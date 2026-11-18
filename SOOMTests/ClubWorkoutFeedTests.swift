import XCTest
@testable import SOOM

@MainActor
final class ClubWorkoutFeedTests: XCTestCase {
    private let viewer = UUID()
    private let club = UUID()

    func testLoadFiltersOwnPrivatePostsAndCapsSortedPublicResults() async {
        let remote = ClubFeedMock(viewer: viewer)
        let scope = ScopeBox(viewer: viewer)
        let publicItems = (0..<30).map { item(author: viewer, age: $0) }
        remote.items = Array(publicItems.reversed()) + [item(author: viewer, visibility: .privatePost)]
        let model = model(remote, scope)
        await model.load()
        XCTAssertEqual(remote.requestedLimits, [20])
        XCTAssertEqual(model.visibleItems.map(\.id), publicItems.prefix(20).map(\.id))
        XCTAssertTrue(model.visibleItems.allSatisfy { $0.visibility == .publicFeed })
    }

    func testLateAccountChangeCannotPublishOldResponse() async {
        let remote = ClubFeedMock(viewer: viewer)
        let scope = ScopeBox(viewer: viewer)
        remote.items = [item(author: viewer)]
        remote.onFetch = { scope.value = .init(viewerID: UUID(), accountGeneration: 2, safetyRevision: 2) }
        let model = model(remote, scope)
        await model.load()
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(model.visibleItems.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    func testLateSafetyChangeCannotPublishResponseEvenForSameAccount() async {
        let remote = ClubFeedMock(viewer: viewer)
        let scope = ScopeBox(viewer: viewer)
        remote.items = [item(author: UUID())]
        remote.onFetch = { scope.value = .init(viewerID: self.viewer, accountGeneration: 1, safetyRevision: 2) }
        let model = model(remote, scope)
        await model.load()
        XCTAssertTrue(model.visibleItems.isEmpty)
    }

    func testBlockedAuthorFilterAppliesToLoadAndAlreadyLoadedCards() async {
        let remote = ClubFeedMock(viewer: viewer)
        let scope = ScopeBox(viewer: viewer)
        let author = UUID()
        remote.items = [item(author: author), item(author: viewer)]
        var blocked = Set<UUID>()
        let model = ClubWorkoutFeedModel(clubID: club, remote: remote, scope: { scope.value },
                                        filter: { $0.filter { !blocked.contains($0.authorId) } })
        await model.load()
        XCTAssertEqual(model.visibleItems.count, 2)
        blocked.insert(author)
        XCTAssertEqual(model.visibleItems.map(\.authorId), [viewer])
    }

    func testSDKAccountChangeImmediatelyHidesLoadedCardsAndRejectsMutation() async {
        let remote = ClubFeedMock(viewer: viewer)
        let scope = ScopeBox(viewer: viewer)
        let post = item(author: viewer)
        remote.items = [post]
        let model = model(remote, scope)
        await model.load()
        remote.sessionUserID = UUID()
        XCTAssertTrue(model.visibleItems.isEmpty)
        do {
            try await model.perform(.bookmark(true), on: post)
            XCTFail("A previous account must not modify the new account's bookmarks")
        } catch CommunitySafetyError.accountChanged {} catch { XCTFail("\(error)") }
        XCTAssertTrue(remote.actions.isEmpty)
    }

    func testMembershipFailureClearsEarlierSnapshot() async {
        let remote = ClubFeedMock(viewer: viewer)
        let scope = ScopeBox(viewer: viewer)
        remote.items = [item(author: viewer)]
        let model = model(remote, scope)
        await model.load()
        XCTAssertEqual(model.visibleItems.count, 1)
        remote.error = ClubWorkoutFeedError.membershipRequired
        await model.load()
        XCTAssertTrue(model.visibleItems.isEmpty)
        XCTAssertTrue(model.requiresMembership)
    }

    func testMutationReloadsConfirmedStateAndRejectsDeletingAnotherAuthorsPost() async throws {
        let remote = ClubFeedMock(viewer: viewer)
        let scope = ScopeBox(viewer: viewer)
        let post = item(author: UUID())
        remote.items = [post]
        let model = model(remote, scope)
        await model.load()
        try await model.perform(.cheer(true), on: post)
        XCTAssertEqual(remote.actions, [.cheer(true)])
        XCTAssertEqual(remote.requestedLimits, [20, 20])
        do {
            try await model.perform(.delete, on: post)
            XCTFail("Club membership never grants deletion of another author's post")
        } catch CommunitySafetyError.invalidTarget {} catch { XCTFail("\(error)") }
        XCTAssertEqual(remote.actions, [.cheer(true)])
    }

    func testSignedOutViewDoesNotFetch() async {
        let remote = ClubFeedMock(viewer: viewer)
        let scope = ScopeBox(viewer: nil)
        let model = model(remote, scope)
        await model.load()
        XCTAssertTrue(remote.requestedLimits.isEmpty)
        XCTAssertTrue(model.visibleItems.isEmpty)
    }

    private func model(_ remote: ClubFeedMock, _ scope: ScopeBox) -> ClubWorkoutFeedModel {
        ClubWorkoutFeedModel(clubID: club, remote: remote, scope: { scope.value })
    }

    private func item(author: UUID, visibility: FeedPostVisibility = .publicPost, age: Int = 0) -> FeedItem {
        FeedPostBundleDTO(post: FeedPostDTO(id: UUID(), userId: author, sport: .running,
            title: "운동 \(age)", visibility: visibility,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000 - Double(age))))
            .makeFeedItem(authorName: "테스트", currentUserId: viewer)
    }
}

@MainActor
private final class ScopeBox {
    var value: ClubWorkoutFeedScope
    init(viewer: UUID?) { value = .init(viewerID: viewer, accountGeneration: 1, safetyRevision: 1) }
}

@MainActor
private final class ClubFeedMock: ClubWorkoutFeedRemote {
    var sessionUserID: UUID?
    var items: [FeedItem] = []
    var error: Error?
    var requestedLimits: [Int] = []
    var actions: [ClubWorkoutFeedAction] = []
    var onFetch: (() -> Void)?
    init(viewer: UUID) { sessionUserID = viewer }
    func fetch(clubID: UUID, viewerID: UUID, limit: Int) async throws -> [FeedItem] {
        requestedLimits.append(limit)
        onFetch?()
        if let error { throw error }
        return items
    }
    func perform(_ action: ClubWorkoutFeedAction, on item: FeedItem, clubID: UUID, viewerID: UUID) async throws {
        actions.append(action)
    }
}
