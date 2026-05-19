import Combine
import Foundation

final class RecoveryViewModel: ObservableObject {
    @Published private(set) var summary: RecoverySummary?
    @Published private(set) var latestCheckIn: RecoveryCheckIn?
    @Published private(set) var timelineEntries: [RecoveryTimelineEntry] = []
    @Published private(set) var weeklySummary: WeeklyRecoverySummary?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let provider: any RecoveryDataProvider
    private let checkInStore: any RecoveryCheckInStore
    private let timelineBuilder: RecoveryTimelineBuilder
    private let weeklySummaryBuilder: WeeklyRecoverySummaryBuilder?
    private let snapshotWriter: DailyRecoverySnapshotWriter?
    private let explanationBuilder: RecoveryExplanationBuilder
    private let composer: RecoverySummaryComposer
    private var baseSummary: RecoverySummary?

    init(
        provider: any RecoveryDataProvider = ActivityRecoveryDataProvider(),
        checkInStore: any RecoveryCheckInStore = MockRecoveryCheckInStore.shared,
        timelineBuilder: RecoveryTimelineBuilder = RecoveryTimelineBuilder(),
        weeklySummaryBuilder: WeeklyRecoverySummaryBuilder? = nil,
        snapshotWriter: DailyRecoverySnapshotWriter? = nil,
        explanationBuilder: RecoveryExplanationBuilder = RecoveryExplanationBuilder(),
        composer: RecoverySummaryComposer = RecoverySummaryComposer()
    ) {
        self.provider = provider
        self.checkInStore = checkInStore
        self.timelineBuilder = timelineBuilder
        self.weeklySummaryBuilder = weeklySummaryBuilder
        self.snapshotWriter = snapshotWriter
        self.explanationBuilder = explanationBuilder
        self.composer = composer
    }

    @MainActor
    func load() async {
        guard summary == nil, !isLoading else {
            await refreshCheckInPersonalization()
            await saveTodaySnapshotIfPossible()
            await refreshTimeline()
            await refreshWeeklySummary()
            return
        }
        await reload()
    }

    @MainActor
    func reload() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetchedSummary = try await provider.fetchRecoverySummary()
            baseSummary = fetchedSummary
            summary = fetchedSummary
        } catch {
            errorMessage = "회복 데이터를 불러오지 못했습니다."
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

        applyRecoveryPersonalization()
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
        guard let snapshotWriter, let summary else {
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
            // Snapshot persistence is a historical aid. It should never block Recovery.
        }
    }
}
