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
            case .banned: state = .suspended
            default: throw error
            }
        }
    }

    /// Refreshes the member on return to the foreground. Failures other than a lost or
    /// suspended session change nothing.
    func refresh() async {
        guard isSignedIn else { return }
        do {
            state = .signedIn(try await api.me(automatic: true))
        } catch {
            if error == .banned { state = .suspended }
            // `.unauthorized` is handled by `handleUnauthorized`.
        }
    }

    func signIn(email: String, password: String) async throws(ApiError) {
        do {
            let (token, user) = try await api.signIn(email: email, password: password)
            tokenStore.save(token)
            apiSession.setToken(token)
            state = .signedIn(user)
        } catch {
            if error == .banned { state = .suspended }
            throw error
        }
    }

    /// Signs out at once and deletes the token whatever the server answers, even offline.
    func signOut() {
        let token = apiSession.token
        clearSession()
        guard let token else { return }
        let api = self.api
        Task { try? await api.signOut(token: token) }
    }

    /// A request carried a token that the API rejected: the session is gone.
    private func handleUnauthorized(rejectedToken: String) {
        // Ignore a late answer for a token that a new sign-in already replaced.
        guard apiSession.token == rejectedToken else { return }
        clearSession()
    }

    private func clearSession() {
        tokenStore.delete()
        apiSession.setToken(nil)
        state = .signedOut
    }
}
