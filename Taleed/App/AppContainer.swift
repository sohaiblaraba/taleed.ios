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
    /// Brands and sizes of the Explore filter sheet.
    let exploreReferences: ExploreReferenceStore
    let router = AppRouter()
    let toasts: AppToasts
    let uploads: PhotoUploadService
    let welcome: WelcomeGate

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
        session.onSignedOut = { [welcome, router] in
            welcome.showAfterSignOut()
            router.sessionDidEnd()
            router.selectedTab = .home
        }
        // From the suspended screen the shell was not on screen to see the session end: leave the
        // screens that need an account here too.
        session.onSessionExpired = { [router] in
            router.sessionDidEnd()
            router.presentSignIn()
        }
        // The suspended screen is the root of the Profile stack: nothing may cover it (screens.md §0.6).
        session.onSuspended = { [router] in router.popToRoot(.profile) }
        router.resolveConversation = { [api] (listingId: String, buyerId: String) async throws(ApiError) -> String in
            try await api.openConversation(listingId: listingId, buyerId: buyerId)
        }
        router.websiteLinks = { [launch] in launch.config?.links ?? WebsiteLinks() }
        favorites.onFailure = { [toasts] error in toasts.show(error: error) }
        favorites.onRemoved = { [toasts, languageManager] _ in
            toasts.show(languageManager.string(.appNotFoundTitle), kind: .info)
        }

        #if DEBUG
        DebugLaunchOptions.apply(to: router)
        #endif

        languageManager.onChange = { [apiSession, catalog] language in
            apiSession.setLanguage(language)
            Task { await catalog.languageDidChange(to: language) }
        }
    }
}
