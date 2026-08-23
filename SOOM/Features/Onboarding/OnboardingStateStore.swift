import Foundation

final class OnboardingStateStore {
    static let shared = OnboardingStateStore()

    private enum Key {
        static let hasCompletedOnboarding = "onboarding.hasCompleted"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var hasCompletedOnboarding: Bool {
        userDefaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    func markOnboardingCompleted() {
        userDefaults.set(true, forKey: Key.hasCompletedOnboarding)
    }
}
