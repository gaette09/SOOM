import Combine
import Foundation

final class RecoveryViewModel: ObservableObject {
    @Published private(set) var summary: RecoverySummary?
    @Published private(set) var latestCheckIn: RecoveryCheckIn?
    @Published private(set) var morningCheckInState: MorningCheckInState = .notCheckedInToday
    @Published private(set) var timelineEntries: [RecoveryTimelineEntry] = []
    @Published private(set) var weeklySummary: WeeklyRecoverySummary?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var snapshotErrorMessage: String?

    private let provider: any RecoveryDataProvider
    private let checkInStore: any RecoveryCheckInStore
    private let timelineBuilder: RecoveryTimelineBuilder
    private let weeklySummaryBuilder: WeeklyRecoverySummaryBuilder?
    private let snapshotWriter: DailyRecoverySnapshotWriter?
    private let explanationBuilder: RecoveryExplanationBuilder
    private let composer: RecoverySummaryComposer
    private let morningCheckInStateBuilder: MorningCheckInStateBuilder
    private let morningCheckInSkipStore: MorningCheckInSkipStore
    private var baseSummary: RecoverySummary?

    init(
        provider: any RecoveryDataProvider = ActivityRecoveryDataProvider(),
        checkInStore: any RecoveryCheckInStore = MockRecoveryCheckInStore.shared,
        timelineBuilder: RecoveryTimelineBuilder = RecoveryTimelineBuilder(),
        weeklySummaryBuilder: WeeklyRecoverySummaryBuilder? = nil,
        snapshotWriter: DailyRecoverySnapshotWriter? = nil,
        explanationBuilder: RecoveryExplanationBuilder = RecoveryExplanationBuilder(),
        composer: RecoverySummaryComposer = RecoverySummaryComposer(),
        morningCheckInStateBuilder: MorningCheckInStateBuilder = MorningCheckInStateBuilder(),
        morningCheckInSkipStore: MorningCheckInSkipStore = MorningCheckInSkipStore()
    ) {
        self.provider = provider
        self.checkInStore = checkInStore
        self.timelineBuilder = timelineBuilder
        self.weeklySummaryBuilder = weeklySummaryBuilder
        self.snapshotWriter = snapshotWriter
        self.explanationBuilder = explanationBuilder
        self.composer = composer
        self.morningCheckInStateBuilder = morningCheckInStateBuilder
        self.morningCheckInSkipStore = morningCheckInSkipStore
    }

    @MainActor
    func load() async {
        guard !isLoading else { return }
        await reload()
    }

    @MainActor
    func reload() async {
        isLoading = true
        errorMessage = nil
        snapshotErrorMessage = nil

        do {
            let fetchedSummary = try await provider.fetchRecoverySummary()
            baseSummary = fetchedSummary
            summary = fetchedSummary
        } catch {
            errorMessage = "회복 데이터를 새로 불러오지 못했어요. 표시 중인 이전 결과는 오늘의 이력으로 저장하지 않았어요."
            await refreshTimeline()
            await refreshWeeklySummary()
            isLoading = false
            return
        }

        await refreshCheckInPersonalization()
        await saveTodaySnapshotIfPossible()
        await refreshTimeline()
        await refreshWeeklySummary()
        isLoading = false
    }

    @MainActor
    func refreshCheckInPersonalization() async {
        guard baseSummary != nil else { return }

        do {
            let checkIns = try await checkInStore.fetchRecentCheckIns(days: 7)
            latestCheckIn = checkIns.sorted { $0.date > $1.date }.first
        } catch {
            latestCheckIn = nil
        }

        morningCheckInState = morningCheckInStateBuilder.build(
            latestCheckIn: latestCheckIn,
            hasSkippedToday: morningCheckInSkipStore.hasSkippedToday()
        )
        applyRecoveryPersonalization()
    }

    @MainActor
    func skipMorningCheckIn() {
        morningCheckInSkipStore.markSkippedToday()
        morningCheckInState = morningCheckInStateBuilder.build(
            latestCheckIn: latestCheckIn,
            hasSkippedToday: true
        )
    }

    private func applyRecoveryPersonalization() {
        guard let baseSummary else { return }

        summary = composer.compose(
            baseSummary: baseSummary,
            latestCheckIn: latestCheckIn
        )
    }

    @MainActor
    func refreshTimeline() async {
        timelineEntries = await timelineBuilder.buildTimeline(fallbackSummary: summary)
    }

    @MainActor
    func refreshWeeklySummary() async {
        guard let weeklySummaryBuilder else {
            weeklySummary = nil
            return
        }

        weeklySummary = await weeklySummaryBuilder.buildSummary()
    }

    @MainActor
    private func saveTodaySnapshotIfPossible() async {
        snapshotErrorMessage = nil
        guard let snapshotWriter, let summary, summary.hasCalculatedScore else {
            return
        }

        let explanation = explanationBuilder.build(
            summary: summary,
            latestCheckIn: latestCheckIn
        )

        do {
            try await snapshotWriter.saveTodaySnapshot(
                from: summary,
                latestCheckIn: latestCheckIn,
                explanation: explanation.explanation
            )
        } catch {
            snapshotErrorMessage = "회복 결과는 계산했지만 오늘의 이력을 저장하지 못했어요. 다시 시도해 주세요."
        }
    }
}
