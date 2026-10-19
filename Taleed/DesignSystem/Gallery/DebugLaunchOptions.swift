#if DEBUG
import Foundation

/// Launch arguments that open a screen directly, for screenshots and UI checks (debug builds only):
///
///     -TaleedDebugTab profile                  select a tab (home, explore, sell, messages, profile)
///     -TaleedDebugProfilePath settings,designSystem
///     -TaleedGallerySection buttons            scroll the design-system gallery to a section
///     -TaleedGalleryLargeText YES              turn on the gallery's "Text 200 %" switch
///     -TaleedDebugSignIn YES                   open the sign-in sheet
///     -TaleedDebugLaunchScreen suspended       show a launch screen (updateRequired, suspended)
///
/// The language can be forced the same way with `-app_language ar`.
@MainActor
enum DebugLaunchOptions {
    private static var applied = false

    static var gallerySection: String? { UserDefaults.standard.string(forKey: "TaleedGallerySection") }

    static var galleryLargeText: Bool { UserDefaults.standard.bool(forKey: "TaleedGalleryLargeText") }

    /// A launch screen to show instead of the launch flow's answer.
    static var launchScreen: String? { UserDefaults.standard.string(forKey: "TaleedDebugLaunchScreen") }

    static func apply(to router: ShellRouter) {
        guard !applied else { return }
        applied = true
        let defaults = UserDefaults.standard
        if let tab = defaults.string(forKey: "TaleedDebugTab"), let shellTab = ShellTab(debugName: tab) {
            router.selectedTab = shellTab
        }
        if let path = defaults.string(forKey: "TaleedDebugProfilePath") {
            router.profilePath = path.split(separator: ",").compactMap { ProfileRoute(debugName: String($0)) }
        }
        if defaults.bool(forKey: "TaleedDebugSignIn") {
            router.isSignInPresented = true
        }
    }
}

private extension ShellTab {
    init?(debugName: String) {
        guard let tab = Self.allCases.first(where: { "\($0)" == debugName }) else { return nil }
        self = tab
    }
}

private extension ProfileRoute {
    init?(debugName: String) {
        switch debugName {
        case "settings": self = .settings
        case "designSystem": self = .designSystem
        default: return nil
        }
    }
}
#endif
