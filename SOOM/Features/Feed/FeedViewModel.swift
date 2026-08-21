import Foundation

protocol FeedLoading {
    func loadFeed(limit: Int) async -> [FeedItem]
}

extension FeedDataSource: FeedLoading {}

protocol FeedWeeklyProgressProviding {
    func fetchWeeklyProgress(referenceDate: Date) async throws -> WeeklyWorkoutProgress
}

extension UnifiedWorkoutWeeklyProgressProvider: FeedWeeklyProgressProviding {}

protocol FeedRecoveryPreviewProviding {
    func fetchPreviewSummary() async throws -> UnifiedWorkoutRecoveryPreviewResult
}

extension UnifiedWorkoutRecoveryPreviewProvider: FeedRecoveryPreviewProviding {}

protocol FeedStreakWorkoutDatesProviding {
    func fetchRecentWorkoutDates(days: Int) async throws -> [Date]
}

struct UnifiedWorkoutStoreStreakDatesProvider: FeedStreakWorkoutDatesProviding {
    let store: any UnifiedWorkoutStore

    func fetchRecentWorkoutDates(days: Int) async throws -> [Date] {
        try await store.fetchRecentWorkouts(days: days).map(\.startDate)
    }
}

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var readModel: FeedReadModel

    private let feedLoader: any FeedLoading
    private let weeklyProgressProvider: any FeedWeeklyProgressProviding
    private let recoveryPreviewProvider: any FeedRecoveryPreviewProviding
    private let streakDatesProvider: any FeedStreakWorkoutDatesProviding
    private let now: () -> Date

    init(
        feedLoader: any FeedLoading,
        weeklyProgressProvider: any FeedWeeklyProgressProviding,
        recoveryPreviewProvider: any FeedRecoveryPreviewProviding,
        streakDatesProvider: any FeedStreakWorkoutDatesProviding,
        now: @escaping () -> Date = Date.init
    ) {
        self.feedLoader = feedLoader
        self.weeklyProgressProvider = weeklyProgressProvider
        self.recoveryPreviewProvider = recoveryPreviewProvider
        self.streakDatesProvider = streakDatesProvider
        self.now = now
        self.readModel = .loading
    }

    func load() async {
        let referenceDate = now()
        readModel.isLoading = true
        async let feedItems = feedLoader.loadFeed(limit: 20)
        async let weeklyProgress = weeklyProgressProvider.fetchWeeklyProgress(referenceDate: referenceDate)
        async let recoveryPreview = recoveryPreviewProvider.fetchPreviewSummary()
        async let streakDates = streakDatesProvider.fetchRecentWorkoutDates(days: 180)

        let items = await feedItems
        let progress = try? await weeklyProgress
        let recovery = try? await recoveryPreview
        let workoutDates = (try? await streakDates) ?? []

        readModel = FeedReadModel(
            items: items,
            weeklySnapshot: progress.map {
                FeedWeeklySnapshot(progress: $0, sportSummary: sportSummary(for: $0))
            },
            recoveryInsight: recovery.map { FeedRecoveryInsight(summary: $0.summary) },
            streak: WeeklyStreakCalculator.calculate(workoutDates: workoutDates, referenceDate: referenceDate),
            isLoading: false
        )
    }

    private func sportSummary(for progress: WeeklyWorkoutProgress) -> String {
        guard progress.workoutCount > 0 else { return "이번 주 운동을 기다리고 있어요" }
        return "이번 주 (progress.workoutCount)회 움직였어요"
    }
}

struct FeedReadModel: Equatable {
    var items: [FeedItem]
    var weeklySnapshot: FeedWeeklySnapshot?
    var recoveryInsight: FeedRecoveryInsight?
    var streak: FeedStreakSnapshot
    var isLoading: Bool

    static let loading = FeedReadModel(
        items: [],
        weeklySnapshot: nil,
        recoveryInsight: nil,
        streak: FeedStreakSnapshot(weekCount: 0, activityCount: 0),
        isLoading: true
    )
}
