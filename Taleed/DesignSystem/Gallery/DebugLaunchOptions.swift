#if DEBUG
import Foundation

/// Launch arguments that open a screen directly, for screenshots and UI checks (debug builds only):
///
///     -TaleedDebugTab profile                  select a tab (home, explore, sell, messages, profile)
///     -TaleedDebugProfilePath settings,designSystem   (settings, designSystem, developerMenu, favorites)
///     -TaleedDebugOpenURL /listings/42             open a link through the router once the shell shows
///     -TaleedGallerySection buttons            scroll the design-system gallery to a section
///     -TaleedGalleryLargeText YES              turn on the gallery's "Text 200 %" switch
///     -TaleedDebugSignIn YES                   open the sign-in sheet
///     -TaleedDebugLaunchScreen suspended       show a launch screen (updateRequired, suspended,
///                                              suspendedSession, launchError)
///     -TaleedDebugSignUp a1b2c3d4              open the sign-up sheet with a referral code
///     -TaleedDebugBetaMode YES                 act as if `GET /config` said `betaMode: true`
///     -TaleedDebugAppVersion 0.9.0             report another app version (the update screen)
///     -welcome_done NO                         show the welcome screen again
///     -TaleedDebugHomeFeed offline             Home's first feed request fails offline (then works);
///                                              `empty` answers an empty feed
///     -TaleedDebugSearchResults offline        the first search-results request fails offline (then works)
///     -TaleedDebugListing offline              the first listing-screen request fails offline (then works)
///     -TaleedDebugMember offline               the first profile request fails offline (then works)
///     -TaleedDebugFavorites offline            the first favorites request fails offline (then works);
///                                              `empty` answers no favorites
///     -TaleedDebugVisualSearch YES             show the photo-search button although `GET /config` has it
///                                              off (the API then answers `503 feature_disabled`)
///     -TaleedDebugSell upload                  the sell form's first photo upload fails offline (then works);
///                                              `publish`: the first publish fails offline
///
/// The language can be forced the same way with `-app_language ar`.
@MainActor
enum DebugLaunchOptions {
    private static var applied = false

    static var gallerySection: String? { UserDefaults.standard.string(forKey: "TaleedGallerySection") }

    static var galleryLargeText: Bool { UserDefaults.standard.bool(forKey: "TaleedGalleryLargeText") }

    /// A launch screen to show instead of the launch flow's answer.
    static var launchScreen: String? { UserDefaults.standard.string(forKey: "TaleedDebugLaunchScreen") }

    /// Home's feed for screenshots of its states: `offline` (first request only) or `empty`.
    static var homeFeed: String? { UserDefaults.standard.string(forKey: "TaleedDebugHomeFeed") }

    /// Request access instead of sign-up, as during the invite-only period.
    static var forcesBetaMode: Bool { UserDefaults.standard.bool(forKey: "TaleedDebugBetaMode") }

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
        if let code = defaults.string(forKey: "TaleedDebugSignUp") {
            router.authEntry = .signUp(referralCode: code)
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
        case "favorites": self = .favorites
        default: return nil
        }
    }
}
#endif
