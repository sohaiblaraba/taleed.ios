import Foundation
import Observation

/// The analytics service (Google Analytics for Firebase in the app, a fake in tests).
@MainActor
protocol AnalyticsBackend: AnyObject {
    func setCollectionEnabled(_ isEnabled: Bool)
    func setUserProperty(_ value: String?, forName name: String)
}

/// Usage statistics: Google Analytics for Firebase with its automatic events only (first_open,
/// session_start, screen_view, app_update…), no event of the app's own.
///
/// - Collection is on in Release and Staging builds (`TALEED_ANALYTICS`), off in Debug, and off whenever the
///   member turned the Settings switch off. The switch is on by default, kept on the device, and applies at once.
/// - No member `id`, never a user ID, and no personal data in user properties: only `build_type` (debug,
///   staging, release) and `app_language`.
/// - No advertising identifier: the app links `FirebaseAnalyticsCore` (no IDFA, no AdSupport), ad
///   personalization signals are off in Info.plist, and the app never shows the tracking prompt.
@MainActor
@Observable
final class UsageAnalytics {
    enum Property {
        static let buildType = "build_type"
        static let language = "app_language"
    }

    nonisolated static let switchKey = "analytics_switched_on"

    /// The member's choice on this device: true unless they turned statistics off in Settings.
    private(set) var isSwitchedOn: Bool

    @ObservationIgnored private let backend: AnalyticsBackend?
    @ObservationIgnored private let isBuildEnabled: Bool
    @ObservationIgnored private let defaults: UserDefaults

    /// `backend` nil: a build without Firebase, where nothing is collected.
    init(backend: AnalyticsBackend?, isBuildEnabled: Bool, buildType: String, language: AppLanguage,
         defaults: UserDefaults = .standard) {
        self.backend = backend
        self.isBuildEnabled = isBuildEnabled
        self.defaults = defaults
        isSwitchedOn = Self.isSwitchedOnOnDevice(defaults)
        backend?.setCollectionEnabled(isCollecting)
        backend?.setUserProperty(buildType, forName: Property.buildType)
        backend?.setUserProperty(language.rawValue, forName: Property.language)
    }

    /// Whether statistics leave the device now.
    var isCollecting: Bool { backend != nil && isBuildEnabled && isSwitchedOn }

    /// The Settings switch.
    func setSwitchedOn(_ isOn: Bool) {
        isSwitchedOn = isOn
        defaults.set(isOn, forKey: Self.switchKey)
        backend?.setCollectionEnabled(isCollecting)
    }

    func languageDidChange(_ language: AppLanguage) {
        backend?.setUserProperty(language.rawValue, forName: Property.language)
    }

    /// The member's choice kept on the device: on unless they turned it off.
    nonisolated static func isSwitchedOnOnDevice(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: switchKey) as? Bool ?? true
    }

    /// Whether this build collects statistics (`TaleedAnalytics` in Info.plist, from `TALEED_ANALYTICS`).
    nonisolated static func isBuildEnabled(bundle: Bundle = .main) -> Bool {
        (bundle.object(forInfoDictionaryKey: "TaleedAnalytics") as? String)?.uppercased() == "YES"
    }

    /// `debug`, `staging` or `release` (`TaleedBuildType` in Info.plist, from `TALEED_BUILD_TYPE`).
    nonisolated static func buildType(bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: "TaleedBuildType") as? String) ?? "release"
    }
}
