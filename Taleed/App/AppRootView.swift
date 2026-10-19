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
        if screen == "suspended" {
            SuspendedView(support: SupportContacts(email: "contact@taleed.app", phone: "+213 540 69 32 36",
                                                   whatsappURL: URL(string: "https://wa.me/213540693236")))
        } else {
            UpdateRequiredView(storeURL: container.environment.appStoreURL)
        }
    }
    #endif

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
            UpdateRequiredView(storeURL: container.environment.appStoreURL)
        case let .suspended(support):
            SuspendedView(support: support)
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
        appStoreURL: URL(string: "https://apps.apple.com/app/taleed")!
    )
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
