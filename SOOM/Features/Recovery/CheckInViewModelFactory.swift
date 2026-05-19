import Foundation
import SwiftData

@MainActor
struct CheckInViewModelFactory {
    // Default mock store is kept for Preview, tests, and rollback only.
    // Production Check-in entry points should use CheckInViewContainer.
    private let store: any RecoveryCheckInWritableStore
    private let now: () -> Date

    init(
        store: any RecoveryCheckInWritableStore = MockRecoveryCheckInStore.shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.now = now
    }

    func makeViewModel() -> CheckInViewModel {
        CheckInViewModel(store: store, now: now)
    }

    static func makeSwiftDataViewModel(modelContext: ModelContext) -> CheckInViewModel {
        CheckInViewModel(
            store: SwiftDataCheckInStore(modelContext: modelContext)
        )
    }
}
