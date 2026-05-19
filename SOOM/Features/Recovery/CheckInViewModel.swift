import Combine
import Foundation

@MainActor
final class CheckInViewModel: ObservableObject {
    @Published var fatigueLevel: Int = 3
    @Published var sleepQuality: Int = 3
    @Published var muscleSoreness: Int = 2
    @Published var moodLevel: Int = 3
    @Published var note: String = ""
    @Published private(set) var isSaving = false
    @Published private(set) var confirmationMessage: String?
    @Published private(set) var errorMessage: String?

    private let store: any RecoveryCheckInWritableStore
    private let now: () -> Date

    init(
        store: any RecoveryCheckInWritableStore = MockRecoveryCheckInStore.shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.now = now
    }

    var canSave: Bool {
        !isSaving
    }

    func save() async {
        guard canSave else { return }

        isSaving = true
        errorMessage = nil

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let checkIn = RecoveryCheckIn(
            date: now(),
            fatigueLevel: fatigueLevel,
            sleepQuality: sleepQuality,
            muscleSoreness: muscleSoreness,
            moodLevel: moodLevel,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )

        do {
            try await store.saveCheckIn(checkIn)
            confirmationMessage = "오늘의 회복 해석이 더 정확해졌어요."
        } catch {
            errorMessage = "기록하지 못했습니다. 잠시 후 다시 시도해 주세요."
        }

        isSaving = false
    }
}
