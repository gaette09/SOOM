import XCTest
@testable import SOOM

@MainActor
final class CommunitySafetyTests: XCTestCase {
    func testPreviewLegacyReceiptIsReadOnlyAndExpiresWithContext() {
        let owner = UUID()
        let store = CommunitySafetyStore(client: nil, viewerID: owner, requiresSocialVerification: true)
        XCTAssertTrue(store.setActivityPreviewVerified(true, owner: owner, generation: 0, expectedRevision: 0))
        var item = FeedMockData.items[0]
        XCTAssertTrue(store.filtered([item]).isEmpty)
        item.previewLegacyReadContext = .init(viewerID: owner, generation: store.accountGeneration, safetyRevision: store.revision)
        XCTAssertEqual(store.filtered([item]).count, 1)
        XCTAssertFalse(store.canUseSocial)
        XCTAssertThrowsError(try store.requireSocialAccess(viewerID: owner))
        store.invalidateRelationships()
        XCTAssertTrue(store.filtered([item]).isEmpty)
        XCTAssertTrue(store.setActivityPreviewVerified(true, owner: owner, generation: store.accountGeneration, expectedRevision: store.revision))
        XCTAssertTrue(store.filtered([item]).isEmpty)
        store.setViewerID(UUID())
        XCTAssertTrue(store.filtered([item]).isEmpty)
    }
    func testPreviewVerificationIsContextBoundAndNeverEnablesLegacySocial() {
        let owner = UUID()
        let store = CommunitySafetyStore(client: nil, viewerID: owner, requiresSocialVerification: true)
        let generation = store.accountGeneration, revision = store.revision
        XCTAssertFalse(store.setActivityPreviewVerified(true, owner: UUID(), generation: generation, expectedRevision: revision))
        XCTAssertTrue(store.setActivityPreviewVerified(true, owner: owner, generation: generation, expectedRevision: revision))
        XCTAssertTrue(store.canUseActivityPreview)
        XCTAssertFalse(store.canUseSocial)
        XCTAssertFalse(store.socialVerified)
        XCTAssertFalse(store.setActivityPreviewVerified(true, owner: owner, generation: generation, expectedRevision: revision))
        store.invalidateRelationships()
        XCTAssertFalse(store.canUseActivityPreview)
        XCTAssertTrue(store.setActivityPreviewVerified(true, owner: owner, generation: generation, expectedRevision: store.revision))
        store.setViewerID(UUID())
        XCTAssertFalse(store.canUseActivityPreview)
        XCTAssertFalse(store.previewVerified)
    }

