import UIKit
import UserNotifications

protocol NotificationPermissionRequesting {
    func requestAuthorization() async
    func reregisterIfAlreadyAuthorized() async
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

    /// Apple's documented pattern: call registerForRemoteNotifications()
    /// every time the app finishes launching, not just the first time
    /// permission is granted — the device token can rotate, and this app
    /// only ever asks for permission once (Settings' "알림 허용하기" row),
    /// so without this a token refresh would otherwise never reach
    /// AppDelegate on a plain app restart. No-ops silently if the user
    /// hasn't granted permission.
    func reregisterIfAlreadyAuthorized() async {
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        await registerForRemoteNotifications()
    }
}
