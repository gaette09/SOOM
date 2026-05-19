import Foundation

final class CombinedRecoveryDataProvider: RecoveryDataProvider {
    private let activityStore: any RecoveryActivityStore
    private let checkInStore: any RecoveryCheckInStore
    private let calculator: RecoveryCalculator
    private let generatedAt: () -> Date

    init(
        activityStore: any RecoveryActivityStore = MockRecoveryActivityStore(),
        checkInStore: any RecoveryCheckInStore = MockRecoveryCheckInStore(),
        calculator: RecoveryCalculator = RecoveryCalculator(),
        generatedAt: @escaping () -> Date = Date.init
    ) {
        self.activityStore = activityStore
        self.checkInStore = checkInStore
        self.calculator = calculator
        self.generatedAt = generatedAt
    }

    func fetchRecoverySummary() async throws -> RecoverySummary {
        let activities = try await activityStore.fetchRecentActivities(days: 7)
        let checkIns = try await checkInStore.fetchRecentCheckIns(days: 7)
        let context = RecoveryInputContext(
            activities: activities,
            checkIns: checkIns,
            generatedAt: generatedAt()
        )

        // TODO: In v2, pass RecoveryInputContext into a score engine that can merge
        // subjective check-ins, HealthKit signals, and app-owned activity history.
        _ = RecoveryCheckInSummary.make(from: context.checkIns)
        return calculator.calculateSummary(from: context.activities)
    }
}
