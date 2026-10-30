import Foundation
@testable import Taleed
import Testing

@MainActor
struct ScreenTrackingTests {
    /// plan/analytics-screens.md, "Screens (43)", in its order. Android uses the same names.
    private static let sharedList = [
        "update_required", "welcome", "sign_in", "sign_up", "request_access", "forgot_password", "finish_sign_up",
        "suspended", "home", "explore", "search_results", "visual_search_results", "listing_detail", "member_profile",
        "favorites", "sell", "edit_listing", "my_listings", "inbox", "conversation", "bundle_builder", "bundle_review",
        "checkout", "order_payment", "orders", "order_detail", "dispute", "shipping_label", "earnings", "notifications",
        "profile", "settings", "profile_settings", "username_settings", "email_settings", "password_settings",
        "addresses", "address_form", "blocked_members", "delete_account", "identity_verification", "referrals", "help",
    ]

    /// One route of each case (the associated values do not matter).
    private static let routes: [AppRoute] = [
        .listing(id: "x"), .editListing(id: "x"), .member(username: "x"), .bundleBuilder(username: "x"),
        .search(ExploreQuery()), .visualSearch(id: "x"), .conversation(id: "x"), .bundle(id: "x"),
        .checkout(CheckoutTarget(listingId: "x")), .orderPayment(OrderPaymentTarget(orderId: "x", attempt: .returnedSuccess)),
        .myListings, .favorites, .orders, .order(id: "x"), .dispute(id: "x"), .wallet, .payoutDetails, .notifications,
        .settings, .profileSettings, .usernameSettings, .emailSettings, .passwordSettings, .addresses, .blockedMembers,
        .identityVerification, .help, .deleteAccount, .referrals,
    ]

    private static let authSteps: [AuthFlowModel.Step] = [.signIn, .signUp, .forgotPassword, .requestAccess, .finishSignUp]

    /// Every screen view the app can log: routes, tab roots, sign-in steps, launch screens and the two sheets.
    private static var allViews: [ScreenView] {
        routes.compactMap(\.screenView) + AppTab.allCases.map(\.screenView) + authSteps.map(\.screenView)
            + [.welcome, .updateRequired, .suspended, .addressForm, .shippingLabel]
    }

    @Test func theNamesAreTheSharedList() {
        #expect(AnalyticsScreen.allCases.map(\.rawValue) == Self.sharedList)
    }

    @Test func theNamesAreSnakeCaseUniqueAndShort() throws {
        let names = AnalyticsScreen.allCases.map(\.rawValue)
        let pattern = try Regex("^[a-z]+(_[a-z]+)*$")
        for name in names {
            #expect(name.wholeMatch(of: pattern) != nil, "\(name)")
            #expect(name.count <= 40, "\(name)")
        }
        #expect(Set(names).count == names.count)
    }

    /// Every name is logged by exactly one place, except `earnings` (Earnings, and Earnings with its payout details
    /// sheet: the iOS `payoutDetails` route, as the shared list says).
    @Test func everyNameIsUsedOnce() {
        var uses: [AnalyticsScreen: Int] = [:]
        for view in Self.allViews { uses[view.screen, default: 0] += 1 }
        for screen in AnalyticsScreen.allCases {
            #expect(uses[screen] == (screen == .earnings ? 2 : 1), "\(screen.rawValue)")
        }
        // Each place has its own class string.
        let classes = Self.allViews.map(\.screenClass)
        #expect(Set(classes).count == classes.count)
    }

    @Test func theDebugScreensAreNotLogged() {
        #if DEBUG
        #expect(AppRoute.designSystem.screenView == nil)
        #expect(AppRoute.developerMenu.screenView == nil)
        #endif
    }

    @Test func aScreenLogsOnceUntilAnotherShows() {
        var logged: [String] = []
        let tracker = ScreenTracker { logged.append($0.screen.rawValue) }
        tracker.settled(on: AppTab.home.screenView)
        tracker.settled(on: AppTab.home.screenView)
        tracker.settled(on: AppRoute.listing(id: "1").screenView)
        tracker.settled(on: AppRoute.listing(id: "2").screenView)
        tracker.settled(on: AppTab.home.screenView)
        #expect(logged == ["home", "listing_detail", "home"])
    }

    /// A sheet that is a screen covers the screen under it, which logs again when it closes.
    @Test func aScreenSheetCoversTheScreenUnderIt() {
        let tracker = ScreenTracker { _ in }
        let base = AppRoute.addresses.screenView
        let id = UUID()
        #expect(tracker.current(base: base) == base)
        tracker.show(.addressForm, id: id)
        #expect(tracker.current(base: base) == .addressForm)
        tracker.hide(id: id)
        #expect(tracker.current(base: base) == base)
    }

    /// The splash logs nothing; the screen after it logs.
    @Test func nothingLogsWhileLaunching() {
        var logged: [String] = []
        let tracker = ScreenTracker { logged.append($0.screen.rawValue) }
        tracker.settled(on: nil)
        tracker.settled(on: .welcome)
        #expect(logged == ["welcome"])
    }

    /// A rebuild (the screen gone and back at once) logs nothing new.
    @Test func aQuickRebuildLogsNothing() async {
        var logged: [String] = []
        let tracker = ScreenTracker(settle: .milliseconds(50)) { logged.append($0.screen.rawValue) }
        tracker.didChange(to: AppTab.explore.screenView)
        try? await Task.sleep(for: .milliseconds(150))
        tracker.didChange(to: nil)
        tracker.didChange(to: AppTab.explore.screenView)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(logged == ["explore"])
    }
}
