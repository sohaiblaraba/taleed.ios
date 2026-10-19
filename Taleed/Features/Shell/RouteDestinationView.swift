import SwiftUI

/// The screen of each `AppRoute`, for every tab's navigation stack. A screen group replaces its
/// placeholder line with its screen.
///
/// Screens own their view model in `@State` (or get it from `AppContainer`), so that it lives while
/// the screen is in the stack: going back shows the screen below with its scroll, filters and data.
struct RouteDestinationView: View {
    let route: AppRoute
    @Environment(\.exploreDependencies) private var explore
    @Environment(\.listingDependencies) private var listings
    @Environment(\.memberDependencies) private var members
    @Environment(\.favoritesListApi) private var favoritesApi
    @Environment(FavoriteStore.self) private var favorites
    @Environment(SessionManager.self) private var session
    @Environment(\.editListingDependencies) private var editListing
    @Environment(\.myListingsDependencies) private var myListings
    @Environment(ExploreReferenceStore.self) private var references
    @Environment(CatalogStore.self) private var catalog
    @Environment(ListingChangeCenter.self) private var listingChanges

    var body: some View {
        switch route {
        case let .listing(id):
            if let listings {
                ListingDetailView(listingId: id, dependencies: listings, memberId: session.user?.id).id(id)
            } else {
                RoutePlaceholderView(route: route)
            }
        case let .editListing(id):
            if let editListing {
                EditListingView(listingId: id, dependencies: editListing, references: references, catalog: catalog,
                                session: session)
                    .id(id)
            } else {
                RoutePlaceholderView(route: route)
            }
        case let .member(username, wardrobe, opensBundle):
            if let members {
                MemberProfileView(username: username, wardrobe: wardrobe, opensBundle: opensBundle, dependencies: members,
                                  memberId: session.user?.id)
                    .id(route)
            } else {
                RoutePlaceholderView(route: route)
            }
        case .myListings:
            if let myListings {
                MyListingsView(dependencies: myListings, changesSeq: listingChanges.seq)
            } else {
                RoutePlaceholderView(route: route)
            }
        case .bundleBuilder: RoutePlaceholderView(route: route)
        case let .search(query, _):
            // Identity by route (the query and the link's `opening`): a link that replaces the results gets
            // a fresh screen with its filters, even with the same query (SwiftUI would otherwise keep the
            // previous screen's state, the member's edited filters, at the same place in the stack).
            if let explore { SearchResultsView(query: query, api: explore.listings).id(route) } else { RoutePlaceholderView(route: route) }
        case let .visualSearch(id):
            if let explore { VisualSearchResultsView(id: id, api: explore.explore).id(id) } else { RoutePlaceholderView(route: route) }
        case .conversation: RoutePlaceholderView(route: route)
        case .bundle: RoutePlaceholderView(route: route)
        case .checkout: RoutePlaceholderView(route: route)
        case .favorites:
            if let favoritesApi { FavoritesView(api: favoritesApi, store: favorites) } else { RoutePlaceholderView(route: route) }
        case .orders: RoutePlaceholderView(route: route)
        case .order: RoutePlaceholderView(route: route)
        case .wallet: RoutePlaceholderView(route: route)
        case .notifications: NotificationsView()
        case .settings: SettingsView()
        case .deleteAccount: RoutePlaceholderView(route: route)
        case .referrals: RoutePlaceholderView(route: route)
        #if DEBUG
        case .designSystem: DesignSystemGalleryView()
        case .developerMenu: DeveloperMenuView()
        #endif
        }
    }
}

/// A screen that is not built yet: back, and "coming soon". Debug builds also name the route, to
/// check links on the simulator.
struct RoutePlaceholderView: View {
    let route: AppRoute
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: "", onBack: { dismiss() })
        } content: {
            MessageStateView(text: l10n.string(.appPlaceholderComingSoon)) {
                #if DEBUG
                Text(verbatim: String(describing: route))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityIdentifier("route_placeholder")
                #endif
            }
        }
    }
}