    func testPreviewFilterNeverRevealsLegacyRemoteCards() {
        let owner = UUID()
        let store = CommunitySafetyStore(client: nil, viewerID: owner, requiresSocialVerification: true)
        XCTAssertTrue(store.setActivityPreviewVerified(true, owner: owner, generation: 0, expectedRevision: 0))
        let card = AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: owner,
            sport: "running", activityAt: "2026-11-12T00:00:00Z", durationSeconds: 120, distanceMeters: 300, revision: 1)
        let native = AccountActivityHydratedPage(cards: [.init(projection: card, legacyItem: nil)], nextCursor: nil, hasMore: false).displayItems()[0]
        var legacy = native
        // Build a separate legacy identity rather than changing immutable provenance.
        legacy = FeedItem(id: UUID(), authorName: "나", authorHandle: nil, authorId: owner, createdAt: Date(), itemType: .workoutSession, visibility: .privateOnly, cardData: native.cardData, caption: nil, activityContext: "")
        XCTAssertEqual(store.filtered([legacy, native]).map(\.id), [native.id])
        store.invalidateRelationships()
        XCTAssertTrue(store.filtered([native]).isEmpty)
    }

    func testReportNeedsReasonAndAuthenticatedSession() async {
        let client = SafetyServiceStub()
        let store = CommunitySafetyStore(client: client)
        let form = CommunityReportViewModel(target: target(), store: store)
        await form.submit()
        XCTAssertFalse(form.canSubmit)
        XCTAssertEqual(client.reportCalls, 0)
        form.reason = .harassment
        await form.submit()
        XCTAssertEqual(client.reportCalls, 0)
        XCTAssertNil(form.receiptID)
        XCTAssertNotNil(form.errorMessage)
    }

    func testFailedReportRetainsReasonDetailsAndCanRetry() async {
        let (store, client) = makeStore()
        let form = CommunityReportViewModel(target: target(), store: store)
        form.reason = .privacy
        form.details = "  개인정보를 공개했어요.  "
        client.failure = SafetyTestError.failed
        await form.submit()
        XCTAssertEqual(form.reason, .privacy)
        XCTAssertEqual(form.details, "  개인정보를 공개했어요.  ")
        XCTAssertNil(form.receiptID)
        XCTAssertNotNil(form.errorMessage)
        XCTAssertTrue(form.canSubmit)
        client.failure = nil
        await form.submit()
        XCTAssertEqual(form.receiptID, client.receiptID)
        XCTAssertEqual(client.lastDetails, "개인정보를 공개했어요.")
        XCTAssertNil(form.errorMessage)
        XCTAssertFalse(form.canSubmit)
    }

    func testOverlongDetailsAndSelfBlockNeverReachServer() async {
        let (store, client) = makeStore()
        do {
            _ = try await store.report(target: target(), reason: .other, details: String(repeating: "가", count: 2001))
            XCTFail("Expected validation failure")
        } catch { XCTAssertEqual(error as? CommunitySafetyError, .invalidDetails) }
        do {
            try await store.block(userID: client.userID, displayName: "나")
            XCTFail("Expected self-block rejection")
        } catch { XCTAssertEqual(error as? CommunitySafetyError, .invalidTarget) }
        XCTAssertEqual(client.reportCalls, 0)
        XCTAssertEqual(client.blockCalls, 0)
    }

    func testFailedBlockDoesNotHideContentAndFailedUnblockKeepsBlock() async throws {
        let (store, client) = makeStore()
        let userID = UUID()
        client.failure = SafetyTestError.failed
        do { try await store.block(userID: userID, displayName: "멤버"); XCTFail("Expected failure") } catch {}
        XCTAssertFalse(store.isBlocked(userID))
        XCTAssertEqual(store.revision, 0)
        client.failure = nil
        try await store.block(userID: userID, displayName: "멤버")
        XCTAssertTrue(store.isBlocked(userID))
        client.failure = SafetyTestError.failed
        do { try await store.unblock(userID: userID); XCTFail("Expected failure") } catch {}
        XCTAssertTrue(store.isBlocked(userID))
        XCTAssertEqual(store.blockedUsers.map(\.id), [userID])
    }

    func testSuccessfulUnblockRemovesConfirmedBlock() async throws {
        let (store, _) = makeStore()
        let id = UUID()
        try await store.block(userID: id, displayName: "멤버")
        let revision = store.revision
        try await store.unblock(userID: id)
        XCTAssertFalse(store.isBlocked(id))
        XCTAssertTrue(store.blockedUsers.isEmpty)
        XCTAssertGreaterThan(store.revision, revision)
    }

    func testDisconnectingSharedClientClearsCacheAndDisablesOperations() async throws {
        let (store, client) = makeStore()
        try await store.block(userID: UUID(), displayName: "멤버")
        store.configure(client: nil)
        XCTAssertTrue(store.blockedUsers.isEmpty)
        do {
            _ = try await store.report(target: target(), reason: .spam, details: "")
            XCTFail("Expected disconnected client")
        } catch { XCTAssertEqual(error as? CommunitySafetyError, .unavailable) }
        XCTAssertEqual(client.reportCalls, 0)
    }

    func testAccountChangeClearsBlocksAndIsIdempotent() async throws {
        let (store, client) = makeStore()
        try await store.block(userID: UUID(), displayName: "멤버")
        let revision = store.revision
        store.setViewerID(client.userID)
        XCTAssertEqual(store.revision, revision)
        store.setViewerID(UUID())
        XCTAssertTrue(store.blockedUsers.isEmpty)
        XCTAssertGreaterThan(store.revision, revision)
    }

    func testAuthenticatedAccountMismatchDoesNotSendRequest() async {
        let (store, client) = makeStore()
        store.setViewerID(UUID())
        do {
            _ = try await store.report(target: target(), reason: .spam, details: "")
            XCTFail("Expected account mismatch")
        } catch { XCTAssertEqual(error as? CommunitySafetyError, .accountChanged) }
        XCTAssertEqual(client.reportCalls, 0)
    }

    func testReportOpenedBeforeAccountChangeDoesNotSubmitAsNewAccount() async {
        let (store, client) = makeStore()
        let form = CommunityReportViewModel(target: target(), store: store)
        form.reason = .spam
        client.userID = UUID()
        store.setViewerID(client.userID)
        await form.submit()
        XCTAssertEqual(client.reportCalls, 0)
        XCTAssertNil(form.receiptID)
        XCTAssertNotNil(form.errorMessage)
    }

    func testInFlightBlockCannotPopulateNextAccountCache() async {
        let (store, client) = makeStore()
        let started = expectation(description: "block sent")
        var continuation: CheckedContinuation<Void, Never>?
        client.beforeBlockReturn = {
            await withCheckedContinuation { continuation = $0; started.fulfill() }
        }
        let blockedID = UUID()
        let action = Task { try await store.block(userID: blockedID, displayName: "멤버") }
        await fulfillment(of: [started], timeout: 2)
        store.setViewerID(UUID())
        continuation?.resume()
        do { try await action.value; XCTFail("Expected stale response rejection") }
        catch { XCTAssertEqual(error as? CommunitySafetyError, .accountChanged) }
        XCTAssertFalse(store.isBlocked(blockedID))
        XCTAssertTrue(store.blockedUsers.isEmpty)
    }

    func testStaleBlockedListCannotUndoJustConfirmedBlock() async throws {
        let (store, client) = makeStore()
        let started = expectation(description: "list sent")
        var continuation: CheckedContinuation<Void, Never>?
        client.beforeListReturn = {
            await withCheckedContinuation { continuation = $0; started.fulfill() }
        }
        let load = Task { try await store.refreshBlockedUsers() }
        await fulfillment(of: [started], timeout: 2)
        let blockedID = UUID()
        try await store.block(userID: blockedID, displayName: "멤버")
        continuation?.resume()
        try await load.value
        XCTAssertTrue(store.isBlocked(blockedID))
        XCTAssertEqual(store.blockedUsers.map(\.id), [blockedID])
    }

    func testConfirmedBlockImmediatelyInvalidatesFeedSavedAndComments() async throws {
        let (store, _) = makeStore()
        let blockedItem = FeedMockData.items[0]
        var visibleItem = FeedMockData.items[1]
        visibleItem.comments = [FeedComment(id: UUID(), authorId: blockedItem.authorId, body: "숨길 댓글", createdAt: Date(), isViewerAuthor: false)]
        let loader = SafetyFeedLoader(items: [blockedItem, visibleItem])
        let feed = makeFeed(loader: loader, store: store)
        let saved = FeedSavedPostsViewModel(repository: SafetySavedRepository(items: [blockedItem, visibleItem]), safetyStore: store)
        await feed.load()
        await saved.load()
        try await store.block(userID: blockedItem.authorId, displayName: blockedItem.authorName)
        XCTAssertFalse(feed.readModel.items.contains { $0.id == blockedItem.id })
        XCTAssertFalse(saved.items.contains { $0.id == blockedItem.id })
        XCTAssertTrue(feed.readModel.items.allSatisfy { $0.comments.isEmpty })
        XCTAssertTrue(saved.items.allSatisfy { $0.comments.isEmpty })
        store.setViewerID(UUID())
        XCTAssertTrue(feed.readModel.items.isEmpty)
        XCTAssertTrue(saved.items.isEmpty)
    }

    func testBlockedAuthorCannotReturnFromInflightFeedSnapshot() async throws {
        let (store, _) = makeStore()
        let item = FeedMockData.items[0]
        let started = expectation(description: "feed fetch")
        var continuation: CheckedContinuation<Void, Never>?
        let loader = SafetyFeedLoader(items: [item])
        loader.beforeFirstLoadReturn = {
            await withCheckedContinuation { continuation = $0; started.fulfill() }
        }
        let feed = makeFeed(loader: loader, store: store)
        let load = Task { await feed.load() }
        await fulfillment(of: [started], timeout: 2)
        try await store.block(userID: item.authorId, displayName: item.authorName)
        continuation?.resume()
        await load.value
        XCTAssertTrue(feed.readModel.items.isEmpty)
        XCTAssertEqual(loader.loadCalls, 2)
    }

    func testNotificationTargetRechecksServerInsteadOfUsingCachedPost() async {
        let (store, _) = makeStore()
        let item = FeedMockData.items[0]
        let loader = SafetyFeedLoader(items: [item])
        let feed = makeFeed(loader: loader, store: store)
        await feed.load()
        loader.items = [] // RLS no longer exposes the cached post.
        let result = await feed.resolveFeedItem(postId: item.id)
        XCTAssertNil(result)
        XCTAssertEqual(loader.postCalls, 1)
    }

    func testCommentRejectionRetainsDraftAndRetryWaitsForServer() async {
        let form = FeedCommentComposeViewModel()
        form.text = "  고칠 댓글  "
        let rejected = await form.submit { _ in throw SafetyTestError.moderationRejected }
        XCTAssertFalse(rejected)
        XCTAssertEqual(form.text, "  고칠 댓글  ")
        XCTAssertNotNil(form.errorMessage)
        XCTAssertTrue(form.canSubmit)
        var postedText: String?
        let accepted = await form.submit { postedText = $0 }
        XCTAssertTrue(accepted)
        XCTAssertEqual(postedText, "고칠 댓글")
        XCTAssertNil(form.errorMessage)
    }

    func testCommentComposerRejectsEmptyAndOverlongDraftsWithoutPosting() async {
        let form = FeedCommentComposeViewModel()
        var posts = 0
        let emptyResult = await form.submit { _ in posts += 1 }
        XCTAssertFalse(emptyResult)
        form.text = String(repeating: "가", count: 501)
        let longResult = await form.submit { _ in posts += 1 }
        XCTAssertFalse(longResult)
        XCTAssertEqual(posts, 0)
    }

    func testCommentWithoutConfiguredPosterThrowsInsteadOfReportingSuccess() async {
        let (store, _) = makeStore()
        let item = FeedMockData.items[0]
        let feed = makeFeed(loader: SafetyFeedLoader(items: [item]), store: store)
        do { try await feed.postComment("댓글", on: item); XCTFail("Expected unavailable") }
        catch { XCTAssertEqual(error as? CommunitySafetyError, .unavailable) }
    }

    func testLocalClubIDsNeverReachRemoteSafetyLookup() async throws {
        let (store, client) = makeStore()
        let local = try await store.verifiedClubIdentity(clubID: "local-club")
        XCTAssertNil(local)
        XCTAssertEqual(client.clubIdentityCalls, 0)
    }

    func testClubModerationUsesConfirmedServerOwnerAndRejectsMismatchedTarget() async throws {
        let (store, client) = makeStore()
        let clubID = UUID()
        let identity = CommunityClubIdentity(id: clubID, ownerID: UUID())
        client.clubIdentityResult = identity
        let result = try await store.verifiedClubIdentity(clubID: clubID.uuidString)
        XCTAssertEqual(result, identity)
        client.clubIdentityResult = CommunityClubIdentity(id: UUID(), ownerID: identity.ownerID)
        let mismatch = try await store.verifiedClubIdentity(clubID: clubID.uuidString)
        XCTAssertNil(mismatch)
    }

    private func target() -> CommunityReportTarget { CommunityReportTarget(kind: .post, id: UUID()) }
    private func makeStore() -> (CommunitySafetyStore, SafetyServiceStub) {
        let client = SafetyServiceStub()
        return (CommunitySafetyStore(client: client, viewerID: client.userID), client)
    }
    private func makeFeed(loader: SafetyFeedLoader, store: CommunitySafetyStore) -> FeedViewModel {
        FeedViewModel(feedLoader: loader, weeklyProgressProvider: SafetySummaryProvider(), recoveryPreviewProvider: SafetySummaryProvider(), streakDatesProvider: SafetySummaryProvider(), safetyStore: store)
    }
}

