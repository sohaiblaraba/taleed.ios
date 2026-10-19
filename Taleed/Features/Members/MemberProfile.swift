import Foundation

/// A member's public profile (`GET /members/{username}`, slice A "Member profile", slice C "Blocking").
/// Every permission comes from the server's flags (screens.md §0.1): `isMe`, `isFollowing`, `isBlocked`,
/// `canBundle`. Never a real name (screens.md §0.3).
struct MemberProfile: Identifiable, Equatable, Sendable {
    /// The member's `id`: what a report names (`memberId`), never the username.
    let id: String
    /// The current username, without `@`. A former one still opens the profile and answers this one:
    /// use it from then on.
    let username: String
    let displayName: String
    let avatarURL: URL?
    let isVerified: Bool
    let isOfficial: Bool
    let bio: String?
    let wilaya: CatalogWilaya?
    let memberSince: Date
    let lastSeenAt: Date?
    let isOnline: Bool
    /// Nil until the first review.
    let rating: MemberRating?
    /// COMPLETED sales.
    let salesCount: Int
    var followersCount: Int
    let followingCount: Int
    /// The "verified information" list.
    let checks: MemberChecks
    /// The signed-in member's own profile.
    let isMe: Bool
    var isFollowing: Bool
    /// The signed-in member blocked this member (never says whether the other side blocked them).
    let isBlocked: Bool
    let canBundle: Bool
    /// The signed-in member's bundle in progress with this seller.
    let openBundleId: String?
    /// The member's items across the wardrobe (active, reserved and sold).
    let wardrobeTotal: Int
    /// The categories the member sells in, for the wardrobe filter.
    let wardrobeCategories: [WardrobeCategory]
    let shareURL: URL?
}

/// `checks` of the profile: email, phone (SMS) and identity.
struct MemberChecks: Equatable, Sendable {
    let email: Bool
    let phone: Bool
    let identity: Bool
}

/// A category of a member's wardrobe, with its number of items.
struct WardrobeCategory: Identifiable, Equatable, Hashable, Sendable {
    let slug: String
    let name: String
    /// The parent category's name ("Femmes"), shown next to a name two categories share.
    let parentName: String?
    let count: Int

    var id: String { slug }
}

/// The wardrobe's filter (`GET /members/{username}/listings`): one category slug and the sort.
struct WardrobeQuery: Hashable, Sendable {
    /// `newest` (the default), `price_asc`, `price_desc`.
    enum Sort: String, CaseIterable, Hashable, Sendable {
        case newest
        case priceAsc = "price_asc"
        case priceDesc = "price_desc"
    }

    var category: String?
    var sort: Sort = .newest

    var isFiltered: Bool { category != nil || sort != .newest }
}

/// A review on a member's profile (`GET /members/{username}/reviews`).
struct MemberReview: Identifiable, Equatable, Sendable {
    let id: String
    /// 1 to 5.
    let rating: Int
    /// Nil: stars only.
    let comment: String?
    let createdAt: Date
    let author: MemberRef
}

/// Another member as lists show them: avatar, `displayName`, badges.
struct MemberRef: Equatable, Sendable {
    let id: String
    /// Nil for the few accounts older than usernames: no profile link then.
    let username: String?
    let displayName: String
    let avatarURL: URL?
    let isVerified: Bool
    let isOfficial: Bool
}
