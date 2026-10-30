import Foundation
import Observation
import SwiftUI

/// The screen names of the analytics `screen_view` events, shared with Android (plan/analytics-screens.md). The raw
/// value is the `screen_name`: stable English snake case, without digits. Never an id, a title or other content.
enum AnalyticsScreen: String, CaseIterable, Sendable {
    case updateRequired = "update_required"
    case welcome
    case signIn = "sign_in"
    case signUp = "sign_up"
    case requestAccess = "request_access"
    case forgotPassword = "forgot_password"
    case finishSignUp = "finish_sign_up"
    case suspended
    case home
    case explore
    case searchResults = "search_results"
    case visualSearchResults = "visual_search_results"
    case listingDetail = "listing_detail"
    case memberProfile = "member_profile"
    case favorites
    case sell
    case editListing = "edit_listing"
    case myListings = "my_listings"
    case inbox
    case conversation
    case bundleBuilder = "bundle_builder"
    case bundleReview = "bundle_review"
    case checkout
    case orderPayment = "order_payment"
    case orders
    case orderDetail = "order_detail"
    case dispute
    case shippingLabel = "shipping_label"
    case earnings
    case notifications
    case profile
    case settings
    case profileSettings = "profile_settings"
    case usernameSettings = "username_settings"
    case emailSettings = "email_settings"
    case passwordSettings = "password_settings"
    case addresses
    case addressForm = "address_form"
    case blockedMembers = "blocked_members"
    case deleteAccount = "delete_account"
    case identityVerification = "identity_verification"
    case referrals
    case help
}

/// One `screen_view`: the shared name and a stable class string of this platform (the route case or the view),
/// written out so that a rename in code does not change it.
struct ScreenView: Equatable, Sendable {
    let screen: AnalyticsScreen
    let screenClass: String

    init(_ screen: AnalyticsScreen, _ screenClass: String) {
        self.screen = screen
        self.screenClass = screenClass
    }
}

extension AppRoute {
    /// The screen this route shows; nil for the debug-only screens, which never collect.
    var screenView: ScreenView? {
        switch self {
        case .listing: ScreenView(.listingDetail, "AppRoute.listing")
        case .editListing: ScreenView(.editListing, "AppRoute.editListing")
        case .member: ScreenView(.memberProfile, "AppRoute.member")
        case .bundleBuilder: ScreenView(.bundleBuilder, "AppRoute.bundleBuilder")
        case .search: ScreenView(.searchResults, "AppRoute.search")
        case .visualSearch: ScreenView(.visualSearchResults, "AppRoute.visualSearch")
        case .conversation: ScreenView(.conversation, "AppRoute.conversation")
        case .bundle: ScreenView(.bundleReview, "AppRoute.bundle")
        case .checkout: ScreenView(.checkout, "AppRoute.checkout")
        case .orderPayment: ScreenView(.orderPayment, "AppRoute.orderPayment")
        case .myListings: ScreenView(.myListings, "AppRoute.myListings")
        case .favorites: ScreenView(.favorites, "AppRoute.favorites")
        case .orders: ScreenView(.orders, "AppRoute.orders")
        case .order: ScreenView(.orderDetail, "AppRoute.order")
        case .dispute: ScreenView(.dispute, "AppRoute.dispute")
        case .wallet: ScreenView(.earnings, "AppRoute.wallet")
        // Earnings with its payout details sheet open; the sheet is not a screen.
        case .payoutDetails: ScreenView(.earnings, "AppRoute.payoutDetails")
        case .notifications: ScreenView(.notifications, "AppRoute.notifications")
        case .settings: ScreenView(.settings, "AppRoute.settings")
        case .profileSettings: ScreenView(.profileSettings, "AppRoute.profileSettings")
        case .usernameSettings: ScreenView(.usernameSettings, "AppRoute.usernameSettings")
        case .emailSettings: ScreenView(.emailSettings, "AppRoute.emailSettings")
        case .passwordSettings: ScreenView(.passwordSettings, "AppRoute.passwordSettings")
        case .addresses: ScreenView(.addresses, "AppRoute.addresses")
        case .blockedMembers: ScreenView(.blockedMembers, "AppRoute.blockedMembers")
        case .identityVerification: ScreenView(.identityVerification, "AppRoute.identityVerification")
        case .help: ScreenView(.help, "AppRoute.help")
        case .deleteAccount: ScreenView(.deleteAccount, "AppRoute.deleteAccount")
        case .referrals: ScreenView(.referrals, "AppRoute.referrals")
        #if DEBUG
        case .designSystem: nil
        #endif
        #if DEBUG || TALEED_TEST_TOOLS
        case .developerMenu: nil
        #endif
        }
    }
}