private enum SafetyTestError: Error { case failed, moderationRejected }

@MainActor
private final class SafetyServiceStub: CommunitySafetyServicing {
    var userID = UUID()
    let receiptID = UUID()
    var failure: Error?
    var reportCalls = 0
    var blockCalls = 0
    var lastDetails: String?
    var clubIdentityResult: CommunityClubIdentity?
    var clubIdentityCalls = 0
    var beforeBlockReturn: (() async -> Void)?
    var beforeListReturn: (() async -> Void)?
    func authenticatedUserID() async throws -> UUID { userID }
    func clubIdentity(id: UUID) async throws -> CommunityClubIdentity? {
        clubIdentityCalls += 1
        return clubIdentityResult
    }
    func report(target: CommunityReportTarget, reason: CommunityReportReason, details: String?) async throws -> UUID {
        reportCalls += 1
        lastDetails = details
        if let failure { throw failure }
        return receiptID
    }
    func block(userID: UUID) async throws {
        blockCalls += 1
        if let failure { throw failure }
        await beforeBlockReturn?()
    }
    func unblock(userID: UUID) async throws { if let failure { throw failure } }
    func listBlockedUsers() async throws -> [CommunityBlockedUser] {
        if let failure { throw failure }
        await beforeListReturn?()
        return []
    }
}

