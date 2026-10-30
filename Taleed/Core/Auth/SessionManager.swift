import Foundation
import Observation

/// Whether a member is signed in, and the actions that change it.
@MainActor
@Observable
final class SessionManager {
    enum State: Equatable {
        case signedOut
        case signedIn(User)
        /// The account is suspended (`403 banned`). With a session (`hasSuspendedSession`), the orders,
        /// the wallet, account deletion and signing out are offered; without one, only the support contacts.
        case suspended
    }

    private(set) var state: State = .signedOut

    var user: User? {
        if case let .signedIn(user) = state { return user }
        return nil
    }

    var isSignedIn: Bool { user != nil }

    /// Suspended with a session: the token is kept, because orders, the wallet and account deletion still
    /// answer (api-guide.md, Suspended accounts). The token is the one the member had when a call answered
    /// `403 banned`, or the one a `banned` sign-in returned in `error.token` (contract 1.5.1). False only
    /// when an older server answered a sign-in `banned` without a token.
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
    /// Called after the member deleted their account: the signed-out Home, without the welcome screen.
    @ObservationIgnored var onAccountDeleted: (() -> Void)?
    /// Called when a suspended member's session works again (`GET /me` answered `200`), just after the
    /// state changed: the shell shows again, with a link that waited meanwhile.
    @ObservationIgnored var onSuspensionLifted: (() -> Void)?
    /// Called when a session starts: a sign-in, a sign-up, or launch with a stored token that `GET /me`
    /// accepted (the push device registers again, slice C).
    @ObservationIgnored var onSessionStarted: (() -> Void)?
    /// Called whenever the session ends (sign-out, a rejected token, account deletion): signs out of the
    /// Google SDK, so the next "Continue with Google" shows the account chooser (slice G, Signing out).
    /// Apple has no sign-out call.
    @ObservationIgnored var signOutOfProviders: (() -> Void)?

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
            let user = try await api.me()
            // A sign-out or another sign-in during the call: that session wins, the answer is dropped.
            guard isCurrent(token) else { return }
            state = .signedIn(user)
            onSessionStarted?()
        } catch {
            guard isCurrent(token) else { return }
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
    /// An answer that comes after a sign-out or another sign-in is dropped (it belongs to the old session).
    func refresh() async {
        guard isSignedIn || hasSuspendedSession, let token = apiSession.token else { return }
        do {
            let user = try await api.me(automatic: true)
            guard isCurrent(token) else { return }
            let wasSuspended = state == .suspended
            state = .signedIn(user)
            if wasSuspended { onSuspensionLifted?() }
        } catch {
            guard isCurrent(token) else { return }
            if error == .banned, state != .suspended { suspend() }
            // `.unauthorized` is handled by `handleUnauthorized`.
        }
    }

    /// The badges an action answered (`POST /conversations/{id}/read`, `POST /notifications/read`): the
    /// Messages tab and the bell show them at once, without `GET /me`.
    func updateUnreadCounts(messages: Int, notifications: Int) {
        guard case var .signedIn(user) = state else { return }
        user.unreadMessages = max(0, messages)
        user.unreadNotifications = max(0, notifications)
        if case let .signedIn(current) = state, current == user { return }
        state = .signedIn(user)
    }

    /// The member as an action answered it (`PATCH /me`, `POST /me/username`): the new avatar, handle and
    /// wilaya show everywhere at once.
    func updateUser(_ user: User) {
        guard case let .signedIn(current) = state, current.id == user.id, current != user else { return }
        state = .signedIn(user)
    }

    /// `POST /me/delete` answered `204`: the server ended every session, so nothing is called; the token
    /// and the member's data leave the device, and the signed-out Home shows (slice E, Deleting the account).
    func accountDeleted() {
        clearSession()
        onAccountDeleted?()
    }

    /// A suspended member gets `banned` with a session (contract 1.5.1): the token is stored like any
    /// session token, then the suspended screen shows with the account links, and `.banned` is thrown so
    /// that the form closes. A `banned` without a token (an older server) leaves no session.
    func signIn(email: String, password: String) async throws(ApiError) {
        let answer: SignInAnswer
        do {
            answer = try await api.signIn(email: email, password: password)
        } catch {
            if error == .banned { suspend() }
            throw error
        }
        switch answer {
        case let .session(token, user):
            didAuthenticate(token: token, user: user)
        case let .suspended(token):
            didSignInSuspended(token: token)
            throw .banned
        }
    }

    /// A sign-in answered `403 banned` (email, Google or Apple): with a token, it is stored like any session
    /// token; then the suspended screen shows. Without one (an older server), no session is kept.
    func didSignInSuspended(token: String?) {
        if let token {
            tokenStore.save(token)
            apiSession.setToken(token)
        }
        suspend()
    }

    /// Starts the session that a sign-in or a sign-up returned.
    func didAuthenticate(token: String, user: User) {
        tokenStore.save(token)
        apiSession.setToken(token)
        state = .signedIn(user)
        onSessionStarted?()
    }

    /// Signs out at once and deletes the token whatever the server answers, even offline.
    func signOut() {
        let token = apiSession.token
        clearSession()
        onSignedOut?()
        guard let token else { return }
        let api = self.api
        // Pushes stop with the session, without a call (slice C, Registering the device).
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

    /// Whether `token` is still the session's token: no sign-out or other sign-in happened meanwhile.
    private func isCurrent(_ token: String) -> Bool {
        apiSession.token == token
    }

    private func suspend() {
        onSuspended?()
        state = .suspended
    }

    private func clearSession() {
        tokenStore.delete()
        apiSession.setToken(nil)
        state = .signedOut
        signOutOfProviders?()
    }
}
