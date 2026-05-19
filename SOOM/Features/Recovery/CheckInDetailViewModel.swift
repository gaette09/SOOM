import Combine
import Foundation

@MainActor
final class CheckInDetailViewModel: ObservableObject {
    @Published private(set) var isDeleting = false
    @Published private(set) var errorMessage: String?

    private let store: any RecoveryCheckInEditableStore
    private let onDeleted: (UUID) -> Void

    init(
        store: any RecoveryCheckInEditableStore = MockRecoveryCheckInStore.shared,
        onDeleted: @escaping (UUID) -> Void = { _ in }
    ) {
        self.store = store
        self.onDeleted = onDeleted
    }

    func deleteCheckIn(id: UUID) async -> Bool {
        guard !isDeleting else { return false }

        isDeleting = true
        errorMessage = nil

        do {
            try await store.deleteCheckIn(id: id)
            onDeleted(id)
            isDeleting = false
            return true
        } catch {
            errorMessage = "기록을 삭제하지 못했습니다. 잠시 후 다시 시도해 주세요."
            isDeleting = false
            return false
        }
    }
}
