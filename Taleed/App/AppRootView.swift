import SwiftUI
import UserNotifications

/// Shows the screen that the launch flow decides, in the app language and its direction.
struct AppRootView: View {
    let container: AppContainer
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasInBackground = false

    var body: some View {
        let language = container.languageManager.language
        content
            // Rebuild the screens when the language changes. Otherwise a screen that is off screen
            // in a navigation stack keeps the old layout direction and shows mirrored text.
            // The tab and the navigation paths live in AppRouter, so they survive.
            .id(language)
            .environment(container.languageManager)
            .environment(container.appearance)
            .environment(container.session)
            .environment(container.router)
            .environment(container.catalog)
            .environment(container.toasts)
            .environment(container.network)
            .environment(container.favorites)
            .environment(container.listingChanges)
            .environment(container.orderChanges)
            .environment(container.welcome)
            .environment(container.launch)
            .environment(container.account)
            .environment(container.push)
            .environment(container.pushCenter)
            .environment(container.analytics)
            .environment(container.exploreReferences)
            .environment(\.exploreDependencies, ExploreDependencies(listings: container.api, explore: container.api))
            .environment(\.listingDependencies,
                         ListingDependencies(listings: container.api, bundles: container.api, reports: container.api,
                                             uploads: container.uploads))
            .environment(\.favoritesListApi, container.api)
            .environment(\.sellDependencies, SellDependencies(api: container.api, uploads: container.uploads))
            .environment(\.editListingDependencies, EditListingDependencies(api: container.api, uploads: container.uploads))
            .environment(\.myListingsDependencies, MyListingsDependencies(listings: container.api, owner: container.api))
            .environment(\.messagesDependencies,
                         MessagesDependencies(messages: container.api, events: container.api, members: container.api,
                                              offers: container.api, reports: container.api, uploads: container.uploads,
                                              reads: container.conversationReads))
            .environment(\.pushRegistration, container.push)
            .environment(\.screenTracker, container.screens)
            .environment(\.bundleDependencies, BundleDependencies(bundles: container.api, members: container.api))
            .environment(\.checkoutDependencies,
                         CheckoutDependencies(checkout: container.api, listings: container.api, bundles: container.api))
            .environment(\.ordersDependencies, OrdersDependencies(orders: container.api, uploads: container.uploads))
            .environment(\.walletApi, container.api)
            .environment(\.referralsApi, container.api)
            .environment(\.settingsDependencies,
                         SettingsDependencies(account: container.api, addresses: container.api, blocks: container.api,
                                              verification: container.api, uploads: container.uploads))
            .environment(\.notificationsDependencies,
                         NotificationsDependencies(api: container.api, feed: container.notificationsFeed))
            .environment(\.memberDependencies,
                         MemberDependencies(members: container.api, reports: container.api, uploads: container.uploads))
            .environment(\.authDependencies, AuthDependencies(
                api: container.api,
                isBetaMode: { [launch = container.launch] in
                    #if DEBUG
                    if DebugLaunchOptions.forcesBetaMode { return true }
                    #endif
                    return launch.config?.betaMode ?? false
                },
                google: container.google,
                socialAvailability: { [launch = container.launch, google = container.google] in
                    launch.socialAvailability(googleConfigured: google.isConfigured)
                },
                socialSignInWasDisabled: { [launch = container.launch] provider in
                    Task { await launch.socialSignInWasDisabled(provider) }
                }
            ))
            #if DEBUG || TALEED_TEST_TOOLS
            .environment(\.developmentApi, container.api)
            #endif
            .environment(\.appEnvironment, container.environment)
            .appLanguage(language)
            .tint(Theme.primary)
            // The Appearance setting: SwiftUI's views and sheets, then the windows for what UIKit presents.
            .preferredColorScheme(colorScheme)
            .onAppear { container.appearance.apply() }
            // A named screen view per screen (plan/analytics-screens.md).
            .onChange(of: currentScreen, initial: true) { _, screen in container.screens.didChange(to: screen) }
            .onChange(of: container.appearance.appearance, initial: true) { _, appearance in
                container.crashReporting.appearanceDidChange(appearance)
            }
            // The icon badge follows the counts the app shows (slice C): unread messages and notifications.
            .onChange(of: badgeCount, initial: true) { _, count in
                Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
            }
            .task { await container.launch.start() }
            // The disk copy shows at once; the launch fetches the catalog again (api-guide.md, Caching).
            .task { await container.catalog.refresh() }
            // App links (taleed.app), the payment return (`taleed://payment-return`) and pushes all go
            // through the router; one that comes during launch waits for the launch flow.
            // Google's sign-in page returns to the reversed client ID scheme (slice G); the SDK takes it.
            .onOpenURL { url in
                if container.google.handle(url) { return }
                container.router.open(url: url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { container.router.open(url: url) }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    wasInBackground = true
                case .active where wasInBackground:
                    wasInBackground = false
                    Task { await container.launch.didReturnToForeground() }
                    // The push permission may have changed in the system settings meanwhile.
                    Task { await container.push.refresh() }
                default:
                    break
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        if let screen = DebugLaunchOptions.launchScreen {
            debugLaunchScreen(screen)
        } else {
            launchContent
        }
        #else
        launchContent
        #endif
    }

    #if DEBUG
    @ViewBuilder
    private func debugLaunchScreen(_ screen: String) -> some View {
        if screen == "suspended" || screen == "suspendedSession" {
            SuspendedView(support: SupportContacts(email: "contact@taleed.app", phone: "+213 540 69 32 36",
                                                   whatsappURL: URL(string: "https://wa.me/213540693236")),
                          showsAccountLinks: screen == "suspendedSession")
        } else if screen == "launchError" {
            LaunchErrorView(error: .network) {}
        } else {
            UpdateRequiredView(storeURL: storeURL ?? URL(string: "https://taleed.app"))
        }
    }
    #endif

    /// The Appearance setting, except under the welcome screen's sky artwork, which is drawn for light
    /// (dark text, dark status bar) in every appearance; its sign-in sheet follows the setting. Nil (System)
    /// follows the phone.
    private var colorScheme: ColorScheme? {
        let showsWelcome = container.launch.route == .main && container.welcome.isVisible
            && !container.session.isSignedIn && container.router.authEntry == nil
        return showsWelcome ? .light : container.appearance.colorScheme
    }

    /// The screen the member sees, for the analytics screen views.
    private var currentScreen: ScreenView? {
        container.screens.current(base: container.baseScreen)
    }

    /// Unread messages plus unread notifications, as `GET /me` and the read marks give them; 0 signed out.
    private var badgeCount: Int {
        guard let user = container.session.user else { return 0 }
        return user.unreadMessages + user.unreadNotifications
    }

    /// The App Store page, or the website until the app has an App Store ID (`TALEED_APP_STORE_ID`).
    private var storeURL: URL? {
        container.environment.appStoreURL ?? container.launch.config?.links.website
    }

    @ViewBuilder
    private var launchContent: some View {
        switch container.launch.route {
        case .loading:
            SplashView()
        case let .failed(error):
            LaunchErrorView(error: error) {
                Task { await container.launch.start() }
            }
        case .updateRequired:
            UpdateRequiredView(storeURL: storeURL)
        case let .suspended(support):
            SuspendedView(support: support, showsAccountLinks: container.session.hasSuspendedSession)
        case .main:
            MainShellView(home: container.home)
        }
    }
}

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppEnvironment(
        apiBaseURL: URL(string: "http://localhost:3000/api/v1")!,
        appVersion: "0.0.0",
        buildNumber: "0",
        appStoreID: nil
    )
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
