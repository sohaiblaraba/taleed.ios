import Foundation
import Observation

/// Whether a member is signed in, and the actions that change it.
@MainActor
@Observable
final class SessionManager {
    enum State: Equatable {
        case signedOut
        case signedIn(User)
        /// The account is suspended (`403 banned`). Only signing out is offered.
        case suspended
    }

    private(set) var state: State = .signedOut

    var user: User? {
        if case let .signedIn(user) = state { return user }
        return nil
    }

    var isSignedIn: Bool { user != nil }

    /// Suspended while signed in (`GET /me` or another call answered `403 banned`): the token is kept,
    /// because orders, the wallet and account deletion still answer (api-guide.md, Suspended accounts).
    /// False when the suspension came from a sign-in, which creates no session.
    var hasSuspendedSession: Bool { state == .suspended && apiSession.token != nil }

    /// Called after the member signs out (Profile, the suspended screen): the welcome screen shows again
    /// (decision 4).
    @ObservationIgnored var onSignedOut: (() -> Void)?
    /// Called when the session of a signed-in member ends on its own (`401 unauthorized`): the app asks
    /// to sign in again (screens.md §0.6). Not called at launch, where a `401` continues signed out.
    @ObservationIgnored var onSessionExpired: (() -> Void)?
    /// Called just before the state becomes `.suspended`, in the same update: the suspended screen draws
    /// on the Profile stack, so a screen pushed there must leave it first (screens.md §0.6).
    @ObservationIgnored var onSuspended: (() -> Void)?

    @ObservationIgnored private let api: TaleedApi
    @ObservationIgnored private let apiSession: ApiSession
    @ObservationIgnored private let tokenStore: TokenStore

    init(api: TaleedApi, apiSession: ApiSession, tokenStore: TokenStore) {
        self.api = api
        self.apiSession = apiSession
        self.tokenStore = tokenStore
        api.onUnauthorized = { [weak self] rejectedToken in
            self?.handleUnauthorized(rejectedToken: rejectedToken)
        }
        api.onBanned = { [weak self] sentToken in
            self?.handleBanned(sentToken: sentToken)
        }
    }

    /// Launch step 3: with a stored token, asks `GET /me` who is signed in.
    /// Throws when no answer decides it (network, 5xx); the token is then kept for a retry.
    func restore() async throws(ApiError) {
        guard let token = tokenStore.load() else {
            state = .signedOut
            return
        }
        apiSession.setToken(token)
        do {
            state = .signedIn(try await api.me())
        } catch {
            switch error {
            case .unauthorized: clearSession()
            case .banned: suspend()
            default: throw error
            }
        }
    }

    /// Refreshes the member on return to the foreground. Failures other than a lost or
    /// suspended session change nothing. A suspended member who still has a session asks again too:
    /// a `200` means the suspension was lifted and the shell shows again; a `401` signs out.
    func refresh() async {
        guard isSignedIn || hasSuspendedSession else { return }
        do {
            state = .signedIn(try await api.me(automatic: true))
        } catch {
            if error == .banned, state != .suspended { suspend() }
            // `.unauthorized` is handled by `handleUnauthorized`.
        }
    }

    func signIn(email: String, password: String) async throws(ApiError) {
        do {
            let (token, user) = try await api.signIn(email: email, password: password)
            didAuthenticate(token: token, user: user)
        } catch {
            if error == .banned { suspend() }
            throw error
        }
    }

    /// Starts the session that a sign-in or a sign-up returned.
    func didAuthenticate(token: String, user: User) {
        tokenStore.save(token)
        apiSession.setToken(token)
        state = .signedIn(user)
    }

    /// Signs out at once and deletes the token whatever the server answers, even offline.
    func signOut() {
        let token = apiSession.token
        clearSession()
        onSignedOut?()
        guard let token else { return }
        let api = self.api
        // Push is off (`features.push`), so no device is registered: no `DELETE /devices` yet.
        Task { try? await api.signOut(token: token) }
    }

    /// A request carried a token that the API rejected: the session is gone.
    private func handleUnauthorized(rejectedToken: String) {
        // Ignore a late answer for a token that a new sign-in already replaced.
        guard apiSession.token == rejectedToken else { return }
        let hadSession = isSignedIn || hasSuspendedSession
        clearSession()
        if hadSession { onSessionExpired?() }
    }

    /// A signed-in request answered `403 banned`: the account was suspended meanwhile.
    private func handleBanned(sentToken: String) {
        guard apiSession.token == sentToken, isSignedIn else { return }
        suspend()
    }

    private func suspend() {
        onSuspended?()
        state = .suspended
    }

    private func clearSession() {
        tokenStore.delete()
        apiSession.setToken(nil)
        state = .signedOut
    }
}
