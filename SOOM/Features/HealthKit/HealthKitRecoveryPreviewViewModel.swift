import Foundation

@MainActor
final class HealthKitRecoveryPreviewViewModel: ObservableObject {
    @Published private(set) var summary: RecoverySummary?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let provider: any RecoveryDataProvider

    init(
        provider: any RecoveryDataProvider = RecoveryDataProviderFactory.makeProvider(source: .healthKit)
    ) {
        self.provider = provider
    }

    var hasInsufficientHealthKitData: Bool {
        summary?.status == "데이터 부족"
    }

    func loadSummary() async {
        isLoading = true
        errorMessage = nil

        do {
            summary = try await provider.fetchRecoverySummary()
        } catch {
            summary = nil
            errorMessage = "HealthKit 기반 Recovery 미리보기를 불러오지 못했어요. 건강 앱 권한과 운동 기록을 확인해 주세요."
        }

        isLoading = false
    }
}
