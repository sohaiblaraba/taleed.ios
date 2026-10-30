import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import FirebaseMessaging
import Foundation
import UIKit

/// Firebase: Cloud Messaging for pushes (slice C), Crashlytics for crash reports (slice J) and Google Analytics
/// for usage statistics (`UsageAnalytics`).
///
/// It starts only when the build carries `GoogleService-Info.plist`, which a build script copies in from
/// `TALEED_FIREBASE_CONFIG_DIR` (it is never in the repository). Without it nothing starts: no push token, so
/// the app neither asks for the push permission nor registers, no crash reporting and no statistics.
@MainActor
enum FirebaseServices {
    /// The push token source, once Firebase is set up.
    private(set) static var pushTokens: FirebasePushTokenSource?
    /// Crashlytics, once Firebase is set up.
    private(set) static var crashReporter: CrashlyticsReporter?
    /// Google Analytics, once Firebase is set up.
    private(set) static var analytics: FirebaseAnalyticsBackend?

    /// Firebase is set up in this build. (Not `FirebaseApp.app()`, which logs an error before `configure()`.)
    private(set) static var isConfigured = false

    /// Called once, before anything else of the app starts (`TaleedApp.init`).
    static func configure(bundle: Bundle = .main) {
        guard !isConfigured, bundle.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
        isConfigured = true
        // At once, before Analytics acts on the choice it kept from an earlier build (a Staging build installed over
        // this Debug one, say); `UsageAnalytics` then applies the same rule.
        Analytics.setAnalyticsCollectionEnabled(UsageAnalytics.isBuildEnabled(bundle: bundle) && UsageAnalytics.isSwitchedOnOnDevice())
        // Info.plist says off (`FirebaseCrashlyticsCollectionEnabled`); each launch sets the build's choice
        // (`TALEED_CRASH_REPORTING`): on in Release and Staging, off in Debug.
        let sendsCrashReports = CrashReporting.isCollectionEnabled(bundle: bundle)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(sendsCrashReports)
        // A Debug build's crashes stay on the device: without this, the next Staging or Release build installed on
        // the same device would send them.
        if !sendsCrashReports { Crashlytics.crashlytics().deleteUnsentReports() }
        // Info.plist says off (`FIREBASE_ANALYTICS_COLLECTION_ENABLED`): `UsageAnalytics` turns it on in Release
        // and Staging builds, unless the member turned it off.
        pushTokens = FirebasePushTokenSource()
        crashReporter = CrashlyticsReporter()
        analytics = FirebaseAnalyticsBackend()
    }
}

/// The Firebase Cloud Messaging registration token. Firebase needs the APNs device token first: the first
/// request registers for remote notifications and waits for it (`AppDelegate` hands it over).
@MainActor
final class FirebasePushTokenSource: NSObject, PushTokenSource {
    /// A new token from Firebase (first one, or a rotation): `PushRegistration.tokenDidChange(_:)`.
    var onNewToken: ((String) -> Void)? {
        didSet {
            if let token = latestToken { onNewToken?(token) }
        }
    }

    private var hasAPNsToken = false
    private var waiters: [CheckedContinuation<Bool, Never>] = []
    private var latestToken: String?
    /// How long a token request waits for the APNs device token.
    private let apnsTimeout: Duration = .seconds(15)

    override init() {
        super.init()
        Messaging.messaging().delegate = self
    }

    func registrationToken() async -> String? {
        // Off in Info.plist, so that no token exists before the member allowed pushes; on from the first
        // request, so Firebase keeps the token fresh.
        Messaging.messaging().isAutoInitEnabled = true
        guard await waitForAPNsToken() else { return nil }
        do {
            let token = try await Messaging.messaging().token()
            latestToken = token
            return token
        } catch {
            return nil
        }
    }

    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        hasAPNsToken = true
        resumeWaiters(true)
    }

    /// `application(_:didFailToRegisterForRemoteNotificationsWithError:)`.
    func didFailToRegisterForRemoteNotifications() {
        resumeWaiters(false)
    }

    private func waitForAPNsToken() async -> Bool {
        if hasAPNsToken { return true }
        #if DEBUG && targetEnvironment(simulator)
        // `-TaleedDebugAPNsToken <hex>`: a simulator whose APNs connection is blocked gets no device token, so
        // no FCM token either. This stand-in lets it register (`POST /devices`) to check the device row; pushes
        // to it do not arrive (test them with `xcrun simctl push`).
        if let hex = UserDefaults.standard.string(forKey: "TaleedDebugAPNsToken"), let token = Data(hex: hex) {
            Messaging.messaging().setAPNSToken(token, type: .sandbox)
            hasAPNsToken = true
            return true
        }
        #endif
        let isFirst = waiters.isEmpty
        UIApplication.shared.registerForRemoteNotifications()
        if isFirst {
            Task { [weak self, apnsTimeout] in
                try? await Task.sleep(for: apnsTimeout)
                self?.resumeWaiters(self?.hasAPNsToken ?? false)
            }
        }
        return await withCheckedContinuation { waiters.append($0) }
    }

    private func resumeWaiters(_ result: Bool) {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume(returning: result) }
    }

    fileprivate func didReceive(token: String) {
        guard token != latestToken else { return }
        latestToken = token
        onNewToken?(token)
    }
}

extension FirebasePushTokenSource: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor [weak self] in self?.didReceive(token: fcmToken) }
    }
}

/// Crashlytics behind `CrashReporter`.
@MainActor
final class CrashlyticsReporter: CrashReporter {
    func setUserID(_ id: String?) {
        // An empty identifier clears it (Crashlytics' documented way).
        Crashlytics.crashlytics().setUserID(id ?? "")
    }

    func setCustomValue(_ value: String, forKey key: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }
}

/// Google Analytics behind `AnalyticsBackend`. Never `Analytics.setUserID`: statistics carry no member id.
@MainActor
final class FirebaseAnalyticsBackend: AnalyticsBackend {
    func setCollectionEnabled(_ isEnabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
    }

    func setUserProperty(_ value: String?, forName name: String) {
        Analytics.setUserProperty(value, forName: name)
    }

    func logScreenView(name: String, screenClass: String) {
        Analytics.logEvent(AnalyticsEventScreenView,
                           parameters: [AnalyticsParameterScreenName: name, AnalyticsParameterScreenClass: screenClass])
    }
}

#if DEBUG && targetEnvironment(simulator)
private extension Data {
    /// Bytes from hexadecimal text, such as `0a1b`; nil when the text is not an even run of hex digits.
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2), !hex.isEmpty else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
#endif
