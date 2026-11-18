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
    #if DEBUG && targetEnvironment(simulator)
    @Published private(set) var syntheticSaveAttempts = 0
    #endif
    @Published private(set) var confirmationMessage: String?
    @Published private(set) var errorMessage: String?

    private var lastSavedInput: RecoveryCheckIn?
    private var pendingInput: RecoveryCheckIn?

    private var presentationGeneration = UUID()
    func stopPresenting() { presentationGeneration = UUID(); isSaving = false }

    private let store: any RecoveryCheckInWritableStore
    private let now: () -> Date

    init(
        store: any RecoveryCheckInWritableStore = MockRecoveryCheckInStore.shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.now = now
    }

    private func matchesInput(_ value: RecoveryCheckIn) -> Bool {
        value.fatigueLevel == fatigueLevel && value.sleepQuality == sleepQuality
            && value.muscleSoreness == muscleSoreness && value.moodLevel == moodLevel
            && (value.note ?? "") == note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var hasSavedCurrentInput: Bool {
        lastSavedInput.map { Calendar.current.isDate($0.date, inSameDayAs: now()) && matchesInput($0) } ?? false
    }
    func refreshForCurrentDay() {
        if let lastSavedInput, !Calendar.current.isDate(lastSavedInput.date, inSameDayAs: now()) {
            self.lastSavedInput = nil; confirmationMessage = nil
        }
    }
    var canSave: Bool { !isSaving && !hasSavedCurrentInput }

    func save() async {
        guard canSave else { return }

        let generation = presentationGeneration
        isSaving = true
        #if DEBUG && targetEnvironment(simulator)
        syntheticSaveAttempts += 1
        #endif
        errorMessage = nil
        confirmationMessage = nil

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let checkIn = pendingInput.flatMap { matchesInput($0) ? $0 : nil } ?? RecoveryCheckIn(
            date: now(),
            fatigueLevel: fatigueLevel,
            sleepQuality: sleepQuality,
            muscleSoreness: muscleSoreness,
            moodLevel: moodLevel,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )

        pendingInput = checkIn
        do {
            try await store.saveCheckIn(checkIn)
            guard generation == presentationGeneration, !Task.isCancelled else { return }
            lastSavedInput = checkIn
            pendingInput = nil
            confirmationMessage = "오늘의 회복 해석이 더 정확해졌어요."
        } catch {
            guard generation == presentationGeneration, !Task.isCancelled else { return }
            errorMessage = "기록하지 못했습니다. 잠시 후 다시 시도해 주세요."
        }

        isSaving = false
    }
}
