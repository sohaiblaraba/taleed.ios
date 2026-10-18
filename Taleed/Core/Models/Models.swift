import Foundation

// App models. View models and views use these, never the generated TaleedAPI types.

/// The signed-in member, from `GET /me` or `POST /auth/sign-in`.
struct User: Equatable, Sendable {
    let id: String
    /// Without the `@`. Null only for a few accounts older than usernames.
    let username: String?
    /// What to show for this member (`@username`).
    let displayName: String
    let avatarURL: URL?
    let isVerified: Bool
    let isOfficial: Bool

    /// `@username`, or nil for the few accounts without a username.
    var handle: String? { username.map { "@\($0)" } }
}

/// The parts of `GET /config` that the app uses so far.
struct RemoteConfig: Equatable, Sendable {
    let minimumVersion: String
    let support: SupportContacts
}

struct SupportContacts: Equatable, Sendable {
    let email: String
    let phone: String
    let whatsappURL: URL?
}

/// A top-level category from `GET /catalog`, named in the app language.
struct CatalogCategory: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}
