import Foundation
@testable import Taleed
import Testing

/// A `GET /me` answer that comes after the session changed belongs to the old session: it never brings
/// that session back, signs out or suspends the new one (Codex P1, client feedback v1.0 A4).
@MainActor
struct SessionRaceTests {
    private let api = FakeTaleedApi()
    private let apiSession = ApiSession(environment: .fixture(), language: .fr, configuration: .init())
    private let tokens = InMemoryTokenStore(token: "old-token")

    /// Signed in as `amina` with `old-token`.
    private func signedInSession() async throws -> SessionManager {
        let session = SessionManager(api: api, apiSession: apiSession, tokenStore: tokens)
        api.sentToken = { [apiSession] in apiSession.token }
        try await session.restore()
        #expect(session.user?.username == "amina")
        return session
    }

    /// While `GET /me` is in flight: `amina` signs out and `karim` signs in with `new-token`.
    private func switchMember(_ session: SessionManager) {
        api.signInResult = .success(.session(token: "new-token", user: .fixture(username: "karim")))
        api.whileMeIsInFlight = {
            session.signOut()
            try? await session.signIn(email: "karim@example.com", password: "sample-pass-1")
        }
    }

    private func expectKarimSignedIn(_ session: SessionManager) {
        #expect(session.user?.username == "karim")
        #expect(apiSession.token == "new-token")
        #expect(tokens.load() == "new-token")
    }

    @Test func signOutDuringRefreshStaysSignedOut() async throws {
        let session = try await signedInSession()
        api.meResult = .success(.fixture(username: "amina2"))
        api.whileMeIsInFlight = { session.signOut() }

        await session.refresh()

        #expect(session.state == .signedOut)
        #expect(apiSession.token == nil)
        #expect(tokens.load() == nil)
    }

    @Test func newSignInDuringRefreshKeepsTheNewMember() async throws {
        let session = try await signedInSession()
        api.meResult = .success(.fixture(username: "amina2"))
        switchMember(session)

        await session.refresh()

        expectKarimSignedIn(session)
    }

    @Test func late401AfterANewSignInKeepsTheNewSession() async throws {
        let session = try await signedInSession()
        var expired = 0
        session.onSessionExpired = { expired += 1 }
        api.meResult = .failure(.unauthorized)
        switchMember(session)

        await session.refresh()

        expectKarimSignedIn(session)
        #expect(expired == 0)
    }

    @Test func lateBannedAfterANewSignInKeepsTheNewSession() async throws {
        let session = try await signedInSession()
        var suspended = 0
        session.onSuspended = { suspended += 1 }
        api.meResult = .failure(.banned)
        switchMember(session)

        await session.refresh()

        expectKarimSignedIn(session)
        #expect(suspended == 0)
    }

    @Test func lateBannedAfterASignOutStaysSignedOut() async throws {
        let session = try await signedInSession()
        api.meResult = .failure(.banned)
        api.whileMeIsInFlight = { session.signOut() }

        await session.refresh()

        #expect(session.state == .signedOut)
        #expect(!session.hasSuspendedSession)
    }

    @Test func launchAnswerAfterANewSignInKeepsTheNewMember() async throws {
        let session = SessionManager(api: api, apiSession: apiSession, tokenStore: tokens)
        api.sentToken = { [apiSession] in apiSession.token }
        api.meResult = .failure(.banned)
        switchMember(session)

        try await session.restore()

        expectKarimSignedIn(session)
    }

    @Test func launchAnswerAfterASignOutStaysSignedOut() async throws {
        let session = SessionManager(api: api, apiSession: apiSession, tokenStore: tokens)
        api.sentToken = { [apiSession] in apiSession.token }
        api.whileMeIsInFlight = { session.signOut() }

        try await session.restore()

        #expect(session.state == .signedOut)
        #expect(tokens.load() == nil)
    }

    @Test func refreshWithoutAChangeStillApplies() async throws {
        let session = try await signedInSession()
        api.meResult = .success(.fixture(username: "amina2"))

        await session.refresh()

        #expect(session.user?.username == "amina2")
    }
}
