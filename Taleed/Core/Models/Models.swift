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
    /// `counts` of `GET /me`: the Messages tab and the bell badges.
    var unreadMessages = 0
    var unreadNotifications = 0
    /// The member's wilaya code (profile), nil when not set: the Sell form's shipping wilaya.
    var wilayaId: Int?

    /// `@username`, or nil for the few accounts without a username.
    var handle: String? { username.map { "@\($0)" } }
}

/// `GET /config`, the first call of every launch (api-guide.md, Remote configuration).
struct RemoteConfig: Equatable, Sendable {
    let minimumVersion: String
    let support: SupportContacts
    /// Invite-only period: the request-access form replaces sign-up.
    var betaMode = false
    var features = RemoteFeatures()
    /// The payment methods turned on (`mock`, `cod`, `chargily`, `slickpay`), as the API names them.
    var paymentMethods: [String] = []
    /// Website pages to open in the in-app browser, in the response language.
    var links = WebsiteLinks()
}

/// `features` of `GET /config`: hide what is off.
struct RemoteFeatures: Equatable, Sendable {
    var visualSearch = false
    var push = false
}

/// `links` of `GET /config`. Open them with `InAppBrowser` (never in an embedded web view).
struct WebsiteLinks: Equatable, Sendable {
    var website: URL?
    var terms: URL?
    var privacy: URL?
    var buyerProtection: URL?
    var guides: URL?

    func url(for page: WebsitePage) -> URL? {
        switch page {
        case .website: website
        case .terms: terms
        case .privacy: privacy
        case .buyerProtection: buyerProtection
        case .guides: guides
        }
    }
}

/// The website pages the app shows in the in-app browser.
enum WebsitePage: String, CaseIterable, Sendable {
    case website, terms, privacy, buyerProtection, guides
}

struct SupportContacts: Equatable, Sendable {
    let email: String
    let phone: String
    let whatsappURL: URL?
}

/// A page of a list (api-guide.md, Pagination). `nextCursor` is nil on the last page.
struct Page<Item: Sendable>: Sendable {
    let items: [Item]
    let nextCursor: String?
    /// The items across all pages ("132 results").
    let total: Int
}

extension Page: Equatable where Item: Equatable {}
