import Foundation

/// Builds the app's objects once, with constructor injection.
@MainActor
final class AppContainer {
    let environment: AppEnvironment
    let languageManager: LanguageManager
    let apiSession: ApiSession
    let api: TaleedApi
    let session: SessionManager
    let launch: LaunchViewModel
    let home: HomeViewModel
    let router = ShellRouter()

    init(environment: AppEnvironment = .current(), tokenStore: TokenStore = KeychainTokenStore()) {
        self.environment = environment
        languageManager = LanguageManager()
        apiSession = ApiSession(environment: environment, language: languageManager.language)
        api = GeneratedTaleedApi(session: apiSession)
        session = SessionManager(api: api, apiSession: apiSession, tokenStore: tokenStore)
        launch = LaunchViewModel(api: api, session: session, environment: environment)
        home = HomeViewModel(api: api)

        #if DEBUG
        DebugLaunchOptions.apply(to: router)
        #endif

        languageManager.onChange = { [apiSession, home] language in
            apiSession.setLanguage(language)
            Task { await home.load() }
        }
    }
}
