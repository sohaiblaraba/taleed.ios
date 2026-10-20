import Foundation
import Observation

/// The signed-in member's account (`GET /me` with its private fields), shared by the settings screens:
/// the hub's rows, the profile, username, email and password screens. Every change the API answers
/// with `Me` lands here and in `SessionManager.user`, so the avatar, the handle and Home's wilaya follow.
@MainActor
@Observable
final class AccountStore {
    private(set) var profile: AccountProfile?
    /// The first load failed and nothing is on screen.
    private(set) var loadError: ApiError?
    private(set) var isLoading = false
    /// The newsletter switch while its change is on its way (optimistic, as the website's).
    private(set) var newsletterPending: Bool?

    @ObservationIgnored private let api: AccountApi
    @ObservationIgnored private let session: SessionManager

    init(api: AccountApi, session: SessionManager) {
        self.api = api
        self.session = session
    }

    /// Loads the account when it is not there yet, or belongs to another member.
    func loadIfNeeded() async {
        guard let user = session.user else {
            reset()
            return
        }
        if profile?.id == user.id { return }
        if profile != nil { reset() }
        guard !isLoading else { return }
        await reload()
    }

    /// Loads again. `automatic`: back in the foreground; a failure then keeps what is on screen quietly.
    /// Returns the error when one stopped it.
    @discardableResult
    func reload(automatic: Bool = false) async -> ApiError? {
        guard session.isSignedIn else { return nil }
        isLoading = true
        defer { isLoading = false }
        do {
            apply(try await api.account(automatic: automatic))
            loadError = nil
            return nil
        } catch {
            if profile == nil { loadError = error }
            return error
        }
    }

    func retry() async {
        loadError = nil
        await reload()
    }

    /// An answer of the API with the whole account (`PATCH /me`, `POST /me/username`…).
    func apply(_ profile: AccountProfile) {
        guard session.user == nil || session.user?.id == profile.id else { return }
        self.profile = profile
        session.updateUser(profile.user)
    }

    /// `PATCH /me/preferences {newsletter}`. The switch shows the new value at once and is disabled
    /// meanwhile; a failure (offline included) puts it back: returns false, and the screen shows
    /// `newsletter.error`.
    func setNewsletter(_ isOn: Bool) async -> Bool {
        guard newsletterPending == nil, profile != nil else { return true }
        newsletterPending = isOn
        defer { newsletterPending = nil }
        do {
            #if DEBUG
            try SettingsDebugFailures.fail(.newsletter)
            #endif
            apply(try await api.setNewsletter(isOn))
            return true
        } catch {
            return false
        }
    }

    /// Signed out, or the account was deleted: nothing of it stays on the device.
    func reset() {
        profile = nil
        loadError = nil
        newsletterPending = nil
    }
}
