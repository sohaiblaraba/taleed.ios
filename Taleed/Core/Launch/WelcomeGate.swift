import Foundation
import Observation

/// Whether the welcome screen (Figma Login) covers the shell for a signed-out member (decision 4):
/// shown at first launch and after sign-out; "Browse without signing in" and signing in skip it until
/// the next sign-out. A link that opens the app also skips it, for this launch only.
@MainActor
@Observable
final class WelcomeGate {
    private(set) var isVisible: Bool

    @ObservationIgnored private let defaults: UserDefaults
    static let storageKey = "welcome_done"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isVisible = !defaults.bool(forKey: Self.storageKey)
    }

    /// "Browse without signing in", or a sign-in or sign-up: not shown again until the next sign-out.
    func complete() {
        defaults.set(true, forKey: Self.storageKey)
        isVisible = false
    }

    /// A link opened the app: its target shows instead, without changing what the next launch shows.
    func skipForLink() {
        isVisible = false
    }

    /// The member signed out: the welcome screen shows again, now and at the next launches.
    func showAfterSignOut() {
        defaults.set(false, forKey: Self.storageKey)
        isVisible = true
    }
}
