import Foundation
import SwiftUI

/// Builds the app's objects once, with constructor injection.
///
/// Screen groups get their API protocol from `api` (which implements every one), the catalog from
/// `catalog`, photo uploads from `uploads`, and navigation from `router` (also in the environment).
@MainActor
final class AppContainer {
    let environment: AppEnvironment
    let languageManager: LanguageManager
    let apiSession: ApiSession
    let api: GeneratedTaleedApi
    let session: SessionManager
    let launch: LaunchViewModel
    let catalog: CatalogStore
    let home: HomeViewModel
    let favorites: FavoriteStore
    /// The member's changes to their listings, for every screen that shows them (G8).
    let listingChanges = ListingChangeCenter()
    let orderChanges = OrderChangeCenter()
    /// The conversations the member reads, for the inbox's rows (G9).
    let conversationReads = ConversationReads()
    /// Tells an open notifications screen that something new arrived (G15): a `/notifications` link,
    /// and the pushes once the app receives them (G16).
    let notificationsFeed = NotificationsFeed()
    /// Brands and sizes of the Explore filter sheet.
    let exploreReferences: ExploreReferenceStore
    let router = AppRouter()
    let toasts: AppToasts
    /// The device's network path, for the offline banner.
    let network = NetworkMonitor()
    let uploads: PhotoUploadService
    let welcome: WelcomeGate
    /// The push permission and `POST /devices`, after the member's first message or offer.
    let push: PushRegistration
    /// The member's account for the settings screens (G16).
    let account: AccountStore

    init(environment: AppEnvironment = .current(), tokenStore: TokenStore = KeychainTokenStore()) {
        ImageLoading.configure()
        self.environment = environment
        languageManager = LanguageManager()
        apiSession = ApiSession(environment: environment, language: languageManager.language)
        api = GeneratedTaleedApi(session: apiSession)
        session = SessionManager(api: api, apiSession: apiSession, tokenStore: tokenStore)
        launch = LaunchViewModel(api: api, session: session, environment: environment)
        catalog = CatalogStore(api: api, language: languageManager.language)
        home = HomeViewModel(api: api, catalog: catalog)
        favorites = FavoriteStore(api: api)
        exploreReferences = ExploreReferenceStore(api: api)
        toasts = AppToasts(languageManager: languageManager)
        uploads = PhotoUploadService(api: api)
        welcome = WelcomeGate()
        push = Self.makePush(api: api, launch: launch, session: session, languageManager: languageManager)
        account = AccountStore(api: api, session: session)

        // A suspended member who was signed in keeps the screens that still answer (orders, wallet,
        // account deletion), so links to them do not ask to sign in.
        router.isSignedIn = { [session] in session.isSignedIn || session.hasSuspendedSession }
        // Without the fade: removing the welcome screen in the frame it appeared left an invisible copy
        // over the shell that took every touch (a link opening the app while the welcome screen was due).
        router.onDestinationOpened = { [welcome] in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { welcome.skipForLink() }
        }
        session.onSignedOut = { [welcome, router, push, account] in
            push.sessionDidEnd()
            account.reset()
            welcome.showAfterSignOut()
            router.sessionDidEnd()
            router.selectedTab = .home
        }
        // From the suspended screen the shell was not on screen to see the session end: leave the
        // screens that need an account here too.
        session.onSessionExpired = { [router, account] in
            account.reset()
            router.sessionDidEnd()
            router.presentSignIn()
        }
        // The suspended screen is the root of the Profile stack: nothing may cover it (screens.md §0.6).
        session.onSuspended = { [router] in router.popToRoot(.profile) }
        router.resolveConversation = { [api] (listingId: String, buyerId: String?) async throws(ApiError) -> String in
            try await api.openConversation(listingId: listingId, buyerId: buyerId)
        }
        router.websiteLinks = { [launch] in launch.config?.links ?? WebsiteLinks() }
        router.onNotificationsOpened = { [notificationsFeed] in notificationsFeed.somethingArrived() }
        favorites.onFailure = { [toasts] error in toasts.show(error: error) }
        favorites.onRemoved = { [toasts, languageManager] _ in
            toasts.show(languageManager.string(.appNotFoundTitle), kind: .info)
        }

        #if DEBUG
        DebugLaunchOptions.apply(to: router)
        #endif

        connectSettings()
    }

    /// No token source until Firebase is set up (plan action 3): nothing is asked or registered meanwhile.
    private static func makePush(api: GeneratedTaleedApi, launch: LaunchViewModel, session: SessionManager,
                                 languageManager: LanguageManager) -> PushRegistration {
        PushRegistration(api: api, permission: SystemNotificationPermission(), tokenSource: nil,
                         isEnabled: { [launch] in launch.config?.features.push == true },
                         isSignedIn: { [session] in session.isSignedIn },
                         language: { [languageManager] in languageManager.language })
    }

    /// The settings (G16): a deleted account, and the language switch.
    private func connectSettings() {
        // Deleted: the signed-out Home, without the welcome screen (screens.md §2 G16). After a lost
        // answer the retry's `401` already asked to sign in (`onSessionExpired`): the account is gone, so
        // that sheet closes (slice E, Retrying).
        session.onAccountDeleted = { [router, push, account] in
            push.sessionDidEnd()
            account.reset()
            router.closeSignIn()
            router.sessionDidEnd()
            router.selectedTab = .home
        }
        // Each sign-in, sign-up and launch with a session registers the push device again once the
        // permission is granted (slice C, Registering the device).
        session.onSessionStarted = { [push] in
            Task { await push.sessionDidStart() }
        }
        languageManager.onChange = { [apiSession, catalog, push, launch] language in
            apiSession.setLanguage(language)
            Task { await catalog.languageDidChange(to: language) }
            // The website links of `GET /config` carry the language (API 1.5.11).
            Task { await launch.languageDidChange() }
            // Pushes follow the new language (screens.md §0.8).
            Task { await push.languageDidChange() }
        }
    }
}
