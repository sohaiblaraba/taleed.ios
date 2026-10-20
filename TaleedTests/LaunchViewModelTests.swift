import Foundation
@testable import Taleed
import Testing

@MainActor
struct LaunchViewModelTests {
    private let api = FakeTaleedApi()
    private let apiSession = ApiSession(
        environment: .fixture(),
        language: .fr,
        configuration: .init()
    )

    private func makeLaunch(
        appVersion: String = "1.0.0",
        tokenStore: TokenStore
    ) -> (LaunchViewModel, SessionManager) {
        let session = SessionManager(api: api, apiSession: apiSession, tokenStore: tokenStore)
        api.sentToken = { [apiSession] in apiSession.token }
        let launch = LaunchViewModel(api: api, session: session, environment: .fixture(appVersion: appVersion))
        return (launch, session)
    }

    @Test func versionBelowMinimumRequiresUpdate() async {
        api.configResult = .success(.fixture(minimumVersion: "1.2.0"))
        let (launch, _) = makeLaunch(appVersion: "1.1.9", tokenStore: InMemoryTokenStore(token: "t"))

        await launch.start()

        #expect(launch.route == .updateRequired)
        #expect(api.meCalls == 0)
    }

    @Test func tokenAnd401SignsOutAndDeletesToken() async {
        let tokens = InMemoryTokenStore(token: "expired")
        api.meResult = .failure(.unauthorized)
        let (launch, session) = makeLaunch(tokenStore: tokens)

        await launch.start()

        #expect(launch.route == .main)
        #expect(session.state == .signedOut)
        #expect(tokens.load() == nil)
        #expect(apiSession.token == nil)
    }

    @Test func tokenAnd403BannedShowsSuspended() async {
        let tokens = InMemoryTokenStore(token: "t")
        api.meResult = .failure(.banned)
        let (launch, session) = makeLaunch(tokenStore: tokens)

        await launch.start()

        #expect(session.state == .suspended)
        #expect(launch.route == .suspended(RemoteConfig.fixture().support))
    }

    @Test func tokenAnd200SignsIn() async {
        let (launch, session) = makeLaunch(tokenStore: InMemoryTokenStore(token: "t"))

        await launch.start()

        #expect(launch.route == .main)
        #expect(session.user == .fixture())
        #expect(apiSession.token == "t")
    }

    @Test func networkErrorOnMeKeepsTokenAndOffersRetry() async {
        let tokens = InMemoryTokenStore(token: "t")
        api.meResult = .failure(.network)
        let (launch, _) = makeLaunch(tokenStore: tokens)

        await launch.start()

        #expect(launch.route == .failed(.network))
        #expect(tokens.load() == "t")
    }

    @Test func networkErrorOnConfigOffersRetry() async {
        api.configResult = .failure(.network)
        let (launch, _) = makeLaunch(tokenStore: InMemoryTokenStore())

        await launch.start()

        #expect(launch.route == .failed(.network))
    }

    @Test func noTokenGoesToShellSignedOut() async {
        let (launch, session) = makeLaunch(tokenStore: InMemoryTokenStore())

        await launch.start()

        #expect(launch.route == .main)
        #expect(session.state == .signedOut)
        #expect(api.meCalls == 0)
    }

    @Test func returnToForegroundRefreshesTheMember() async {
        let (launch, session) = makeLaunch(tokenStore: InMemoryTokenStore(token: "t"))
        await launch.start()
        api.meResult = .success(.fixture(username: "amina2"))

        await launch.didReturnToForeground()

        #expect(api.meCalls == 2)
        #expect(session.user?.username == "amina2")
    }

    @Test func unauthorizedOnAnyCallSignsOut() async {
        let tokens = InMemoryTokenStore(token: "t")
        let (launch, session) = makeLaunch(tokenStore: tokens)
        await launch.start()
        api.meResult = .failure(.unauthorized)

        await launch.didReturnToForeground()

        #expect(session.state == .signedOut)
        #expect(tokens.load() == nil)
    }

