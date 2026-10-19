import SwiftUI

/// The screen of each `AppRoute`, for every tab's navigation stack. A screen group replaces its
/// placeholder line with its screen.
///
/// Screens own their view model in `@State` (or get it from `AppContainer`), so that it lives while
/// the screen is in the stack: going back shows the screen below with its scroll, filters and data.
struct RouteDestinationView: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .listing: RoutePlaceholderView(route: route)
        case .member: RoutePlaceholderView(route: route)
        case .search: RoutePlaceholderView(route: route)
        case .visualSearch: RoutePlaceholderView(route: route)
        case .conversation: RoutePlaceholderView(route: route)
        case .bundle: RoutePlaceholderView(route: route)
        case .checkout: RoutePlaceholderView(route: route)
        case .favorites: RoutePlaceholderView(route: route)
        case .orders: RoutePlaceholderView(route: route)
        case .order: RoutePlaceholderView(route: route)
        case .wallet: RoutePlaceholderView(route: route)
        case .notifications: NotificationsView()
        case .settings: SettingsView()
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
