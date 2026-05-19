import Foundation

final class ActivityRecoveryDataProvider: RecoveryDataProvider {
    private let store: any RecoveryActivityStore
    private let calculator: RecoveryCalculator

    init(
        store: any RecoveryActivityStore = MockRecoveryActivityStore(),
        calculator: RecoveryCalculator = RecoveryCalculator()
    ) {
        self.store = store
        self.calculator = calculator
    }

    func fetchRecoverySummary() async throws -> RecoverySummary {
        let activities = try await store.fetchRecentActivities(days: 7)
        return calculator.calculateSummary(from: activities)
    }
}
