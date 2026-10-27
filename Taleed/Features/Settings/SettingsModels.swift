import Foundation

/// The signed-in member's account as the settings show it: `GET /me` with the private fields (slice E,
/// The profile). `User` is the part the rest of the app needs.
struct AccountProfile: Equatable, Sendable {
    let id: String
    let username: String?
    let displayName: String
    let avatarURL: URL?
    let isVerified: Bool
    let isOfficial: Bool
    let email: String
    let emailVerified: Bool
    /// The legal name as the form edits it: the stored name split on its first space.
    let firstName: String
    let lastName: String
    let bio: String?
    /// Normalized by the server (`0550123456`). Private.
    let phone: String?
    let wilaya: CatalogWilaya?
    /// When the username can change again; nil when it can change now.
    let usernameNextChangeAt: Date?
    /// `preferences.newsletter`.
    let newsletter: Bool
    /// False for a member who only ever signed in with Google or Apple (slice G, Members without a
    /// password): no password change and no password to delete the account.
    var hasPassword = true
    var unreadMessages = 0
    var unreadNotifications = 0

    /// The member for the rest of the app (the tabs' badges, the avatar, Home's wilaya).
    var user: User {
        User(id: id, username: username, displayName: displayName, avatarURL: avatarURL, isVerified: isVerified,
             isOfficial: isOfficial, unreadMessages: unreadMessages, unreadNotifications: unreadNotifications,
             wilayaId: wilaya?.id)
    }

    /// `@username`, or nil for the few accounts without a username.
    var handle: String? { username.map { "@\($0)" } }

    /// Whether the username is in its 30-day cooldown at `now`.
    func usernameLocked(at now: Date = .now) -> Bool {
        guard let next = usernameNextChangeAt else { return false }
        return next > now
    }
}

/// `GET /me/billing` (slice E, Billing details). Every field is optional.
struct BillingInfo: Equatable, Sendable {
    var name: String?
    var address: String?
    var commune: String?
    var wilayaId: Int?
    var zip: String?
}

/// `PATCH /me`: only the fields that changed. An empty string removes `bio`, `phone` and the photo
/// (`avatarKey`); `wilayaId` 0 removes the wilaya.
struct ProfileChanges: Equatable, Sendable {
    var firstName: String?
    var lastName: String?
    var bio: String?
    var phone: String?
    var wilayaId: Int?
    var avatarKey: String?

    var isEmpty: Bool { self == ProfileChanges() }
}

/// `POST /me/addresses`.
struct AddressInput: Equatable, Sendable {
    let recipientName: String
    let phone: String
    let wilayaId: Int
    let communeId: Int
    let addressLine: String
    let isDefault: Bool
}

/// `PATCH /me/addresses/{id}`: only the fields to change. A new wilaya carries its commune.
struct AddressChanges: Equatable, Sendable {
    var recipientName: String?
    var phone: String?
    var wilayaId: Int?
    var communeId: Int?
    var addressLine: String?
    var isDefault: Bool?

    var isEmpty: Bool { self == AddressChanges() }
}

/// A row of `GET /me/blocks`. Its id is the member's.
struct BlockedMemberRow: Identifiable, Equatable, Sendable {
    let id: String
    /// Nil only for the few accounts older than usernames: they cannot be unblocked by name.
    let username: String?
    let displayName: String
    let avatarURL: URL?
    let isVerified: Bool
    let isOfficial: Bool
    let blockedAt: Date
}
