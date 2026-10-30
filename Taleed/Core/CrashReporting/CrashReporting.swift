import Foundation

/// The crash reporting service (Crashlytics in the app, a fake in tests).
@MainActor
protocol CrashReporter: AnyObject {
    /// The member's `id`, or nil to clear it.
    func setUserID(_ id: String?)
    func setCustomValue(_ value: String, forKey key: String)
}

/// What crash reports say about the member (slice J, App behaviour 2): the member's `id` while signed in,
/// nothing once signed out or deleted. Never a name, email address or phone number: the privacy policy says
/// the crash reporting service does not receive them. The custom keys are not personal: the app's language
/// and appearance.
@MainActor
final class CrashReporting {
    enum Key {
        static let language = "app_language"
        static let appearance = "app_appearance"
    }

    private let reporter: CrashReporter?

    /// No reporter: a build without Firebase, where every call does nothing.
    init(reporter: CrashReporter?) {
        self.reporter = reporter
    }

    /// A sign-in, a sign-up, or launch with a stored session.
    func sessionDidStart(memberId: String?) {
        reporter?.setUserID(memberId)
    }

    /// Sign-out, a rejected session or account deletion.
    func sessionDidEnd() {
        reporter?.setUserID(nil)
    }

    func languageDidChange(_ language: AppLanguage) {
        reporter?.setCustomValue(language.rawValue, forKey: Key.language)
    }

    func appearanceDidChange(_ appearance: AppAppearance) {
        reporter?.setCustomValue(appearance.rawValue, forKey: Key.appearance)
    }

    /// Whether crash reports leave the device in this build (`TaleedCrashReporting` in Info.plist, from
    /// `TALEED_CRASH_REPORTING`): on in Release and Staging, off in Debug.
    nonisolated static func isCollectionEnabled(bundle: Bundle = .main) -> Bool {
        (bundle.object(forInfoDictionaryKey: "TaleedCrashReporting") as? String)?.uppercased() == "YES"
    }
}
