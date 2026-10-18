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
}
