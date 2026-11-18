import Foundation

@MainActor
final class RecoveryRealDataPreviewViewModel: ObservableObject {
    @Published private(set) var summary: RecoverySummary?
    @Published private(set) var comparison: RecoveryComparisonSummary?
    @Published private(set) var usedWorkoutCount = 0
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let provider: UnifiedWorkoutRecoveryPreviewProvider
    private let officialProvider: (any RecoveryDataProvider)?
    private let comparisonBuilder: RecoveryComparisonBuilder

    init(
        provider: UnifiedWorkoutRecoveryPreviewProvider,
        officialProvider: (any RecoveryDataProvider)? = nil,
        comparisonBuilder: RecoveryComparisonBuilder = RecoveryComparisonBuilder()
    ) {
        self.provider = provider
        self.officialProvider = officialProvider
        self.comparisonBuilder = comparisonBuilder
    }

    var hasInsufficientWorkoutData: Bool {
        summary?.hasCalculatedScore != true || usedWorkoutCount == 0
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let result = try await provider.fetchPreviewSummary()
            try Task.checkCancellation()
            summary = result.summary
            usedWorkoutCount = result.usedWorkoutCount
            comparison = await buildComparisonIfPossible(previewSummary: result.summary)
        } catch is CancellationError {
            // Cancellation is not a failure or a replacement for cached data.
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "가져온 운동 기록 기반 Recovery 미리보기를 불러오지 못했어요. 운동 기록 저장 상태를 확인해 주세요."
        }

    }

    private func buildComparisonIfPossible(previewSummary: RecoverySummary) async -> RecoveryComparisonSummary? {
        guard previewSummary.hasCalculatedScore, let officialProvider else { return nil }

        do {
            let officialSummary = try await officialProvider.fetchRecoverySummary()
            guard officialSummary.hasCalculatedScore else { return nil }
            return comparisonBuilder.build(
                officialSummary: officialSummary,
                previewSummary: previewSummary
            )
        } catch {
            return nil
        }
    }
}
