import Foundation

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
    let router = AppRouter()
    let toasts: AppToasts
    let uploads: PhotoUploadService

    init(environment: AppEnvironment = .current(), tokenStore: TokenStore = KeychainTokenStore()) {
        ImageLoading.configure()
        self.environment = environment
        languageManager = LanguageManager()
        apiSession = ApiSession(environment: environment, language: languageManager.language)
        api = GeneratedTaleedApi(session: apiSession)
        session = SessionManager(api: api, apiSession: apiSession, tokenStore: tokenStore)
        launch = LaunchViewModel(api: api, session: session, environment: environment)
        catalog = CatalogStore(api: api, language: languageManager.language)
        home = HomeViewModel(catalog: catalog)
        toasts = AppToasts(languageManager: languageManager)
        uploads = PhotoUploadService(api: api)

        router.isSignedIn = { [session] in session.isSignedIn }
        router.resolveConversation = { [api] (listingId: String, buyerId: String) async throws(ApiError) -> String in
            try await api.openConversation(listingId: listingId, buyerId: buyerId)
        }
        router.websiteLinks = { [launch] in launch.config?.links ?? WebsiteLinks() }

        #if DEBUG
        DebugLaunchOptions.apply(to: router)
        #endif

        languageManager.onChange = { [apiSession, catalog] language in
            apiSession.setLanguage(language)
            Task { await catalog.languageDidChange(to: language) }
        }
    }
}