private final class SafetyFeedLoader: FeedLoading {
    var items: [FeedItem]
    var loadCalls = 0
    var postCalls = 0
    var beforeFirstLoadReturn: (() async -> Void)?
    init(items: [FeedItem]) { self.items = items }
    func loadFeed(limit: Int) async -> FeedLoadResult {
        loadCalls += 1
        let snapshot = items
        if loadCalls == 1 { await beforeFirstLoadReturn?() }
        return FeedLoadResult(items: snapshot)
    }
    func loadPost(id: UUID) async -> FeedItem? {
        postCalls += 1
        return items.first { $0.id == id }
    }
}

private struct SafetySavedRepository: FeedRepositoryProtocol {
    let items: [FeedItem]
    func fetchFeed(limit: Int) async throws -> [FeedItem] { items }
    func fetchSavedPosts() async throws -> [FeedItem] { items }
    func fetchPost(id: UUID) async throws -> FeedItem? { items.first { $0.id == id } }
}

private struct SafetySummaryProvider: FeedWeeklyProgressProviding, FeedRecoveryPreviewProviding, FeedStreakWorkoutDatesProviding {
    func fetchWeeklyProgress(referenceDate: Date) async throws -> WeeklyWorkoutProgress { throw SafetyTestError.failed }
    func fetchPreviewSummary() async throws -> UnifiedWorkoutRecoveryPreviewResult { throw SafetyTestError.failed }
    func fetchRecentWorkoutDates(days: Int) async throws -> [Date] { [] }
}
