import UIKit
import HealthKit
import UserNotifications

/// Routes notification registration and taps to handlers installed by SOOMApp.
/// Device tokens are never logged. Register the notification delegate early
/// so a cold-launch tap can be retained until authentication finishes.
final class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    private let healthStore = HKHealthStore()
    private var healthObservers: [HKObserverQuery] = []
    private var pendingHealthCompletions: [() -> Void] = []
    private var pendingGoogleHealthCompletions: [(UIBackgroundFetchResult) -> Void] = []
    var onHealthWorkoutUpdate: ((@escaping () -> Void) -> Void)? {
        didSet {
            guard let onHealthWorkoutUpdate else { return }
            let pending = pendingHealthCompletions
            pendingHealthCompletions.removeAll()
            pending.forEach(onHealthWorkoutUpdate)
        }
    }
    var onGoogleHealthEvent: ((@escaping (UIBackgroundFetchResult) -> Void) -> Void)? {
        didSet {
            guard let onGoogleHealthEvent else { return }
            let pending = pendingGoogleHealthCompletions
            pendingGoogleHealthCompletions.removeAll()
            pending.forEach(onGoogleHealthEvent)
        }
    }

    private var pendingDeviceToken: Data?
    private var pendingRegistrationError: Error?
    var onDidReceiveDeviceToken: ((Data) -> Void)? {
        didSet {
            if let handler = onDidReceiveDeviceToken, let token = pendingDeviceToken {
                pendingDeviceToken = nil; handler(token)
            }
        }
    }
    var onDidFailToRegister: ((Error) -> Void)? {
        didSet {
            if let handler = onDidFailToRegister, let error = pendingRegistrationError {
                pendingRegistrationError = nil; handler(error)
            }
        }
    }
    var onDidReceiveNotificationTap: (UUID) -> Void = { _ in }
    @MainActor var eventCanPresent: ((EventPush) -> Bool)?
    @MainActor var eventReceived: ((EventPush, Bool) -> Void)?
    var nativePushReceived: ((NativeActivityPushPayload) -> Void)?
    private var pendingNativePush: NativeActivityPushPayload?
    func consumePendingNativePush() -> NativeActivityPushPayload? { defer {pendingNativePush=nil};return pendingNativePush }
    private var pendingEventTap: EventPush?
    func consumePendingEventTap() -> EventPush? { defer {pendingEventTap=nil}; return pendingEventTap }
    var onDidReceivePushTap: ((NotificationPushPayload) -> Void)?
    @MainActor var shouldPresentRemotePush: (@MainActor (NotificationPushPayload) -> Bool)?
    @MainActor var onDidReceiveVisiblePush: (@MainActor () -> Void)?

    @MainActor
    func foregroundPresentationOptions(for userInfo: [AnyHashable: Any],
                                       isRemotePush: Bool) -> UNNotificationPresentationOptions {
        // Native preview foreground banners remain suppressed until fresh server validation.
        if isRemotePush, userInfo["source_kind"] as? String == "activity_native_v1" { return [] }
        if isRemotePush, let event=EventPush(userInfo:userInfo) {
            guard eventCanPresent?(event) == true else {return []}
            eventReceived?(event,false)
            return [.banner,.sound]
        }
        return foregroundPresentationOptions(payload: NotificationPushPayload(userInfo: userInfo),
                                      isRemotePush: isRemotePush)
    }

    @MainActor
    private func foregroundPresentationOptions(payload: NotificationPushPayload?,
                                               isRemotePush: Bool) -> UNNotificationPresentationOptions {
        // Already accepted notifications can arrive after account/session changes.
        // Local HealthKit import alerts keep their existing presentation behavior.
        if isRemotePush {
            guard let payload, shouldPresentRemotePush?(payload) == true else { return [] }
            onDidReceiveVisiblePush?()
            // A queued APNs badge snapshot may predate reads on another device.
            // Foreground uses the exact fresh count rather than replaying it.
            return [.banner, .sound]
        }
        return [.banner, .sound, .badge]
    }

    private var pendingPushTap:NotificationPushPayload?
    func consumePendingPushTap() -> NotificationPushPayload? { defer { pendingPushTap=nil };return pendingPushTap }
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
        registerHealthWorkoutObserver()
        return true
    }

    private func registerHealthWorkoutObserver() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        for workoutType: HKSampleType in [HKWorkoutType.workoutType(), HKSeriesType.workoutRoute()] {
            let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completion, _ in
                Task { @MainActor in
                    guard let self else { completion(); return }
                    if let handler = self.onHealthWorkoutUpdate {
                        handler(completion)
                    } else {
                        self.pendingHealthCompletions.append(completion)
                    }
                }
            }
            healthObservers.append(query)
            healthStore.execute(query)
            healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { _, _ in }
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        pendingRegistrationError = nil
        if let onDidReceiveDeviceToken { onDidReceiveDeviceToken(deviceToken) }
        else { pendingDeviceToken = deviceToken }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        pendingDeviceToken = nil
        if let onDidFailToRegister { onDidFailToRegister(error) }
        else { pendingRegistrationError = error }
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard userInfo["soom_google_health_event"] as? Bool == true else {
            completionHandler(.noData)
            return
        }
        if let handler = onGoogleHealthEvent { handler(completionHandler) }
        else { pendingGoogleHealthCompletions.append(completionHandler) }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let isRemotePush = notification.request.trigger is UNPushNotificationTrigger
        let payload = NotificationPushPayload(userInfo: notification.request.content.userInfo)
        Task { @MainActor [weak self] in
            completionHandler(self?.foregroundPresentationOptions(for: notification.request.content.userInfo, isRemotePush: isRemotePush) ?? [])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if info["source_kind"] as? String == "activity_native_v1" {
            if let native=NativeActivityPushPayload(userInfo: info) {
                if let nativePushReceived {nativePushReceived(native)} else {pendingNativePush=native}
            }
        } else if let event=EventPush(userInfo:info) {
            if let eventReceived {eventReceived(event,true)} else {pendingEventTap=event}
        } else if let payload=NotificationPushPayload(userInfo:response.notification.request.content.userInfo) {
            if let onDidReceivePushTap { onDidReceivePushTap(payload) }
            else { pendingPushTap=payload }
        }
        completionHandler()
    }
}
