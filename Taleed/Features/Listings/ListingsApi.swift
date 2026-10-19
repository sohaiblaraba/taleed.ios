import Foundation
import TaleedAPI

/// `GET /listings`: the home feed without filters, search and browse with them (slice A, Home feed
/// and search). Pages of 24 cards whose order can change between pages: show them with a
/// `PagedList`, which de-duplicates by id.
@MainActor
protocol ListingsApi: AnyObject {
    /// `automatic`: a refresh the member did not ask for (return to the foreground).
    func searchListings(_ query: ExploreQuery, cursor: String?, automatic: Bool) async throws(ApiError) -> Page<ListingSummary>
}

/// The heart on cards and on the listing screen (slice B, Favorites).
@MainActor
protocol FavoritesApi: AnyObject {
    /// `PUT` (`favorited`) or `DELETE /listings/{id}/favorite`. Both are idempotent.
    func setFavorite(listingId: String, favorited: Bool) async throws(ApiError) -> FavoriteState
}

extension GeneratedTaleedApi: ListingsApi, FavoritesApi {
    func searchListings(_ query: ExploreQuery, cursor: String?, automatic: Bool) async throws(ApiError) -> Page<ListingSummary> {
        let filters = ListingSearchParameters(query)
        let asOf = ContinuousClock.now
        let page = try await caller.call(.read, automatic: automatic) {
            try await ListingsAPI.searchListings(
                q: filters.text, category: filters.category, brand: filters.brand, wilaya: filters.wilaya,
                condition: filters.condition.flatMap(TaleedAPI.ListingCondition.init(rawValue:)), size: filters.size,
                minPrice: filters.minPrice, maxPrice: filters.maxPrice,
                sort: filters.sort.flatMap(TaleedAPI.ListingSort.init(rawValue:)), cursor: cursor, apiConfiguration: $0
            )
        }
        return Page(items: page.items.map { ListingSummary($0, asOf: asOf) }, nextCursor: page.nextCursor, total: page.total)
    }

    func setFavorite(listingId: String, favorited: Bool) async throws(ApiError) -> FavoriteState {
        // Never repeated on its own: the heart goes back at once on a failure, and the member taps again.
        let state = try await caller.call(.write) {
            favorited
                ? try await FavoritesAPI.favoriteListing(id: listingId, apiConfiguration: $0)
                : try await FavoritesAPI.unfavoriteListing(id: listingId, apiConfiguration: $0)
        }
        return FavoriteState(isFavorited: state.isFavorited, count: state.favoritesCount)
    }
}

/// The query parameters of `GET /listings` for an `ExploreQuery`, without the values the API would
/// reject with `400` (screens.md §7 G3): empty text, more than 100 characters, a negative price, a
/// condition or sort this build does not know. An empty query is the home feed.
///
/// Lengths are counted as the API counts them: UTF-16 code units (JavaScript's `length`), not the
/// characters Swift counts, so Arabic with harakat or emoji stay within the limit.
struct ListingSearchParameters: Equatable, Sendable {
    static let maxTextLength = 100
    static let maxSizeLength = 30
    /// Category and brand slugs.
    static let maxSlugLength = 100
    static let conditions: Set<String> = ["NEW_WITH_TAGS", "NEW_WITHOUT_TAGS", "VERY_GOOD", "GOOD", "SATISFACTORY"]
    static let sorts: Set<String> = ["recommended", "newest", "price_asc", "price_desc"]

    var text: String?
    var category: String?
    var brand: String?
    var wilaya: Int?
    var condition: String?
    var size: String?
    var minPrice: Int?
    var maxPrice: Int?
    var sort: String?

    init(_ query: ExploreQuery) {
        text = Self.trimmed(query.text).map { $0.prefix(utf16Units: Self.maxTextLength) }
        // A longer slug names no category or brand (the API would answer `400`): left out, like an
        // unknown slug the API ignores.
        category = Self.trimmed(query.category).flatMap { $0.utf16.count <= Self.maxSlugLength ? $0 : nil }
        brand = Self.trimmed(query.brand).flatMap { $0.utf16.count <= Self.maxSlugLength ? $0 : nil }
        wilaya = query.wilaya.flatMap { $0 > 0 ? $0 : nil }
        condition = query.condition.flatMap { Self.conditions.contains($0) ? $0 : nil }
        size = Self.trimmed(query.size).map { $0.prefix(utf16Units: Self.maxSizeLength) }
        minPrice = query.minPrice.flatMap { $0 >= 0 ? $0 : nil }
        maxPrice = query.maxPrice.flatMap { $0 >= 0 ? $0 : nil }
        sort = query.sort.flatMap { Self.sorts.contains($0) ? $0 : nil }
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

extension String {
    /// The longest prefix of whole characters that is at most `limit` UTF-16 code units long: the length
    /// the API (JavaScript) checks. A character is never cut in the middle (a letter and its harakat,
    /// an emoji).
    func prefix(utf16Units limit: Int) -> String {
        guard utf16.count > limit else { return self }
        var units = 0
        var end = startIndex
        for index in indices {
            let next = self.index(after: index)
            let length = self[index..<next].utf16.count
            guard units + length <= limit else { break }
            units += length
            end = next
        }
        return String(self[..<end])
    }
}

extension ListingSummary {
    /// From the API's card. Unknown enum values (decoded as `unknownDefaultOpenApi`) become "no tag" and
    /// `.unknown` (api-guide.md, Compatibility). `asOf`: when the request started.
    init(_ card: TaleedAPI.ListingCard, asOf: ContinuousClock.Instant = .now) {
        self.init(
            id: card.id,
            title: card.title,
            price: card.price,
            size: card.size.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
            brandName: card.brandName,
            condition: card.condition == .unknownDefaultOpenApi ? nil : card.condition.rawValue,
            status: card.status == .unknownDefaultOpenApi ? .unknown : ListingStatus(code: card.status.rawValue),
            imageURL: card.imageUrl.flatMap(URL.init(string:)),
            favoritesCount: card.favoritesCount,
            isFavorited: card.isFavorited,
            isBoosted: card.isBoosted,
            shipsFrom: card.shipsFrom.map { CatalogWilaya(id: $0.id, name: $0.name) },
            sellerRating: card.sellerRating.flatMap { $0.count >= 1 ? MemberRating(average: $0.average, count: $0.count) : nil },
            asOf: asOf
        )
    }
}