    @Test func late401ForAnOldTokenKeepsTheNewSession() async throws {
        let tokens = InMemoryTokenStore()
        let (launch, session) = makeLaunch(tokenStore: tokens)
        await launch.start()
        try await session.signIn(email: "amina@example.com", password: "sample-pass-1")

        api.onUnauthorized?("old-token")

        #expect(session.isSignedIn)
        #expect(tokens.load() == "new-token")
        #expect(apiSession.token == "new-token")
    }

    @Test func bannedSignInShowsSuspendedWithoutToken() async {
        let tokens = InMemoryTokenStore()
        api.signInResult = .failure(.banned)
        let (launch, session) = makeLaunch(tokenStore: tokens)
        await launch.start()
        let viewModel = SignInViewModel(session: session)
        viewModel.email = "banned@example.com"
        viewModel.password = "secret"

        let closesSheet = await viewModel.submit()

        #expect(closesSheet)
        #expect(launch.route == .suspended(RemoteConfig.fixture().support))
        #expect(tokens.load() == nil)
    }

    @Test(arguments: [
        (ApiError.invalidCredentials, L10nKey.authErrorInvalidCredentials),
        (ApiError.rateLimited(retryAfter: 60), L10nKey.authErrorRateLimited),
        (ApiError.network, L10nKey.commonErrorNetwork),
        (ApiError.server(status: 500), L10nKey.commonErrorGeneric),
    ])
    func signInErrorMessages(error: ApiError, key: L10nKey) {
        #expect(SignInViewModel.messageKey(for: error) == key)
    }

    @Test func signOutDeletesTokenAndRevokesSession() async throws {
        let tokens = InMemoryTokenStore(token: "t")
        let (launch, session) = makeLaunch(tokenStore: tokens)
        await launch.start()

        session.signOut()
        try await Task.sleep(for: .milliseconds(50))

        #expect(session.state == .signedOut)
        #expect(tokens.load() == nil)
        #expect(api.signedOutTokens == ["t"])
    }

    @Test func signOutCallsBackForTheWelcomeScreen() async {
        let (launch, session) = makeLaunch(tokenStore: InMemoryTokenStore(token: "t"))
        await launch.start()
        var signedOut = 0
        session.onSignedOut = { signedOut += 1 }

        session.signOut()

        #expect(signedOut == 1)
    }

    @Test func bannedWhileSignedInShowsSuspendedAndKeepsTheToken() async {
        let tokens = InMemoryTokenStore(token: "t")
        let (launch, session) = makeLaunch(tokenStore: tokens)
        await launch.start()

        api.onBanned?("t")

        #expect(session.state == .suspended)
        #expect(session.hasSuspendedSession)
        #expect(launch.route == .suspended(RemoteConfig.fixture().support))
        #expect(tokens.load() == "t")
    }

    @Test func bannedForAnOldTokenChangesNothing() async {
        let (launch, session) = makeLaunch(tokenStore: InMemoryTokenStore(token: "t"))
        await launch.start()

        api.onBanned?("old")

        #expect(session.isSignedIn)
    }

    @Test func expiredSessionAsksToSignInAgainButNotAtLaunch() async {
        let tokens = InMemoryTokenStore(token: "expired")
        api.meResult = .failure(.unauthorized)
        let (launch, session) = makeLaunch(tokenStore: tokens)
        var expired = 0
        session.onSessionExpired = { expired += 1 }

        await launch.start()
        #expect(expired == 0)

        api.meResult = .success(.fixture())
        try? await session.signIn(email: "a@b.dz", password: "x")
        api.onUnauthorized?("new-token")
        #expect(expired == 1)
        #expect(!session.isSignedIn)
    }

    @Test func everySuspensionCallsBackFirst() async throws {
        // Launch: `GET /me` answers `403 banned`.
        api.meResult = .failure(.banned)
        let (launch, session) = makeLaunch(tokenStore: InMemoryTokenStore(token: "t"))
        var statesSeen: [SessionManager.State] = []
        session.onSuspended = { statesSeen.append(session.state) }
        await launch.start()
        #expect(statesSeen == [.signedOut])

        // While signed in: another call answers `403 banned`.
        api.meResult = .success(.fixture())
        await launch.start()
        api.onBanned?("t")
        #expect(statesSeen.count == 2)
        #expect(session.state == .suspended)

        // At sign-in.
        session.signOut()
        api.signInResult = .failure(.banned)
        try? await session.signIn(email: "a@b.dz", password: "x")
        #expect(statesSeen.count == 3)
    }

