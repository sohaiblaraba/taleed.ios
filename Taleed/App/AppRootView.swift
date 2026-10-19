import SwiftUI

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
            .environment(container.session)
            .environment(container.router)
            .environment(container.catalog)
            .environment(container.toasts)
            .environment(container.favorites)
            .environment(container.listingChanges)
            .environment(container.welcome)
            .environment(container.launch)
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
            .environment(\.bundleDependencies, BundleDependencies(bundles: container.api, members: container.api))
            .environment(\.checkoutDependencies,
                         CheckoutDependencies(checkout: container.api, listings: container.api, bundles: container.api))
            .environment(\.memberDependencies,
                         MemberDependencies(members: container.api, reports: container.api, uploads: container.uploads))
            .environment(\.authDependencies, AuthDependencies(api: container.api, isBetaMode: { [launch = container.launch] in
                #if DEBUG
                if DebugLaunchOptions.forcesBetaMode { return true }
                #endif
                return launch.config?.betaMode ?? false
            }))
            #if DEBUG
            .environment(\.developmentApi, container.api)
            #endif
            .environment(\.appEnvironment, container.environment)
            .appLanguage(language)
            .tint(Theme.primary)
            .preferredColorScheme(.light)
            .task { await container.launch.start() }
            // The disk copy shows at once; the launch fetches the catalog again (api-guide.md, Caching).
            .task { await container.catalog.refresh() }
            // App links (taleed.app), the payment return (`taleed://payment-return`) and pushes all go
            // through the router; one that comes during launch waits for the shell.
            .onOpenURL { container.router.open(url: $0) }
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