extension AppTab {
    /// The tab's root screen.
    var screenView: ScreenView {
        switch self {
        case .home: ScreenView(.home, "HomeView")
        case .explore: ScreenView(.explore, "ExploreView")
        case .sell: ScreenView(.sell, "SellView")
        case .messages: ScreenView(.inbox, "MessagesView")
        case .profile: ScreenView(.profile, "ProfileView")
        }
    }
}

extension AuthFlowModel.Step {
    /// The step of the sign-in sheet, which covers the tabs (rule 9).
    var screenView: ScreenView {
        switch self {
        case .signIn: ScreenView(.signIn, "AuthStep.signIn")
        case .signUp: ScreenView(.signUp, "AuthStep.signUp")
        case .forgotPassword: ScreenView(.forgotPassword, "AuthStep.forgotPassword")
        case .requestAccess: ScreenView(.requestAccess, "AuthStep.requestAccess")
        case .finishSignUp: ScreenView(.finishSignUp, "AuthStep.finishSignUp")
        }
    }
}

extension ScreenView {
    static let welcome = ScreenView(.welcome, "WelcomeView")
    static let updateRequired = ScreenView(.updateRequired, "UpdateRequiredView")
    static let suspended = ScreenView(.suspended, "SuspendedView")
    /// Sheets on iOS that are screens on Android: logged on both (plan/analytics-screens.md, rule 10).
    static let addressForm = ScreenView(.addressForm, "AddressFormSheet")
    static let shippingLabel = ScreenView(.shippingLabel, "ShippingLabelSheet")
}

/// Logs a `screen_view` each time the screen the member sees changes (plan/analytics-screens.md).
///
/// The root works out the screen from the launch route, the welcome screen, the selected tab and its stack
/// (`AppContainer.baseScreen`). A sheet that is a screen (the sign-in flow, the address form, the shipping label)
/// covers it while it shows (`analyticsScreen(_:)`); when it closes, the screen under it logs again. A change is
/// logged once it has lasted `settle`, so the rebuild of a language switch (the same screen gone and back at once)
/// logs nothing, and neither does a redraw of the same screen.
@MainActor
@Observable
final class ScreenTracker {
    private struct Overlay {
        let id: UUID
        var view: ScreenView
    }

    /// The sheets that are screens, the newest last.
    private var overlays: [Overlay] = []

    @ObservationIgnored private var lastLogged: ScreenView?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let settle: Duration
    @ObservationIgnored private let log: (ScreenView) -> Void

    init(settle: Duration = .milliseconds(400), log: @escaping (ScreenView) -> Void) {
        self.settle = settle
        self.log = log
    }

    /// The screen on top: the newest sheet that is a screen, otherwise `base`.
    func current(base: ScreenView?) -> ScreenView? {
        overlays.last?.view ?? base
    }

    /// The screen on top changed (or seemed to): logged once it lasts.
    func didChange(to view: ScreenView?) {
        pending?.cancel()
        pending = Task { [weak self, settle] in
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled else { return }
            self?.settled(on: view)
        }
    }

    /// Logs `view` unless it is the screen logged last. Nil (the splash, the launch error) logs nothing, and the
    /// next screen logs.
    func settled(on view: ScreenView?) {
        guard view != lastLogged else { return }
        lastLogged = view
        if let view { log(view) }
    }

    func show(_ view: ScreenView, id: UUID) {
        if let index = overlays.firstIndex(where: { $0.id == id }) {
            overlays[index].view = view
        } else {
            overlays.append(Overlay(id: id, view: view))
        }
    }

    func hide(id: UUID) {
        overlays.removeAll { $0.id == id }
    }
}

private struct ScreenTrackerKey: EnvironmentKey {
    static var defaultValue: ScreenTracker? { nil }
}

extension EnvironmentValues {
    /// Set once at the root (`AppRootView`).
    var screenTracker: ScreenTracker? {
        get { self[ScreenTrackerKey.self] }
        set { self[ScreenTrackerKey.self] = newValue }
    }
}

private struct AnalyticsScreenModifier: ViewModifier {
    let view: ScreenView
    @Environment(\.screenTracker) private var tracker
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { tracker?.show(view, id: id) }
            .onChange(of: view) { _, view in tracker?.show(view, id: id) }
            .onDisappear { tracker?.hide(id: id) }
    }
}

extension View {
    /// A sheet that is a screen: it is the screen on top while it shows.
    func analyticsScreen(_ view: ScreenView) -> some View {
        modifier(AnalyticsScreenModifier(view: view))
    }
}
