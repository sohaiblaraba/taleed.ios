import SwiftUI

/// The five tabs: Home, Explore, Sell, Messages, Profile, under the design-system bottom navigation
/// (decision D-2). Every tab keeps its own navigation stack (`AppRouter.paths`) while another one
/// shows, and every stack draws its screens with `RouteDestinationView`.
struct MainShellView: View {
    let home: HomeViewModel
    @Environment(AppRouter.self) private var router
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session
    @Environment(AppToasts.self) private var toasts
    @Environment(WelcomeGate.self) private var welcome
    @Environment(FavoriteStore.self) private var favorites
    @Environment(\.scenePhase) private var scenePhase
    @State private var tabBarHeight: CGFloat = 0
    /// Confirmation modals draw over the whole window, tab bar included (screens.md §0.9).
    @State private var confirmations = ConfirmationHost()

    var body: some View {
        @Bindable var router = router
        ZStack {
            tab(.home) { HomeView(viewModel: home) }
            tab(.explore) { ExploreView() }
            tab(.sell) { SellView() }
            tab(.messages) { MessagesView() }
            tab(.profile) { ProfileView() }
        }
        .environment(\.confirmationHost, confirmations)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // A screen that draws the bar inside its own bottom bar (Item Detail) hides this one.
            if !drawsOwnTabBar {
                ShellTabBar()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabBarHeight = $0 }
            }
        }
        // Above the tab bar, or above the screen's own bottom bar when it draws the tab bar (Item Detail).
        .overlay {
            Color.clear
                .allowsHitTesting(false)
                .taleedToastHost(toasts.state)
                .padding(.bottom, toastBottomInset)
        }
        .onChange(of: router.paths) { _, paths in toasts.keepBottomBars(in: paths) }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
        .accessibilityHidden(showsWelcome || confirmations.presentation(in: router.selectedTab) != nil)
        // Over the tabs and the tab bar: nothing but the modal's two buttons takes a touch.
        .confirmationHostOverlay(confirmations, tab: router.selectedTab)
        .overlay {
            if router.isResolvingLink {
                ProgressView()
                    .controlSize(.large)
                    .tint(TaleedColor.brandPrimary)
                    .accessibilityLabel(l10n.string(.commonLoading))
            }
        }
        // Welcome (Figma Login) covers the shell for a signed-out member until they browse or sign in.
        .overlay {
            if showsWelcome {
                WelcomeView(onContinueWithEmail: { router.presentSignIn() }, onBrowse: { welcome.complete() })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: TaleedMotion.transitionMax), value: showsWelcome)
        // The design-system bottom sheet (handle, start-aligned title, close) with the auth forms, as
        // Android's sign-in sheet. Closing it signed in continues the action that asked for it (the auth gate).
        .taleedSheet(isPresented: authSheetPresented, onDismiss: { router.authSheetDidDismiss() }, content: {
            AuthSheetView(entry: router.authEntry)
                .appLanguage(l10n.language)
        })
        .onAppear { router.shellDidAppear() }
        // Home reloads after a while in the background (here, since Home may sit under a pushed screen).
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                home.wentToBackground()
            case .active:
                Task { await home.returnedToForeground() }
            default:
                break
            }
        }
        // Another member's hearts: the lists reload with theirs.
        .onChange(of: session.user?.id) { _, _ in favorites.sessionDidChange() }
        .onChange(of: session.isSignedIn) { _, isSignedIn in
            if isSignedIn {
                welcome.complete()
            } else {
                router.sessionDidEnd()
            }
        }
    }

    /// The screen on top draws the tab bar inside its own bottom bar (Item Detail).
    private var drawsOwnTabBar: Bool {
        router.path(router.selectedTab).last?.drawsOwnTabBar ?? false
    }

    /// The bottom bar of the screen on top: its own when it draws the tab bar (measured per screen),
    /// otherwise the shell's tab bar.
    private var toastBottomInset: CGFloat {
        guard let top = router.path(router.selectedTab).last, top.drawsOwnTabBar else { return tabBarHeight }
        return toasts.bottomBarHeight(tab: router.selectedTab, route: top) ?? tabBarHeight
    }

    private var showsWelcome: Bool {
        welcome.isVisible && !session.isSignedIn
    }

    private var authSheetPresented: Binding<Bool> {
        Binding(get: { router.authEntry != nil }, set: { if !$0 { router.authEntry = nil } })
    }

    /// Keeps every tab alive in its own navigation stack, and shows the selected one.
    private func tab(_ tab: AppTab, @ViewBuilder root: () -> some View) -> some View {
        let isSelected = router.selectedTab == tab
        return NavigationStack(path: router.pathBinding(tab)) {
            root().navigationDestination(for: AppRoute.self) { route in
                // Pushed screens do not get the shell's bottom inset from the stack: they reserve the tab
                // bar's height themselves, so that their last row scrolls above it (not the screens that
                // draw the bar in their own bottom bar).
                RouteDestinationView(route: route)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Color.clear.frame(height: route.drawsOwnTabBar ? 0 : tabBarHeight).allowsHitTesting(false)
                    }
            }
        }
        .environment(\.shellTab, tab)
        .opacity(isSelected ? 1 : 0)
        .allowsHitTesting(isSelected)
        .accessibilityHidden(!isSelected)
    }
}

