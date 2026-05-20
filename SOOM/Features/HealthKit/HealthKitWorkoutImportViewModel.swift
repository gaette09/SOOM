import Foundation

@MainActor
final class HealthKitWorkoutImportViewModel: ObservableObject {
    @Published private(set) var isImporting = false
    @Published private(set) var lastResult: HealthKitWorkoutImportResult?
    @Published private(set) var errorMessage: String?

    private let pipeline: any HealthKitWorkoutImporting
    private let limit: Int

    init(
        pipeline: any HealthKitWorkoutImporting,
        limit: Int = 50
    ) {
        self.pipeline = pipeline
        self.limit = limit
    }

    func importRecentWorkouts() async {
        guard !isImporting else { return }

        isImporting = true
        errorMessage = nil

        let result = await pipeline.importRecentWorkouts(limit: limit)
        lastResult = result
        errorMessage = result.failedCount > 0 ? result.message : nil
        isImporting = false
    }
}
