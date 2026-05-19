import Combine
import Foundation

@MainActor
final class CheckInEditViewModel: ObservableObject {
    @Published var fatigueLevel: Int
    @Published var sleepQuality: Int
    @Published var muscleSoreness: Int
    @Published var moodLevel: Int
    @Published var note: String
    @Published private(set) var isSaving = false
    @Published private(set) var confirmationMessage: String?
    @Published private(set) var errorMessage: String?

    private let originalCheckIn: RecoveryCheckIn
    private let store: any RecoveryCheckInEditableStore

    init(
        checkIn: RecoveryCheckIn,
        store: any RecoveryCheckInEditableStore = MockRecoveryCheckInStore.shared
    ) {
        self.originalCheckIn = checkIn
        self.store = store
        fatigueLevel = checkIn.fatigueLevel
        sleepQuality = checkIn.sleepQuality
        muscleSoreness = checkIn.muscleSoreness
        moodLevel = checkIn.moodLevel
        note = checkIn.note ?? ""
    }

    var canSave: Bool {
        !isSaving
    }

    func save() async -> RecoveryCheckIn? {
        guard canSave else { return nil }

        isSaving = true
        errorMessage = nil
        confirmationMessage = nil

        let updatedCheckIn = makeUpdatedCheckIn()

        do {
            try await store.updateCheckIn(updatedCheckIn)
            confirmationMessage = "컨디션 기록을 수정했어요."
            isSaving = false
            return updatedCheckIn
        } catch {
            errorMessage = "수정 내용을 저장하지 못했습니다. 잠시 후 다시 시도해 주세요."
            isSaving = false
            return nil
        }
    }

    private func makeUpdatedCheckIn() -> RecoveryCheckIn {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        return RecoveryCheckIn(
            id: originalCheckIn.id,
            date: originalCheckIn.date,
            fatigueLevel: fatigueLevel,
            sleepQuality: sleepQuality,
            muscleSoreness: muscleSoreness,
            moodLevel: moodLevel,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
    }
}

