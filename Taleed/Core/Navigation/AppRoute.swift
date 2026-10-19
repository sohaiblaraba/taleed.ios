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
    /// The seller's edit form (G8).
    case editListing(id: String)
    /// A member's profile (G5). `wardrobe`: the filter a link asked for (`?category=&sort=`).
    /// `opensBundle`: the website's `?bundle=1`; the bundle builder opens over the profile once it has
    /// loaded, only when the profile offers it (`canBundle`, never the member's own profile).
    case member(username: String, wardrobe: WardrobeQuery = WardrobeQuery(), opensBundle: Bool = false)
    /// Picking a seller's items for a bundle (G10): "Achète en lot" on a listing.
    case bundleBuilder(username: String)
    /// Search results with filters (G3): a category from Home, `/browse?…`, `/categories/…`.
    /// `opening`: set by each link that opens the screen (`AppRouter.open`), so that a link gives a fresh
    /// screen with its own filters even when the results open below have the same query.
    case search(ExploreQuery, opening: UUID? = nil)
    case visualSearch(id: String)
    // Messages, offers, bundles, checkout (G9–G11)
    /// A conversation (G9). `focusesComposer`: "Message the seller" opens it with the keyboard up.
    case conversation(id: String, focusesComposer: Bool = false)
    case bundle(id: String)
    case checkout(CheckoutTarget)
    // Profile hub (G6, G8, G12–G18)
    /// The member's own listings (G8): "Mes annonces" on their profile.
    case myListings
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
             .deleteAccount, .editListing, .bundleBuilder, .myListings:
            true
        case .listing, .member, .search, .visualSearch, .settings:
            false
        #if DEBUG
        case .designSystem, .developerMenu:
            false
        #endif
        }
    }

    /// The screen draws the tab bar itself, inside its bottom bar (Item Detail): the shell hides its own.
    var drawsOwnTabBar: Bool {
        if case .listing = self { return true }
        return false
    }

    /// The shell hides its tab bar over this screen: Item Detail draws its own; a conversation keeps the
    /// bottom for its composer, which rises with the keyboard.
    var hidesShellTabBar: Bool {
        if case .conversation = self { return true }
        return drawsOwnTabBar
    }

    /// The same screen with a new identity: a link opens it fresh, never on the state of a screen
    /// already in the stack with the same route.
    var reopened: AppRoute {
        switch self {
        case let .search(query, _): .search(query, opening: UUID())
        default: self
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
    /// `/listings/{id}/chat`: `POST /conversations`, then the conversation, or the listing when that
    /// fails. Without `memberId` the member writes to the seller as a buyer (the website's
    /// `getOrCreateConversation`); with it (`?with=`), the seller writes to that member.
    case listingChat(listingId: String, memberId: String?)
    /// `/r/{code}`: sign-up with the referral code; Home when signed in.
    case signUp(referralCode: String)
    case paymentReturn(PaymentReturn)
}
