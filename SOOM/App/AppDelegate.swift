import UIKit

/// Batch 2 of the APNs notification infrastructure. Only handles the
/// registration callbacks — `onDidReceiveDeviceToken` just logs for now.
/// Batch 3 (device token storage) replaces that closure with a call that
/// upserts the token into `device_tokens`, so the callback shape is
/// injectable rather than hardcoded here.
final class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    var onDidReceiveDeviceToken: (Data) -> Void = { token in
        let hex = token.map { String(format: "%02x", $0) }.joined()
        print("[AppDelegate] APNs device token: \(hex)")
    }
    var onDidFailToRegister: (Error) -> Void = { error in
        print("[AppDelegate] APNs registration failed: \(error.localizedDescription)")
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
