import Combine
import Foundation

final class CheckInHistoryViewModel: ObservableObject {
    @Published private(set) var checkIns: [RecoveryCheckIn] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let store: any RecoveryCheckInStore
    private let days: Int

    init(
        store: any RecoveryCheckInStore = MockRecoveryCheckInStore.shared,
        days: Int = 30
    ) {
        self.store = store
        self.days = days
    }

    @MainActor
    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetchedCheckIns = try await store.fetchRecentCheckIns(days: days)
            checkIns = fetchedCheckIns.sorted { $0.date > $1.date }
        } catch {
            checkIns = []
            errorMessage = "컨디션 기록을 불러오지 못했습니다."
        }

        isLoading = false
    }

    @MainActor
    func removeCheckIn(id: UUID) {
        checkIns.removeAll { $0.id == id }
    }

    @MainActor
    func updateCheckIn(_ updatedCheckIn: RecoveryCheckIn) {
        guard let index = checkIns.firstIndex(where: { $0.id == updatedCheckIn.id }) else {
            return
        }

        checkIns[index] = updatedCheckIn
        checkIns.sort { $0.date > $1.date }
    }
}
