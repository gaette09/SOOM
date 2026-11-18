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
            store: makeStore(modelContext: modelContext)
        )
    }
    static func makeStore(modelContext: ModelContext) -> any RecoveryCheckInEditableStore {
        let base = SwiftDataCheckInStore(modelContext: modelContext)
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_CHECKIN_FORM_QA"] == "1" {
            return CheckInSyntheticFailureStore(base: base)
        }
        #endif
        return base
    }

}

#if DEBUG && targetEnvironment(simulator)
/// Fault injection in the real form/container; only the isolated demo database.
@MainActor
private final class CheckInSyntheticFailureStore: RecoveryCheckInEditableStore {
    let base: SwiftDataCheckInStore
    var failSave = true
    var failEdit = true
    init(base: SwiftDataCheckInStore) { self.base = base }
    func fetchRecentCheckIns(days: Int) async throws -> [RecoveryCheckIn] { try await base.fetchRecentCheckIns(days: days) }
    func saveCheckIn(_ value: RecoveryCheckIn) async throws {
        try await Task.sleep(for: .milliseconds(500))
        if failSave { failSave = false; throw CocoaError(.fileWriteUnknown) }
        try await base.saveCheckIn(value)
    }
    func updateCheckIn(_ value: RecoveryCheckIn) async throws {
        try await Task.sleep(for: .milliseconds(500))
        if failEdit { failEdit = false; throw CocoaError(.fileWriteUnknown) }
        try await base.updateCheckIn(value)
    }
    func deleteCheckIn(id: UUID) async throws { throw CocoaError(.featureUnsupported) }
    func deleteAllCheckIns() async throws { throw CocoaError(.featureUnsupported) }
}
#endif
