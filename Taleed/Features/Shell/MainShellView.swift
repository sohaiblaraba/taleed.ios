import Observation
import SwiftUI

enum ShellTab: Hashable, CaseIterable {
    case home, explore, sell, messages, profile
}

/// Screens pushed on the Home and Sell tabs.
enum ShellRoute: Hashable {
    /// The notifications placeholder, opened from the brand app bar's bell.
    case notifications
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
    var homePath: [ShellRoute] = []
    var sellPath: [ShellRoute] = []
    var profilePath: [ProfileRoute] = []
    var isSignInPresented = false

    /// Selecting the current tab again returns it to its first screen.
    var tabSelection: Binding<ShellTab> {
        Binding(
            get: { self.selectedTab },
            set: { tab in
                if tab == self.selectedTab {
                    switch tab {
                    case .home: self.homePath = []
                    case .sell: self.sellPath = []
                    case .profile: self.profilePath = []
                    case .explore, .messages: break
                    }
                }
                self.selectedTab = tab
            }
        )
    }

    /// Pushes the notifications placeholder on the current tab (the bell shows on Home and Sell).
    func openNotifications() {
        if selectedTab == .sell { sellPath.append(.notifications) } else { homePath.append(.notifications) }
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
            tab(.home) {
                NavigationStack(path: $router.homePath) {
                    HomeView(viewModel: home).shellDestinations()
                }
            }
            tab(.explore) { NavigationStack { ExploreView() } }
            tab(.sell) {
                NavigationStack(path: $router.sellPath) {
                    SellView().shellDestinations()
                }
            }
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
            TaleedBottomNavigation(items: navigationItems, selection: router.tabSelection)
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
        // The design-system bottom sheet (handle, start-aligned title, close), as Android's sign-in sheet.
        .taleedSheet(isPresented: $router.isSignInPresented) {
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

/// The brand app bar of Home and Sell. Signed in, it shows the notifications bell (opens the
/// notifications placeholder) and the member's avatar (opens Profile), as on Android.
struct ShellBrandAppBar: View {
    var showsDivider = true
    @Environment(SessionManager.self) private var session
    @Environment(ShellRouter.self) private var router

    var body: some View {
        BrandAppBar(
            showsDivider: showsDivider,
            onNotifications: session.isSignedIn ? { router.openNotifications() } : nil,
            avatarInitials: session.user.map { TaleedAvatar.initials(from: $0.displayName) },
            avatarURL: session.user?.avatarURL,
            onAvatar: { router.selectedTab = .profile }
        )
    }
}

private extension View {
    /// The screens Home and Sell push.
    func shellDestinations() -> some View {
        navigationDestination(for: ShellRoute.self) { route in
            switch route {
            case .notifications: NotificationsView()
            }
        }
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
