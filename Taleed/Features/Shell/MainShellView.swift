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

    var body: some View {
        @Bindable var router = router
        ZStack {
            tab(.home) { HomeView(viewModel: home) }
            tab(.explore) { ExploreView() }
            tab(.sell) { SellView() }
            tab(.messages) { MessagesView() }
            tab(.profile) { ProfileView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TaleedBottomNavigation(items: navigationItems, selection: router.tabSelection)
        }
        .taleedToastHost(toasts.state)
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
        .accessibilityHidden(showsWelcome)
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
        .onChange(of: session.isSignedIn) { _, isSignedIn in
            if isSignedIn {
                welcome.complete()
            } else {
                router.sessionDidEnd()
            }
        }
    }

    private var showsWelcome: Bool {
        welcome.isVisible && !session.isSignedIn
    }

    private var authSheetPresented: Binding<Bool> {
        Binding(get: { router.authEntry != nil }, set: { if !$0 { router.authEntry = nil } })
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

    /// Keeps every tab alive in its own navigation stack, and shows the selected one.
    private func tab(_ tab: AppTab, @ViewBuilder root: () -> some View) -> some View {
        let isSelected = router.selectedTab == tab
        return NavigationStack(path: router.pathBinding(tab)) {
            root().navigationDestination(for: AppRoute.self) { RouteDestinationView(route: $0) }
        }
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
