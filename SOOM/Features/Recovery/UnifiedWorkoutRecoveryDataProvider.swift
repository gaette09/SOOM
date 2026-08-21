import Foundation

struct UnifiedWorkoutRecoveryDataProvider: RecoveryDataProvider {
    private let previewProvider: UnifiedWorkoutRecoveryPreviewProvider

    init(previewProvider: UnifiedWorkoutRecoveryPreviewProvider) {
        self.previewProvider = previewProvider
    }

    func fetchRecoverySummary() async throws -> RecoverySummary {
        try await previewProvider.fetchPreviewSummary().summary
    }
}
