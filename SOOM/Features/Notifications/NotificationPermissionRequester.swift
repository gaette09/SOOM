import UIKit
import UserNotifications

protocol NotificationPermissionRequesting {
    func requestAuthorization() async
    func registerForBackgroundUpdates() async
    func refreshPermissionStatus() async
}

extension NotificationPermissionRequesting { func refreshPermissionStatus() async {} }

/// Visible alerts require user authorization. Silent health-change pushes use
/// APNs registration independently, even if the user declines visible alerts.
/// The UIKit call is injected so it can run on the main actor in tests.
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
        guard await MainActor.run(body: { !ReviewDemoMode.isActive }) else { return }
        let granted = (try? await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        await refreshPermissionStatus()
        guard granted else { return }
        await registerForRemoteNotifications()
    }

    /// Register at launch for silent background updates and token rotation.
    /// This does not request or enable visible notification permission.
    func refreshPermissionStatus() async {
        let settings = await notificationCenter.notificationSettings()
        await MainActor.run {
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: PushRegistrationStatus.shared.permission = .allowed
            case .denied: PushRegistrationStatus.shared.permission = .denied
            case .notDetermined: PushRegistrationStatus.shared.permission = .notDetermined
            @unknown default: PushRegistrationStatus.shared.permission = .unknown
            }
        }
    }

    func registerForBackgroundUpdates() async {
        await refreshPermissionStatus()
        guard await MainActor.run(body: { !ReviewDemoMode.isActive }) else { return }
        await registerForRemoteNotifications()
    }
}
