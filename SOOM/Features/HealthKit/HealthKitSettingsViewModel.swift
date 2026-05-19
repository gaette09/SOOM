import Foundation

@MainActor
final class HealthKitSettingsViewModel: ObservableObject {
    @Published private(set) var status: HealthKitConnectionStatus
    @Published private(set) var isRequesting = false
    @Published var errorMessage: String?

    private let manager: any HealthKitManaging

    init(manager: any HealthKitManaging = HealthKitManager()) {
        self.manager = manager
        self.status = manager.isHealthDataAvailable() ? .notRequested : .notAvailable
    }

    var statusText: String {
        status.title
    }

    var canRequestAuthorization: Bool {
        status != .notAvailable && !isRequesting
    }

    func requestAuthorization() async {
        guard manager.isHealthDataAvailable() else {
            status = .notAvailable
            errorMessage = "이 기기에서는 HealthKit 데이터를 사용할 수 없습니다."
            return
        }

        isRequesting = true
        errorMessage = nil

        do {
            try await manager.requestAuthorization()
            status = .accessLimited
        } catch {
            status = .accessLimited
            errorMessage = error.localizedDescription
        }

        isRequesting = false
    }
}
