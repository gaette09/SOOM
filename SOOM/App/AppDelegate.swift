import UIKit
import UserNotifications

/// Batch 2 of the APNs notification infrastructure. Only handles the
/// registration callbacks — `onDidReceiveDeviceToken` just logs for now.
/// Batch 3 (device token storage) replaces that closure with a call that
/// upserts the token into `device_tokens`, so the callback shape is
/// injectable rather than hardcoded here.
///
/// Batch 5 adds `UNUserNotificationCenterDelegate`: `willPresent` shows
/// the standard system banner even while the app is foregrounded (no
/// suppression), and `didReceive response:` is the tap-to-deep-link entry
/// point. The delegate is registered in `didFinishLaunchingWithOptions` —
/// as early as possible, since a cold launch caused by tapping a
/// notification needs the delegate in place before iOS delivers the tap.
final class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    var onDidReceiveDeviceToken: (Data) -> Void = { token in
        let hex = token.map { String(format: "%02x", $0) }.joined()
        print("[AppDelegate] APNs device token: \(hex)")
    }
    var onDidFailToRegister: (Error) -> Void = { error in
        print("[AppDelegate] APNs registration failed: \(error.localizedDescription)")
    }
    var onDidReceiveNotificationTap: (UUID) -> Void = { _ in }
    /// A tap that arrived before SOOMApp's `.task` had a chance to replace
    /// `onDidReceiveNotificationTap` with something that actually routes
    /// it — most notably a cold launch, where iOS can deliver the tap
    /// before the SwiftUI view hierarchy (and its `.task` modifiers) has
    /// run at all. SOOMApp checks this once it's ready, mirroring
    /// `DeviceTokenReceiptHandler`'s token-arrives-before-login-confirms
    /// handling from batch 3.
    private(set) var pendingNotificationPostId: UUID?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        onDidReceiveDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        onDidFailToRegister(error)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let postIdString = response.notification.request.content.userInfo["post_id"] as? String,
           let postId = UUID(uuidString: postIdString) {
            pendingNotificationPostId = postId
            onDidReceiveNotificationTap(postId)
        }
        completionHandler()
    }
}
