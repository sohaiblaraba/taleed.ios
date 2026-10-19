import Foundation

/// A listing in a grid or a list (`ListingCard` of the API): the home feed, search, favorites, a
/// member's items, "more from this seller". Show it with `ListingCardView`.
struct ListingSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    /// Whole dinars, before the buyer's fee (cards never show the fee).
    let price: Int
    /// Free text written by the seller ("M", "42").
    let size: String?
    let brandName: String?
    /// `VERY_GOOD`…, nil for a value this build does not know (no tag, screens.md §0.4).
    let condition: String?
    let status: ListingStatus
    /// The cover thumbnail.
    let imageURL: URL?
    let favoritesCount: Int
    /// Always false signed out.
    let isFavorited: Bool
    let isBoosted: Bool
    /// The wilaya the item ships from, its name in the response language.
    let shipsFrom: CatalogWilaya?
    /// Nil until the seller has a review.
    let sellerRating: MemberRating?
}

/// `status` of a listing. Values this build does not know are `unknown`: no buy buttons, no banner.
enum ListingStatus: String, Hashable, Sendable {
    case active = "ACTIVE"
    case reserved = "RESERVED"
    case sold = "SOLD"
    /// Paused by the seller; only the seller sees it.
    case hidden = "HIDDEN"
    /// Taleed creates none: handled like an unknown value.
    case draft = "DRAFT"
    case unknown

    init(code: String) {
        self = ListingStatus(rawValue: code) ?? .unknown
    }
}

/// A member's average rating, from 1 to 5, over `count` reviews (at least one).
struct MemberRating: Equatable, Hashable, Sendable {
    let average: Double
    let count: Int
}

/// The answer of `PUT` / `DELETE /listings/{id}/favorite`.
struct FavoriteState: Equatable, Hashable, Sendable {
    var isFavorited: Bool
    var count: Int
}