    @Test func liftedSuspensionShowsTheShellOnReturnToForeground() async {
        api.meResult = .failure(.banned)
        let (launch, session) = makeLaunch(tokenStore: InMemoryTokenStore(token: "t"))
        await launch.start()
        #expect(launch.route == .suspended(RemoteConfig.fixture().support))

        await launch.didReturnToForeground()
        #expect(session.state == .suspended)

        api.meResult = .success(.fixture())
        await launch.didReturnToForeground()
        #expect(launch.route == .main)
        #expect(session.user == .fixture())
    }

    @Test func endedSuspendedSessionSignsOutOnReturnToForeground() async {
        let tokens = InMemoryTokenStore(token: "t")
        api.meResult = .failure(.banned)
        let (launch, session) = makeLaunch(tokenStore: tokens)
        var expired = 0
        session.onSessionExpired = { expired += 1 }
        await launch.start()

        api.meResult = .failure(.unauthorized)
        await launch.didReturnToForeground()

        #expect(session.state == .signedOut)
        #expect(tokens.load() == nil)
        #expect(launch.route == .main)
        #expect(expired == 1)
    }

    @Test func suspendedAtSignInDoesNotAskAgainOnReturnToForeground() async {
        api.signInResult = .failure(.banned)
        let (launch, session) = makeLaunch(tokenStore: InMemoryTokenStore())
        await launch.start()
        try? await session.signIn(email: "a@b.dz", password: "x")

        await launch.didReturnToForeground()

        #expect(api.meCalls == 0)
        #expect(session.state == .suspended)
    }

    @Test func storeURLComesFromTheAppStoreID() {
        func environment(_ id: String?) -> AppEnvironment {
            AppEnvironment(apiBaseURL: URL(string: "http://localhost:3000/api/v1")!, appVersion: "1.0.0",
                           buildNumber: "1", appStoreID: id)
        }
        #expect(environment("6450000000").appStoreURL == URL(string: "https://apps.apple.com/app/id6450000000"))
        #expect(environment(nil).appStoreURL == nil)
        #expect(environment("").appStoreURL == nil)
        #expect(environment("$(TALEED_APP_STORE_ID)").appStoreURL == nil)
    }

    @Test func suspendedAtSignInHasNoSession() async {
        api.signInResult = .failure(.banned)
        let (launch, session) = makeLaunch(tokenStore: InMemoryTokenStore())
        await launch.start()

        try? await session.signIn(email: "a@b.dz", password: "x")

        #expect(session.state == .suspended)
        #expect(!session.hasSuspendedSession)
    }
}

/// The language changed in Settings: `GET /config` again, for links in the new language (API 1.5.11).
extension LaunchViewModelTests {
    @Test func languageChangeReloadsTheConfigLinks() async {
        let (launch, _) = makeLaunch(tokenStore: InMemoryTokenStore())
        await launch.start()
        var english = RemoteConfig.fixture()
        english.links.terms = URL(string: "http://localhost:3000/en/terms")
        api.configResult = .success(english)

        await launch.languageDidChange()

        #expect(launch.config?.links.terms == URL(string: "http://localhost:3000/en/terms"))
        #expect(launch.route == .main)
    }

    @Test func languageChangeKeepsTheConfigWhenTheReloadFails() async {
        var french = RemoteConfig.fixture()
        french.links.terms = URL(string: "http://localhost:3000/fr/terms")
        api.configResult = .success(french)
        let (launch, _) = makeLaunch(tokenStore: InMemoryTokenStore())
        await launch.start()
        api.configResult = .failure(.network)

        await launch.languageDidChange()

        #expect(launch.config?.links.terms == URL(string: "http://localhost:3000/fr/terms"))
        #expect(launch.route == .main)
    }
}
