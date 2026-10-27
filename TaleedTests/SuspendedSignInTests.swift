import Foundation
@testable import Taleed
import TaleedAPI
import Testing

/// A suspended member's sign-in answers `403 banned` with the session in `error.token` (contract 1.5.1):
/// the app keeps it, so the suspended screen offers the orders, the wallet and account deletion (Codex P2,
/// client feedback v1.0 A6).
@MainActor
struct SuspendedSignInTests {
    /// The body the server sends (`src/server/api/errors.ts`, `toBody`).
    private static let bannedWithToken = Data(
        #"{"error":{"code":"banned","message":"This account is suspended.","token":"Zx8qK2mN4pR7sT1vW3yA5bC6dE9fG0hJ"}}"#.utf8
    )
    private static let bannedWithoutToken = Data(#"{"error":{"code":"banned","message":"This account is suspended."}}"#.utf8)

    private let api = FakeTaleedApi()
    private let apiSession = ApiSession(environment: .fixture(), language: .fr, configuration: .init())

    @Test func bannedSignInBodyCarriesTheSession() {
        #expect(ApiError.suspendedSessionToken(status: 403, body: Self.bannedWithToken) == "Zx8qK2mN4pR7sT1vW3yA5bC6dE9fG0hJ")
        // Still `banned` for every other reader.
        #expect(ApiError.from(status: 403, body: Self.bannedWithToken) == .banned)
    }

    @Test func noSessionWithoutABannedToken() {
        #expect(ApiError.suspendedSessionToken(status: 403, body: Self.bannedWithoutToken) == nil)
        #expect(ApiError.suspendedSessionToken(status: 403, body: nil) == nil)
        let forbidden = Data(#"{"error":{"code":"forbidden","message":"No.","token":"t"}}"#.utf8)
        #expect(ApiError.suspendedSessionToken(status: 403, body: forbidden) == nil)
    }

    @Test func generatedClientErrorBecomesASuspendedSignIn() {
        let error = ErrorResponse.error(403, Self.bannedWithToken, nil, URLError(.badServerResponse))
        #expect(SignInAnswer.suspended(from: error) == .suspended(token: "Zx8qK2mN4pR7sT1vW3yA5bC6dE9fG0hJ"))

        let older = ErrorResponse.error(403, Self.bannedWithoutToken, nil, URLError(.badServerResponse))
        #expect(SignInAnswer.suspended(from: older) == nil)
        let wrongPassword = ErrorResponse.error(
            401, Data(#"{"error":{"code":"invalid_credentials","message":"Wrong."}}"#.utf8), nil, URLError(.badServerResponse)
        )
        #expect(SignInAnswer.suspended(from: wrongPassword) == nil)
    }

    @Test func suspendedSignInKeepsTheSessionAndShowsTheAccountLinks() async {
        let tokens = InMemoryTokenStore()
        api.signInResult = .success(.suspended(token: "suspended-token"))
        let session = SessionManager(api: api, apiSession: apiSession, tokenStore: tokens)
        let launch = LaunchViewModel(api: api, session: session, environment: .fixture())
        await launch.start()
        var started = 0
        session.onSessionStarted = { started += 1 }
        let viewModel = SignInViewModel(session: session)
        viewModel.email = "banned@example.com"
        viewModel.password = "secret"

        let closesSheet = await viewModel.submit()

        #expect(closesSheet)
        #expect(viewModel.errorKey == nil)
        #expect(launch.route == .suspended(RemoteConfig.fixture().support))
        #expect(session.state == .suspended)
        #expect(session.hasSuspendedSession)
        #expect(tokens.load() == "suspended-token")
        #expect(apiSession.token == "suspended-token")
        #expect(started == 0)
    }

    @Test func suspendedSignInThrowsBanned() async {
        api.signInResult = .success(.suspended(token: "suspended-token"))
        let session = SessionManager(api: api, apiSession: apiSession, tokenStore: InMemoryTokenStore())

        await #expect(throws: ApiError.banned) {
            try await session.signIn(email: "a@b.dz", password: "x")
        }
    }

    @Test func signOutFromTheSuspendedScreenRevokesTheSession() async {
        let tokens = InMemoryTokenStore()
        api.signInResult = .success(.suspended(token: "suspended-token"))
        let session = SessionManager(api: api, apiSession: apiSession, tokenStore: tokens)
        try? await session.signIn(email: "a@b.dz", password: "x")

        session.signOut()
        // The revocation runs in its own task.
        for _ in 0..<10 where api.signedOutTokens.isEmpty { await Task.yield() }

        #expect(session.state == .signedOut)
        #expect(tokens.load() == nil)
        #expect(api.signedOutTokens == ["suspended-token"])
    }
}
