import UIKit

/// The APNs device token, which Firebase Cloud Messaging needs before it hands out its own token (the
/// Firebase app delegate proxy is off: `FirebaseAppDelegateProxyEnabled` in Info.plist).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        FirebaseServices.pushTokens?.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        FirebaseServices.pushTokens?.didFailToRegisterForRemoteNotifications()
    }
}
