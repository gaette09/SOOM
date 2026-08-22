import XCTest
@testable import SOOM

@MainActor
final class FeedViewModelTests: XCTestCase {
    func testLoadBuildsProductionReadModelFromProviders() async {
        let item = FeedMockData.items[0]
        let progress = makeProgress(workoutCount: 3)
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let viewModel = FeedViewModel(
            feedLoader: StubFeedLoader(items: [item]),
            weeklyProgressProvider: StubWeeklyProgressProvider(result: .success(progress)),
            recoveryPreviewProvider: StubRecoveryPreviewProvider(result: .success(
                UnifiedWorkoutRecoveryPreviewResult(summary: .mockToday, usedWorkoutCount: 3)
            )),
            streakDatesProvider: StubStreakDatesProvider(result: .success([referenceDate])),
            now: { referenceDate }
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.readModel.items, [item])
        XCTAssertEqual(viewModel.readModel.weeklySnapshot?.progress, progress)
        XCTAssertEqual(viewModel.readModel.weeklySnapshot?.sportSummary, "이번 주 3회 움직였어요")
        XCTAssertEqual(viewModel.readModel.recoveryInsight?.score, RecoverySummary.mockToday.score)
        XCTAssertEqual(viewModel.readModel.streak.weekCount, 1)
        XCTAssertEqual(viewModel.readModel.streak.activityCount, 1)
        XCTAssertFalse(viewModel.readModel.isLoading)
    }

    func testLoadKeepsSocialFeedWhenWorkoutSummariesFail() async {
        let item = FeedMockData.items[0]
        let viewModel = FeedViewModel(
            feedLoader: StubFeedLoader(items: [item]),
            weeklyProgressProvider: StubWeeklyProgressProvider(result: .failure(StubError.failed)),
            recoveryPreviewProvider: StubRecoveryPreviewProvider(result: .failure(StubError.failed)),
            streakDatesProvider: StubStreakDatesProvider(result: .failure(StubError.failed))
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.readModel.items, [item])
        XCTAssertNil(viewModel.readModel.weeklySnapshot)
        XCTAssertNil(viewModel.readModel.recoveryInsight)
        XCTAssertEqual(viewModel.readModel.streak.weekCount, 0)
        XCTAssertFalse(viewModel.readModel.isLoading)
    }

    func testToggleCheerAddsReactionAndUpdatesReadModelOptimistically() async {
        let item = FeedMockData.items[0]
        XCTAssertFalse(item.viewerHasCheered)
        let reactionPoster = StubReactionPoster()
        let viewModel = makeViewModel(items: [item], reactionPoster: reactionPoster)
        await viewModel.load()

        await viewModel.toggleCheer(for: item)

        XCTAssertEqual(reactionPoster.added, [FeedReactionCall(postId: item.id, reactionType: "cheer")])
        XCTAssertTrue(reactionPoster.removed.isEmpty)
        XCTAssertEqual(viewModel.readModel.items.first?.viewerHasCheered, true)
    }

    func testToggleCheerRemovesReactionWhenAlreadyCheered() async {
        var item = FeedMockData.items[0]
        item.viewerHasCheered = true
        let reactionPoster = StubReactionPoster()
        let viewModel = makeViewModel(items: [item], reactionPoster: reactionPoster)
        await viewModel.load()

        await viewModel.toggleCheer(for: item)

        XCTAssertEqual(reactionPoster.removed, [FeedReactionCall(postId: item.id, reactionType: "cheer")])
        XCTAssertEqual(viewModel.readModel.items.first?.viewerHasCheered, false)
    }

    func testToggleCheerRevertsOptimisticUpdateOnFailure() async {
        let item = FeedMockData.items[0]
        let reactionPoster = StubReactionPoster(error: StubError.failed)
        let viewModel = makeViewModel(items: [item], reactionPoster: reactionPoster)
        await viewModel.load()

        await viewModel.toggleCheer(for: item)

        XCTAssertEqual(viewModel.readModel.items.first?.viewerHasCheered, false)
    }

    func testToggleCheerIsNoOpForLocalDraft() async {
        var item = FeedMockData.items[0]
        item = FeedItem(
            id: item.id,
            authorName: item.authorName,
            authorHandle: item.authorHandle,
            isLocalDraft: true,
            createdAt: item.createdAt,
            itemType: item.itemType,
            visibility: item.visibility,
            cardData: item.cardData,
            caption: item.caption,
            activityContext: item.activityContext
        )
        let reactionPoster = StubReactionPoster()
        let viewModel = makeViewModel(items: [item], reactionPoster: reactionPoster)
        await viewModel.load()

        await viewModel.toggleCheer(for: item)

        XCTAssertTrue(reactionPoster.added.isEmpty)
        XCTAssertTrue(reactionPoster.removed.isEmpty)
    }

    func testPostCommentCallsPosterThenReloads() async throws {
        let item = FeedMockData.items[0]
        let commentPoster = StubCommentPoster()
        let viewModel = makeViewModel(items: [item], commentPoster: commentPoster)
        await viewModel.load()

        try await viewModel.postComment("좋은 흐름이에요!", on: item)

        XCTAssertEqual(commentPoster.posted, [FeedCommentCall(postId: item.id, body: "좋은 흐름이에요!")])
    }

