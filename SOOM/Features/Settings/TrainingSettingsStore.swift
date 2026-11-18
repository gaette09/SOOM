import Foundation

final class TrainingSettingsStore {
    static private(set) var shared = TrainingSettingsStore()

    /// Existing instances retain their original scope across delayed saves.
    static func selectAccount(_ userID: UUID?) {
        shared = TrainingSettingsStore(userID: userID)
    }

    /// Swaps only the selected store; retained views keep their original scope.
    static func useDemoScope(_ store: TrainingSettingsStore) { shared = store }

    private enum Key {
        static let maxHeartRate = "training.maxHeartRate"
        static let cyclingFTP = "training.cyclingFTP"
        static let preferredUnit = "training.preferredUnit"
        static let privacyDefault = "training.privacyDefault"
    }

    private let userDefaults: UserDefaults
    private let keyPrefix: String

    init(userDefaults: UserDefaults = .standard, userID: UUID? = nil) {
        self.userDefaults = userDefaults
        self.keyPrefix = userID.map { "account." + $0.uuidString.lowercased() + "." } ?? ""
    }

    func loadSettings() -> TrainingSettings {
        TrainingSettings(
            maxHeartRate: optionalInt(forKey: scoped(Key.maxHeartRate)),
            cyclingFTP: optionalInt(forKey: scoped(Key.cyclingFTP)),
            preferredUnit: TrainingPreferredUnit(rawValue: userDefaults.string(forKey: scoped(Key.preferredUnit)) ?? "") ?? .metric,
            privacyDefault: ShareableWorkoutVisibility(rawValue: userDefaults.string(forKey: scoped(Key.privacyDefault)) ?? "") ?? .privateOnly
        )
    }

    func saveSettings(_ settings: TrainingSettings) {
        saveOptionalInt(settings.maxHeartRate, forKey: scoped(Key.maxHeartRate))
        saveOptionalInt(settings.cyclingFTP, forKey: scoped(Key.cyclingFTP))
        userDefaults.set(settings.preferredUnit.rawValue, forKey: scoped(Key.preferredUnit))
        userDefaults.set(settings.privacyDefault.rawValue, forKey: scoped(Key.privacyDefault))
        NotificationCenter.default.post(name: ActivityLoadRules.changed, object: nil)
    }

    func loadZoneBaseline() -> PersonalizedZoneBaseline {
        PersonalizedZoneBaseline(
            maxHeartRate: optionalInt(forKey: scoped(Key.maxHeartRate)),
            cyclingFTP: optionalInt(forKey: scoped(Key.cyclingFTP))
        )
    }

    func hasAnySavedTrainingSetting() -> Bool {
        [
            scoped(Key.maxHeartRate),
            scoped(Key.cyclingFTP),
            scoped(Key.preferredUnit),
            scoped(Key.privacyDefault)
        ].contains { userDefaults.object(forKey: $0) != nil }
    }

    func saveMaxHeartRate(_ value: Int?) {
        saveOptionalInt(value, forKey: scoped(Key.maxHeartRate))
        NotificationCenter.default.post(name: ActivityLoadRules.changed, object: nil)
    }

    func saveCyclingFTP(_ value: Int?) {
        saveOptionalInt(value, forKey: scoped(Key.cyclingFTP))
    }

    func savePreferredUnit(_ value: TrainingPreferredUnit) {
        userDefaults.set(value.rawValue, forKey: scoped(Key.preferredUnit))
    }

    func savePrivacyDefault(_ value: ShareableWorkoutVisibility) {
        userDefaults.set(value.rawValue, forKey: scoped(Key.privacyDefault))
    }

    func resetAll() {
        userDefaults.removeObject(forKey: scoped(Key.maxHeartRate))
        userDefaults.removeObject(forKey: scoped(Key.cyclingFTP))
        userDefaults.removeObject(forKey: scoped(Key.preferredUnit))
        userDefaults.removeObject(forKey: scoped(Key.privacyDefault))
        NotificationCenter.default.post(name: ActivityLoadRules.changed, object: nil)
    }

    private func scoped(_ key: String) -> String { keyPrefix + key }

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
