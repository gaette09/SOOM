import Foundation

protocol RecoveryDataProvider {
    func fetchRecoverySummary() async throws -> RecoverySummary
}

struct MockRecoveryDataProvider: RecoveryDataProvider {
    func fetchRecoverySummary() async throws -> RecoverySummary {
        await Task.yield()
        return .mockToday
    }
}
