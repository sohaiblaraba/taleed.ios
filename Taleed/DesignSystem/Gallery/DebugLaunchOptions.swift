#if DEBUG
import Foundation

/// Launch arguments that open a screen directly, for screenshots and UI checks (debug builds only):
///
///     -TaleedDebugTab profile                  select a tab (home, explore, sell, messages, profile)
///     -TaleedDebugProfilePath settings,designSystem   (settings, designSystem, developerMenu, favorites,
///                                              myListings, orders, wallet, notifications, referrals…)
///     -TaleedDebugOpenURL /listings/42             open a link through the router once the launch ends
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
///     -TaleedDebugSearchFilters YES            search results open their filters sheet (screenshots)
///     -TaleedDebugListing offline              the first listing-screen request fails offline (then works)
///     -TaleedDebugMember offline               the first profile request fails offline (then works)
///     -TaleedDebugFavorites offline            the first favorites request fails offline (then works);
///                                              `empty` answers no favorites
///     -TaleedDebugVisualSearch YES             show the photo-search button although `GET /config` has it
///                                              off (the API then answers `503 feature_disabled`)
///     -TaleedDebugIdentityAiReview YES         act as if `features.identityAiReview` were on: identity
///                                              verification shows the OpenAI consent step (slice I)
///     -TaleedDebugSell upload                  the sell form's first photo upload fails offline (then works);
///                                              `upload-refused`: it fails as too large (413);
///                                              `publish`: the first publish (or edit save) fails offline
///     -TaleedDebugMyListings offline           the first My listings request fails offline (then works)
///     -TaleedDebugEditListing offline          the edit form's first load fails offline (then works)
///     -TaleedDebugInbox offline                the inbox's first request fails offline (then works);
///                                              `empty` answers an empty inbox
///     -TaleedDebugConversation offline         the first conversation load fails offline (then works)
///     -TaleedDebugSend lost                    the first message is posted but its answer is lost (the
///                                              stream or "Réessayer" confirms it, same clientId); `offline`:
///                                              it fails before leaving, "Non envoyé" until "Réessayer"
///     -TaleedDebugCheckout offline             checkout's first load fails offline (then works)
///     -TaleedDebugOrderPayment offline         the payment screen's first sync fails offline (then works)
///     -TaleedDebugOrder offline                the order screen's first load fails offline (then works)
///                                              `carrier`: the first "Bordereau d'expédition" is refused
///                                              by the carrier (`502 carrier_error` with a `detail`)
///     -TaleedDebugOrders offline               the orders list's first page fails offline (then works);
///                                              `empty` answers no orders
///     -TaleedDebugWallet offline               Earnings' first load fails offline (then works)
///     -TaleedDebugNotifications offline        the notifications' first page fails offline (then works);
///                                              `empty` answers no notifications; `hidden`: a first page
///                                              without rows that has a next page (the real first page)
///     -TaleedDebugSettings offline             the first load of the settings hub's account rows, the
///                                              profile form, the addresses and the blocked members each
///                                              fail offline once (then work); `newsletter`: the first
///                                              newsletter change fails offline (the switch flips back);
///                                              `offline,newsletter`: both
///     -TaleedDebugDelete unauthorized          deleting the account answers `401` without calling the
///                                              API (the retry after a lost answer): the signed-out Home
///     -TaleedDebugVerification offline         identity verification's first load fails offline (then
///                                              works); `upload`: the first ID upload fails offline;
///                                              `limit`: the first send answers 429 (an hour to wait)
///     -TaleedDebugReferrals offline            the referral screen's first load fails offline (then works)
///     -TaleedDebugReport offline               the first report fails offline before it is sent (then
///                                              works); `limit`: it answers 429 (an hour to wait);
///                                              `upload`: the first screenshot upload fails offline
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

    /// `-TaleedDebugSocialFinish <email>`: the sign-in sheet opens on the finish step of a Google or Apple
    /// sign-up for that email, with a made-up token (slice G). Sending it answers `social_signup_expired`.
    static var socialFinishEmail: String? { UserDefaults.standard.string(forKey: "TaleedDebugSocialFinish") }

    /// `-TaleedDebugNoPassword YES`: `GET /me` reads `hasPassword` false, for the settings of a member who
    /// signed up with Google or Apple (slice G). The server still knows the real answer.
    static var forcesNoPassword: Bool { UserDefaults.standard.bool(forKey: "TaleedDebugNoPassword") }

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
    static let debugNames: [String: AppRoute] = [
        "settings": .settings, "designSystem": .designSystem, "developerMenu": .developerMenu, "favorites": .favorites,
        "myListings": .myListings, "orders": .orders, "wallet": .wallet, "notifications": .notifications,
        "profileSettings": .profileSettings, "usernameSettings": .usernameSettings, "emailSettings": .emailSettings,
        "passwordSettings": .passwordSettings, "addresses": .addresses, "blockedMembers": .blockedMembers, "help": .help,
        "deleteAccount": .deleteAccount, "identityVerification": .identityVerification, "referrals": .referrals,
    ]

    init?(debugName: String) {
        guard let route = Self.debugNames[debugName] else { return nil }
        self = route
    }
}
#endif
