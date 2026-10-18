import Observation
import SwiftUI

enum ShellTab: Hashable {
    case home, explore, sell, messages, profile
}

enum ProfileRoute: Hashable {
    case settings
}

/// Navigation state of the main shell. It lives outside the views so that it survives
/// a language switch.
@MainActor
@Observable
final class ShellRouter {
    var selectedTab: ShellTab = .home
    var profilePath: [ProfileRoute] = []
    var isSignInPresented = false

    /// Selecting the current tab again returns it to its first screen.
    var tabSelection: Binding<ShellTab> {
        Binding(
            get: { self.selectedTab },
            set: { tab in
                if tab == self.selectedTab, tab == .profile { self.profilePath = [] }
                self.selectedTab = tab
            }
        )
    }
}

/// The five tabs: Home, Explore, Sell, Messages, Profile.
struct MainShellView: View {
    let home: HomeViewModel
    @Environment(ShellRouter.self) private var router
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        @Bindable var router = router
        TabView(selection: router.tabSelection) {
            NavigationStack { HomeView(viewModel: home) }
                .tabItem { Label(l10n.string(.tabHome), systemImage: "house") }
                .tag(ShellTab.home)

            NavigationStack { ExploreView() }
                .tabItem { Label(l10n.string(.tabExplore), systemImage: "magnifyingglass") }
                .tag(ShellTab.explore)

            NavigationStack { SellView() }
                .tabItem { Label(l10n.string(.tabSell), systemImage: "plus.circle") }
                .tag(ShellTab.sell)

            NavigationStack { MessagesView() }
                .tabItem { Label(l10n.string(.tabMessages), systemImage: "bubble.left") }
                .tag(ShellTab.messages)

            NavigationStack(path: $router.profilePath) {
                ProfileView()
                    .navigationDestination(for: ProfileRoute.self) { route in
                        switch route {
                        case .settings: SettingsView()
                        }
                    }
            }
            .tabItem { Label(l10n.string(.tabProfile), systemImage: "person") }
            .tag(ShellTab.profile)
        }
        .sheet(isPresented: $router.isSignInPresented) {
            SignInView()
                .appLanguage(l10n.language)
        }
    }
}
