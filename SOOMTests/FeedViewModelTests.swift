import XCTest
@testable import SOOM

@MainActor
final class FeedViewModelTests: XCTestCase {
    func testLoadBuildsProductionReadModelFromProviders() async {
        let item = FeedMockData.items[0]
        let progress = makeProgress(workoutCount: 3)
        let viewModel = FeedViewModel(
            feedLoader: StubFeedLoader(items: [item]),
            weeklyProgressProvider: StubWeeklyProgressProvider(result: .success(progress)),
            recoveryPreviewProvider: StubRecoveryPreviewProvider(result: .success(
                UnifiedWorkoutRecoveryPreviewResult(summary: .mockToday, usedWorkoutCount: 3)
            )),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.readModel.items, [item])
        XCTAssertEqual(viewModel.readModel.weeklySnapshot?.progress, progress)
        XCTAssertEqual(viewModel.readModel.weeklySnapshot?.sportSummary, "이번 주 3회 움직였어요")
        XCTAssertEqual(viewModel.readModel.recoveryInsight?.score, RecoverySummary.mockToday.score)
        XCTAssertFalse(viewModel.readModel.isLoading)
    }

    func testLoadKeepsSocialFeedWhenWorkoutSummariesFail() async {
        let item = FeedMockData.items[0]
        let viewModel = FeedViewModel(
            feedLoader: StubFeedLoader(items: [item]),
            weeklyProgressProvider: StubWeeklyProgressProvider(result: .failure(StubError.failed)),
            recoveryPreviewProvider: StubRecoveryPreviewProvider(result: .failure(StubError.failed))
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.readModel.items, [item])
        XCTAssertNil(viewModel.readModel.weeklySnapshot)
        XCTAssertNil(viewModel.readModel.recoveryInsight)
        XCTAssertFalse(viewModel.readModel.isLoading)
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

private enum StubError: Error {
    case failed
}
