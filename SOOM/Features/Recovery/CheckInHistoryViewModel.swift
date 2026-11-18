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
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let fetchedCheckIns = try await store.fetchRecentCheckIns(days: days)
            try Task.checkCancellation()
            checkIns = fetchedCheckIns.sorted { $0.date > $1.date }
        } catch is CancellationError {
            // Cancellation is not a failure or a replacement for cached data.
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "컨디션 기록을 불러오지 못했습니다."
        }

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
