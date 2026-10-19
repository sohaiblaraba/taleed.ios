import Foundation
import TaleedAPI

/// The reference lists of the filter sheet (slice A, Home feed and search) and search by photo
/// (slice B, Search by photo). Results of a text search come from `ListingsApi`.
@MainActor
protocol ExploreApi: AnyObject {
    /// `GET /brands`: every brand, alphabetical.
    func brands() async throws(ApiError) -> [CatalogBrand]
    /// `GET /sizes`: the sizes of the items on sale right now, in natural order.
    func sizes() async throws(ApiError) -> [String]
    /// `POST /visual-searches` with a prepared JPEG in the `photo` part: the search and its first page.
    func createVisualSearch(photo: URL) async throws(ApiError) -> VisualSearchPage
    /// `GET /visual-searches/{id}`: a page of a search made in the last 24 hours (`404` after).
    func visualSearch(id: String, cursor: String?) async throws(ApiError) -> VisualSearchPage
}

/// A brand of `GET /brands`: `slug` goes in the `brand` filter.
struct CatalogBrand: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let slug: String
    let name: String
}

/// A search by photo and one page of its results.
struct VisualSearchPage: Equatable, Sendable {
    let id: String
    /// The photo as it was analyzed: a square crop.
    let photoURL: URL?
    /// Even the closest items are not very similar: say so instead of "similar items".
    let weakMatch: Bool
    /// Most similar first, 24 a page, 48 at most in all.
    let page: Page<ListingSummary>
    /// After this, `GET /visual-searches/{id}` may answer `404`: start a new search.
    let expiresAt: Date
}

extension GeneratedTaleedApi: ExploreApi {
    func brands() async throws(ApiError) -> [CatalogBrand] {
        let list = try await caller.call { try await ReferenceAPI.listBrands(apiConfiguration: $0) }
        return list.items.map { CatalogBrand(id: $0.id, slug: $0.slug, name: $0.name) }
    }

    func sizes() async throws(ApiError) -> [String] {
        let list = try await caller.call { try await ReferenceAPI.listSizes(apiConfiguration: $0) }
        return list.items.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func createVisualSearch(photo: URL) async throws(ApiError) -> VisualSearchPage {
        let asOf = ContinuousClock.now
        // Never repeated on its own: a failed search is not kept, and the member's retry sends the photo
        // again (slice B). The upload configuration allows about a minute.
        let search = try await caller.call(.write, configuration: session.uploadConfiguration()) {
            try await VisualSearchAPI.createVisualSearch(photo: photo, apiConfiguration: $0)
        }
        return VisualSearchPage(search, asOf: asOf)
    }

    func visualSearch(id: String, cursor: String?) async throws(ApiError) -> VisualSearchPage {
        let asOf = ContinuousClock.now
        let search = try await caller.call { try await VisualSearchAPI.getVisualSearch(id: id, cursor: cursor, apiConfiguration: $0) }
        return VisualSearchPage(search, asOf: asOf)
    }
}

extension VisualSearchPage {
    init(_ search: TaleedAPI.VisualSearch, asOf: ContinuousClock.Instant = .now) {
        self.init(
            id: search.id,
            photoURL: URL(string: search.photoUrl),
            weakMatch: search.weakMatch,
            page: Page(items: search.items.map { ListingSummary($0, asOf: asOf) }, nextCursor: search.nextCursor,
                       total: search.total),
            expiresAt: search.expiresAt
        )
    }
}