    func testDeletePostRemovesRemotePostAndUpdatesReadModel() async {
        let item = FeedMockData.items[0]
        let postDeleter = StubPostDeleter()
        let viewModel = makeViewModel(items: [item], postDeleter: postDeleter)
        await viewModel.load()

        await viewModel.deletePost(item)

        XCTAssertEqual(postDeleter.deletedIds, [item.id])
        XCTAssertTrue(viewModel.readModel.items.isEmpty)
    }

    func testDeletePostRemovesLocalDraftFromDraftStoreNotRemotely() async {
        let draft = FeedItem(
            id: UUID(),
            authorName: "나",
            authorHandle: nil,
            isLocalDraft: true,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            itemType: .workoutSession,
            visibility: .privateOnly,
            cardData: FeedMockData.items[0].cardData,
            caption: nil,
            activityContext: "오늘의 라이딩"
        )
        let draftStore = InMemoryFeedShareDraftStore()
        let postDeleter = StubPostDeleter()
        let viewModel = makeViewModel(items: [draft], postDeleter: postDeleter, draftStore: draftStore)
        await viewModel.load()

        await viewModel.deletePost(draft)

        XCTAssertTrue(postDeleter.deletedIds.isEmpty)
        XCTAssertTrue(viewModel.readModel.items.isEmpty)
    }

    private func makeViewModel(
        items: [FeedItem],
        reactionPoster: (any FeedRemoteReactionPosting)? = nil,
        commentPoster: (any FeedRemoteCommentPosting)? = nil,
        postDeleter: (any FeedRemotePostDeleting)? = nil,
        draftStore: (any FeedShareDraftStoreProtocol)? = nil
    ) -> FeedViewModel {
        FeedViewModel(
            feedLoader: StubFeedLoader(items: items),
            weeklyProgressProvider: StubWeeklyProgressProvider(result: .failure(StubError.failed)),
            recoveryPreviewProvider: StubRecoveryPreviewProvider(result: .failure(StubError.failed)),
            streakDatesProvider: StubStreakDatesProvider(result: .failure(StubError.failed)),
            reactionPoster: reactionPoster,
            commentPoster: commentPoster,
            postDeleter: postDeleter,
            draftStore: draftStore
        )
    }

    private func makeProgress(workoutCount: Int) -> WeeklyWorkoutProgress {
        WeeklyWorkoutProgress(
            weekStartDate: Date(timeIntervalSince1970: 1_800_000_000),
            workoutCount: workoutCount,
            totalDistanceKm: 42.4,
            totalDurationMinutes: 180,
            averagePaceOrSpeedText: "평균 페이스 5'20\"/km",
            progressSummary: "이번 주도 리듬을 이어가고 있어요.",
            motivationText: "좋은 흐름입니다.",
            trendType: .steady
        )
    }
}

private struct StubFeedLoader: FeedLoading {
    let items: [FeedItem]

    func loadFeed(limit: Int) async -> [FeedItem] {
        Array(items.prefix(limit))
    }
}

private struct StubWeeklyProgressProvider: FeedWeeklyProgressProviding {
    let result: Result<WeeklyWorkoutProgress, Error>

    func fetchWeeklyProgress(referenceDate: Date) async throws -> WeeklyWorkoutProgress {
        try result.get()
    }
}

private struct StubRecoveryPreviewProvider: FeedRecoveryPreviewProviding {
    let result: Result<UnifiedWorkoutRecoveryPreviewResult, Error>

    func fetchPreviewSummary() async throws -> UnifiedWorkoutRecoveryPreviewResult {
        try result.get()
    }
}

private struct StubStreakDatesProvider: FeedStreakWorkoutDatesProviding {
    let result: Result<[Date], Error>

    func fetchRecentWorkoutDates(days: Int) async throws -> [Date] {
        try result.get()
    }
}

private enum StubError: Error {
    case failed
}

private struct FeedReactionCall: Equatable {
    let postId: UUID
    let reactionType: String
}

private final class StubReactionPoster: FeedRemoteReactionPosting {
    private(set) var added: [FeedReactionCall] = []
    private(set) var removed: [FeedReactionCall] = []
    let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func addReaction(postId: UUID, reactionType: String) async throws {
        if let error { throw error }
        added.append(FeedReactionCall(postId: postId, reactionType: reactionType))
    }

    func removeReaction(postId: UUID, reactionType: String) async throws {
        if let error { throw error }
        removed.append(FeedReactionCall(postId: postId, reactionType: reactionType))
    }
}

private struct FeedCommentCall: Equatable {
    let postId: UUID
    let body: String
}

private final class StubCommentPoster: FeedRemoteCommentPosting {
    private(set) var posted: [FeedCommentCall] = []

    func addComment(postId: UUID, body: String) async throws {
        posted.append(FeedCommentCall(postId: postId, body: body))
    }
}

private final class StubPostDeleter: FeedRemotePostDeleting {
    private(set) var deletedIds: [UUID] = []

    func deletePost(id: UUID) async throws {
        deletedIds.append(id)
    }
}
