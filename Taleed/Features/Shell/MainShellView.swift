import Observation
import SwiftUI

enum ShellTab: Hashable, CaseIterable {
    case home, explore, sell, messages, profile
}

enum ProfileRoute: Hashable {
    case settings
    #if DEBUG
    /// The design-system gallery (debug builds only).
    case designSystem
    #endif
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

/// The five tabs: Home, Explore, Sell, Messages, Profile, under the design-system bottom navigation
/// (decision D-2). Every tab keeps its own navigation stack while another one shows.
struct MainShellView: View {
    let home: HomeViewModel
    @Environment(ShellRouter.self) private var router
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        @Bindable var router = router
        ZStack {
            tab(.home) { NavigationStack { HomeView(viewModel: home) } }
            tab(.explore) { NavigationStack { ExploreView() } }
            tab(.sell) { NavigationStack { SellView() } }
            tab(.messages) { NavigationStack { MessagesView() } }
            tab(.profile) {
                NavigationStack(path: $router.profilePath) {
                    ProfileView()
                        .navigationDestination(for: ProfileRoute.self) { route in
                            switch route {
                            case .settings: SettingsView()
                            #if DEBUG
                            case .designSystem: DesignSystemGalleryView()
                            #endif
                            }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomNavigation(items: navigationItems, selection: router.tabSelection)
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
        .sheet(isPresented: $router.isSignInPresented) {
            SignInView()
                .appLanguage(l10n.language)
        }
    }

    private var navigationItems: [BottomNavItem<ShellTab>] {
        [
            BottomNavItem(id: .home, icon: .houseLine, title: l10n.string(.tabHome)),
            BottomNavItem(id: .explore, icon: .magnifyingGlass, title: l10n.string(.tabExplore)),
            BottomNavItem(id: .sell, icon: .plus, title: l10n.string(.tabSell)),
            BottomNavItem(id: .messages, icon: .chatCircleText, title: l10n.string(.tabMessages)),
            BottomNavItem(id: .profile, icon: .user, title: l10n.string(.tabProfile)),
        ]
    }

    /// Keeps every tab alive and shows the selected one.
    private func tab(_ tab: ShellTab, @ViewBuilder content: () -> some View) -> some View {
        let isSelected = router.selectedTab == tab
        return content()
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }
}

/// A screen of the shell: the design-system app bar on top of the content, on white, without the
/// system navigation bar.
struct ShellScreen<Bar: View, Content: View>: View {
    @ViewBuilder let bar: Bar
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            bar
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The brand app bar of the top-level tabs, with the member's avatar (opens Profile).
struct ShellBrandAppBar: View {
    var showsDivider = true
    @Environment(SessionManager.self) private var session
    @Environment(ShellRouter.self) private var router
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        BrandAppBar(
            showsDivider: showsDivider,
            avatarInitials: session.user.map { TaleedAvatar.initials(from: $0.username ?? $0.displayName) },
            avatarURL: session.user?.avatarURL,
            avatarAccessibilityLabel: l10n.string(.tabProfile),
            onAvatar: router.selectedTab == .profile ? nil : { router.selectedTab = .profile }
        )
    }
}

/// Keeps the swipe-from-edge back gesture while the system navigation bar is hidden.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
