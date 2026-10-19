#if DEBUG
import Foundation

/// Launch arguments that open a screen directly, for screenshots and UI checks (debug builds only):
///
///     -TaleedDebugTab profile                  select a tab (home, explore, sell, messages, profile)
///     -TaleedDebugProfilePath settings,designSystem   (settings, designSystem, developerMenu)
///     -TaleedDebugOpenURL /listings/42             open a link through the router once the shell shows
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

    static func apply(to router: AppRouter) {
        guard !applied else { return }
        applied = true
        let defaults = UserDefaults.standard
        if let tab = defaults.string(forKey: "TaleedDebugTab"), let appTab = AppTab(rawValue: tab) {
            router.selectedTab = appTab
        }
        if let path = defaults.string(forKey: "TaleedDebugProfilePath") {
            router.pathBinding(.profile).wrappedValue = path.split(separator: ",").compactMap { AppRoute(debugName: String($0)) }
        }
        if defaults.bool(forKey: "TaleedDebugSignIn") {
            router.presentSignIn()
        }
        if let link = defaults.string(forKey: "TaleedDebugOpenURL") {
            router.open(LinkRouter.destination(for: link))
        }
    }
}

private extension AppRoute {
    init?(debugName: String) {
        switch debugName {
        case "settings": self = .settings
        case "designSystem": self = .designSystem
        case "developerMenu": self = .developerMenu
        default: return nil
        }
    }
}
#endif