private struct ShellTabKey: EnvironmentKey {
    static var defaultValue: AppTab? { nil }
}

extension EnvironmentValues {
    /// The tab whose navigation stack shows the screen (nil outside the shell's stacks).
    var shellTab: AppTab? {
        get { self[ShellTabKey.self] }
        set { self[ShellTabKey.self] = newValue }
    }
}

/// The five tabs' bottom navigation (decision D-2), with the unread-messages badge. `isEmbedded`: inside
/// a screen's own bottom bar (Item Detail's buttons, wireframes.md #4.17), which draws the fill.
struct ShellTabBar: View {
    var isEmbedded = false
    @Environment(AppRouter.self) private var router
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session

    var body: some View {
        TaleedBottomNavigation(items: navigationItems, selection: router.tabSelection, isEmbedded: isEmbedded)
    }

    private var navigationItems: [BottomNavItem<AppTab>] {
        [
            BottomNavItem(id: .home, icon: .houseLine, title: l10n.string(.tabHome)),
            BottomNavItem(id: .explore, icon: .magnifyingGlass, title: l10n.string(.tabExplore)),
            BottomNavItem(id: .sell, icon: .plus, title: l10n.string(.tabSell)),
            BottomNavItem(id: .messages, icon: .chatCircleText, title: l10n.string(.tabMessages),
                          badge: unreadMessages, badgeAccessibilityLabel: unreadMessagesLabel),
            BottomNavItem(id: .profile, icon: .user, title: l10n.string(.tabProfile)),
        ]
    }

    /// `counts.unreadMessages` of `GET /me` (launch, foreground, sign-in).
    private var unreadMessages: Int { session.user?.unreadMessages ?? 0 }

    private var unreadMessagesLabel: String? {
        unreadMessages > 0 ? l10n.format(.appA11yUnreadMessages, unreadMessages) : nil
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
    @Environment(AppRouter.self) private var router
    @Environment(LanguageManager.self) private var l10n

    /// `counts.unreadNotifications` of `GET /me`.
    private var unreadNotifications: Int { session.user?.unreadNotifications ?? 0 }

    var body: some View {
        BrandAppBar(
            showsDivider: showsDivider,
            onNotifications: session.isSignedIn ? { router.push(.notifications) } : nil,
            notificationsBadge: unreadNotifications,
            notificationsBadgeAccessibilityLabel: unreadNotifications > 0
                ? l10n.format(.appA11yUnreadNotifications, unreadNotifications) : nil,
            avatarInitials: session.user.map { TaleedAvatar.initials(from: $0.displayName) },
            avatarURL: session.user?.avatarURL,
            onAvatar: { router.selectedTab = .profile }
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
