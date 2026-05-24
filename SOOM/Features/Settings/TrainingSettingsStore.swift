import Foundation

final class TrainingSettingsStore {
    static let shared = TrainingSettingsStore()

    private enum Key {
        static let maxHeartRate = "training.maxHeartRate"
        static let cyclingFTP = "training.cyclingFTP"
        static let preferredUnit = "training.preferredUnit"
        static let privacyDefault = "training.privacyDefault"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadSettings() -> TrainingSettings {
        TrainingSettings(
            maxHeartRate: optionalInt(forKey: Key.maxHeartRate),
            cyclingFTP: optionalInt(forKey: Key.cyclingFTP),
            preferredUnit: TrainingPreferredUnit(rawValue: userDefaults.string(forKey: Key.preferredUnit) ?? "") ?? .metric,
            privacyDefault: ShareableWorkoutVisibility(rawValue: userDefaults.string(forKey: Key.privacyDefault) ?? "") ?? .privateOnly
        )
    }

    func saveSettings(_ settings: TrainingSettings) {
        saveOptionalInt(settings.maxHeartRate, forKey: Key.maxHeartRate)
        saveOptionalInt(settings.cyclingFTP, forKey: Key.cyclingFTP)
        userDefaults.set(settings.preferredUnit.rawValue, forKey: Key.preferredUnit)
        userDefaults.set(settings.privacyDefault.rawValue, forKey: Key.privacyDefault)
    }

    func saveMaxHeartRate(_ value: Int?) {
        saveOptionalInt(value, forKey: Key.maxHeartRate)
    }

    func saveCyclingFTP(_ value: Int?) {
        saveOptionalInt(value, forKey: Key.cyclingFTP)
    }

    func savePreferredUnit(_ value: TrainingPreferredUnit) {
        userDefaults.set(value.rawValue, forKey: Key.preferredUnit)
    }

    func savePrivacyDefault(_ value: ShareableWorkoutVisibility) {
        userDefaults.set(value.rawValue, forKey: Key.privacyDefault)
    }

    private func optionalInt(forKey key: String) -> Int? {
        guard userDefaults.object(forKey: key) != nil else { return nil }
        return userDefaults.integer(forKey: key)
    }

    private func saveOptionalInt(_ value: Int?, forKey key: String) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
}
