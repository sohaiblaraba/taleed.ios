import Foundation

/// A listing as its screen shows it (`GET /listings/{id}`, slice A "Listing screen", slice F). Every
/// permission comes from the server's flags (screens.md §0.1): `canBuy`, `offerRange`, `canMessage`,
/// `canBundle`, `isOwner`, `orderId`, `acceptedOffer`.
struct ListingDetail: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let description: String
    /// Whole dinars, before the buyer's fee.
    let price: Int
    /// The buyer's platform and service fee, computed by the server.
    let protectionFee: Int
    let size: String?
    let brand: ListingBrandRef?
    /// `VERY_GOOD`…, nil for a value this build does not know (no tag).
    let condition: String?
    let status: ListingStatus
    let photos: [ListingPhoto]
    let category: ListingCategoryRef
    let shipsFrom: CatalogWilaya?
    let viewsCount: Int
    let favoritesCount: Int
    let isFavorited: Bool
    let isBoosted: Bool
    let isOwner: Bool
    let seller: ListingSellerInfo
    /// The seller accepted this member's offer: checkout uses it.
    let acceptedOffer: AcceptedOfferRef?
    let canBuy: Bool
    /// Reserved or sold, and the member is its buyer or seller: "View the order".
    let orderId: String?
    /// Set while the member may make an offer (also signed out).
    let offerRange: AmountRange?
    let canMessage: Bool
    let canBundle: Bool
    /// The member's bundle in progress with this seller (slice F).
    var openBundleId: String?
    var inMyBundle: Bool
    let memberItems: [ListingSummary]
    let similar: [ListingSummary]
    let shareURL: URL?
    let createdAt: Date
    /// When the app asked for it, as for cards (`FavoriteStore`).
    var asOf: ContinuousClock.Instant = .now
}

struct ListingPhoto: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL?
    let thumbURL: URL?
}

/// `brand`: `slug` is nil for a brand the seller typed, shown as text and never as a filter link.
struct ListingBrandRef: Equatable, Sendable {
    let slug: String?
    let name: String
}

struct ListingCategoryRef: Equatable, Sendable {
    let slug: String
    let name: String
    let parentName: String?
    /// The category's id (`GET /catalog` ids), to prefill the edit form.
    var id = ""
    /// Nil for the older listings filed under a top-level category (slice B, Editing).
    var parentId: String?
}

/// The seller as the listing screen shows them. Never a real name (screens.md §0.3).
struct ListingSellerInfo: Equatable, Sendable {
    let id: String
    /// Nil for the few accounts older than usernames: no profile link then.
    let username: String?
    let displayName: String
    let avatarURL: URL?
    let isVerified: Bool
    let isOfficial: Bool
    /// Nil until the first review ("No reviews yet").
    let rating: MemberRating?
    let lastSeenAt: Date?
    let isOnline: Bool
}

struct AcceptedOfferRef: Equatable, Sendable {
    let id: String
    let amount: Int
}

/// `offerRange` / `counterRange`: the amounts the API accepts, both included.
struct AmountRange: Equatable, Sendable {
    let min: Int
    let max: Int

    func contains(_ amount: Int) -> Bool { amount >= min && amount <= max }
}

/// The member's open bundle with a seller, as far as the listing screen needs it (`GET /bundles/{id}`,
/// `PUT /members/{username}/bundle`).
struct BundleSelectionState: Equatable, Sendable {
    let id: String
    /// The items in the order the buyer picked them.
    let listingIds: [String]
}

extension ListingDetail {
    /// The listing as a card, for the shared hearts (`FavoriteStore`).
    var summary: ListingSummary {
        ListingSummary(
            id: id, title: title, price: price, size: size, brandName: brand?.name, condition: condition,
            status: status, imageURL: photos.first?.thumbURL ?? photos.first?.url, favoritesCount: favoritesCount,
            isFavorited: isFavorited, isBoosted: isBoosted, shipsFrom: shipsFrom, sellerRating: seller.rating, asOf: asOf
        )
    }
}
