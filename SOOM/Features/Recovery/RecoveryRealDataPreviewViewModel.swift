import Foundation

@MainActor
final class RecoveryRealDataPreviewViewModel: ObservableObject {
    @Published private(set) var summary: RecoverySummary?
    @Published private(set) var usedWorkoutCount = 0
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let provider: UnifiedWorkoutRecoveryPreviewProvider

    init(provider: UnifiedWorkoutRecoveryPreviewProvider) {
        self.provider = provider
    }

    var hasInsufficientWorkoutData: Bool {
        summary?.status == "데이터 부족" || usedWorkoutCount == 0
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await provider.fetchPreviewSummary()
            summary = result.summary
            usedWorkoutCount = result.usedWorkoutCount
        } catch {
            summary = nil
            usedWorkoutCount = 0
            errorMessage = "가져온 운동 기록 기반 Recovery 미리보기를 불러오지 못했어요. 운동 기록 저장 상태를 확인해 주세요."
        }

        isLoading = false
    }
}
