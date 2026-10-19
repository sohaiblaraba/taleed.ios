import Foundation

/// The five tabs (screens.md §1.1, decision D-2). Each keeps its own navigation stack.
enum AppTab: String, Hashable, CaseIterable, Sendable {
    case home, explore, sell, messages, profile
}

/// A screen pushed on a tab's navigation stack. Every in-app navigation, link and push ends as one of
/// these (`AppRouter.push(_:)`, `AppRouter.open(_:)`); `RouteDestinationView` draws each one.
///
/// Screen groups add their own cases here (for example `editListing(id:)`), with a line in
/// `RouteDestinationView` and, when a website path leads to it, in `LinkRouter`.
enum AppRoute: Hashable, Sendable {
    // Browse (G2–G5)
    case listing(id: String)
    case member(username: String)
    /// Search results with filters (G3): a category from Home, `/browse?…`, `/categories/…`.
    case search(ExploreQuery)
    case visualSearch(id: String)
    // Messages, offers, bundles, checkout (G9–G11)
    case conversation(id: String)
    case bundle(id: String)
    case checkout(CheckoutTarget)
    // Profile hub (G6, G12–G18)
    case favorites
    case orders
    case order(id: String)
    case wallet
    case notifications
    case settings
    /// Delete the account (G16). Also offered on the suspended screen.
    case deleteAccount
    case referrals
    #if DEBUG
    /// The design-system gallery (debug builds only).
    case designSystem
    /// The developer menu (debug builds only).
    case developerMenu
    #endif

    /// Screens that only make sense signed in: links to them go through the sign-in gate, and they
    /// leave the stacks at sign-out.
    var requiresSignIn: Bool {
        switch self {
        case .conversation, .bundle, .checkout, .favorites, .orders, .order, .wallet, .notifications, .referrals,
             .deleteAccount:
            true
        case .listing, .member, .search, .visualSearch, .settings:
            false
        #if DEBUG
        case .designSystem, .developerMenu:
            false
        #endif
        }
    }
}

/// The filters of a search, as the website's `/browse` query names them. Values the app cannot read
/// (a wilaya that is not a number) are dropped.
struct ExploreQuery: Hashable, Sendable {
    /// The keywords (`q`).
    var text: String?
    /// Category slug; a top-level category includes its subcategories.
    var category: String?
    /// Brand slug.
    var brand: String?
    /// Wilaya code.
    var wilaya: Int?
    /// Condition code (`VERY_GOOD`).
    var condition: String?
    var size: String?
    var minPrice: Int?
    var maxPrice: Int?
    /// `recommended`, `newest`, `price_asc`, `price_desc`.
    var sort: String?

    var isEmpty: Bool { self == ExploreQuery() }
}

/// What checkout buys: a listing, possibly at an accepted offer's price, or a bundle.
struct CheckoutTarget: Hashable, Sendable {
    let listingId: String
    var offerId: String?
    var bundleId: String?
}

/// `taleed://payment-return?kind=order|top_up&id=…&result=success|failure` (slice D, Paying online).
/// Never trust `result`: the screen asks the API how the payment went.
struct PaymentReturn: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case order
        case topUp
    }

    let kind: Kind
    let id: String
    /// What the gateway said; only a hint for the message while the screen syncs.
    let succeeded: Bool
}

/// Where a link, a push or an action leads: a tab, a screen, or something to resolve first.
enum AppDestination: Hashable, Sendable {
    case home
    /// The Explore tab; with filters, their results on top of it.
    case explore(ExploreQuery)
    case sell
    case inbox
    case profile
    case screen(AppRoute)
    /// `/listings/{id}/chat?with={memberId}`: `POST /conversations`, then the conversation, or the
    /// listing when that fails.
    case listingChat(listingId: String, memberId: String)
    /// `/r/{code}`: sign-up with the referral code; Home when signed in.
    case signUp(referralCode: String)
    case paymentReturn(PaymentReturn)
}
