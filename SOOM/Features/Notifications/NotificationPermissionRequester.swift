import UIKit
import UserNotifications

protocol NotificationPermissionRequesting {
    func requestAuthorization() async
}

/// Requests local notification permission, then registers for remote
/// (APNs) notifications only if the user granted it — registering without
/// permission just wastes a round trip to Apple's servers for a token the
/// app can't use yet. `registerForRemoteNotifications` is injected (rather
/// than calling `UIApplication.shared` directly) so this stays testable and
/// so the call can be dispatched to the main actor, which UIKit requires.
final class NotificationPermissionRequester: NotificationPermissionRequesting {
    private let notificationCenter: UNUserNotificationCenter
    private let registerForRemoteNotifications: @MainActor () -> Void

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        registerForRemoteNotifications: @escaping @MainActor () -> Void = {
            UIApplication.shared.registerForRemoteNotifications()
        }
    ) {
        self.notificationCenter = notificationCenter
        self.registerForRemoteNotifications = registerForRemoteNotifications
    }

    func requestAuthorization() async {
        let granted = (try? await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else { return }
        await registerForRemoteNotifications()
    }
}
