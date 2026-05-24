import Foundation

final class SettingsViewModel: ObservableObject {
    @Published private(set) var settings: TrainingSettings
    @Published var maxHeartRateText: String
    @Published var cyclingFTPText: String
    @Published private(set) var errorMessage: String?

    private let store: TrainingSettingsStore

    init(store: TrainingSettingsStore = .shared) {
        self.store = store
        let settings = store.loadSettings()
        self.settings = settings
        self.maxHeartRateText = settings.maxHeartRate.map(String.init) ?? ""
        self.cyclingFTPText = settings.cyclingFTP.map(String.init) ?? ""
    }

    func load() {
        let loaded = store.loadSettings()
        settings = loaded
        maxHeartRateText = loaded.maxHeartRate.map(String.init) ?? ""
        cyclingFTPText = loaded.cyclingFTP.map(String.init) ?? ""
        errorMessage = nil
    }

    @discardableResult
    func saveMaxHeartRate() -> Bool {
        guard let value = validatedOptionalInt(
            text: maxHeartRateText,
            range: 80...230,
            message: "최대 심박은 80~230 사이로 입력해주세요."
        ) else {
            return false
        }

        settings.maxHeartRate = value
        store.saveMaxHeartRate(value)
        errorMessage = nil
        return true
    }

    @discardableResult
    func saveCyclingFTP() -> Bool {
        guard let value = validatedOptionalInt(
            text: cyclingFTPText,
            range: 50...500,
            message: "FTP는 50~500W 사이로 입력해주세요."
        ) else {
            return false
        }

        settings.cyclingFTP = value
        store.saveCyclingFTP(value)
        errorMessage = nil
        return true
    }

    func updatePreferredUnit(_ value: TrainingPreferredUnit) {
        settings.preferredUnit = value
        store.savePreferredUnit(value)
        errorMessage = nil
    }

    func updatePrivacyDefault(_ value: ShareableWorkoutVisibility) {
        settings.privacyDefault = value
        store.savePrivacyDefault(value)
        errorMessage = nil
    }

    private func validatedOptionalInt(
        text: String,
        range: ClosedRange<Int>,
        message: String
    ) -> Int?? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .some(nil) }
        guard let value = Int(trimmed), range.contains(value) else {
            errorMessage = message
            return nil
        }
        return .some(value)
    }
}
