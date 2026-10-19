import Foundation
@testable import Taleed
import TaleedAPI
import Testing

// MARK: - Fakes

/// A `ListingsApi` with canned pages per cursor, recording what it was asked.
@MainActor
final class FakeListingsApi: ListingsApi {
    var pages: [String?: Result<Page<ListingSummary>, Taleed.ApiError>] = [:]
    struct Request {
        let query: ExploreQuery
        let cursor: String?
        let automatic: Bool
    }

    private(set) var requests: [Request] = []

    func searchListings(_ query: ExploreQuery, cursor: String?, automatic: Bool) async throws(Taleed.ApiError)
        -> Page<ListingSummary> {
        requests.append(Request(query: query, cursor: cursor, automatic: automatic))
        guard let result = pages[cursor] else { throw .network }
        return try result.get()
    }
}

/// A `FavoritesApi` whose answers the test releases one at a time.
@MainActor
final class FakeFavoritesApi: FavoritesApi {
    /// Answers in order; a missing answer echoes the request with `count`.
    var results: [Result<Taleed.FavoriteState, Taleed.ApiError>] = []
    var count = 10
    private(set) var sent: [(id: String, favorited: Bool)] = []
    /// When set, each call waits until `release()`.
    var holds = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func setFavorite(listingId: String, favorited: Bool) async throws(Taleed.ApiError) -> Taleed.FavoriteState {
        sent.append((listingId, favorited))
        if holds { await withCheckedContinuation { waiting.append($0) } }
        if !results.isEmpty { return try results.removeFirst().get() }
        return Taleed.FavoriteState(isFavorited: favorited, count: count)
    }

    func release() {
        let next = waiting
        waiting = []
        next.forEach { $0.resume() }
    }

    var isWaiting: Bool { !waiting.isEmpty }
}

extension ListingSummary {
    static func fixture(id: String = "l1", isFavorited: Bool = false, favoritesCount: Int = 3,
                        status: Taleed.ListingStatus = .active, condition: String? = "VERY_GOOD",
                        isBoosted: Bool = false) -> ListingSummary {
        ListingSummary(id: id, title: "Robe", price: 2500, size: "M", brandName: "Zara", condition: condition,
                       status: status, imageURL: nil, favoritesCount: favoritesCount, isFavorited: isFavorited,
                       isBoosted: isBoosted, shipsFrom: CatalogWilaya(id: 16, name: "Alger"), sellerRating: nil)
    }
}

private func notFound() -> Taleed.ApiError {
    .from(status: 404, body: Data(#"{"error":{"code":"not_found","message":"x"}}"#.utf8))
}

private func waitUntil(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<200 where !condition() { await Task.yield() }
}

// MARK: - Search parameters

struct ListingSearchParametersTests {
    @Test func anEmptyQueryIsTheHomeFeed() {
        #expect(ListingSearchParameters(ExploreQuery()) == ListingSearchParameters(ExploreQuery(text: "  ", category: "")))
        let parameters = ListingSearchParameters(ExploreQuery())
        #expect(parameters.text == nil && parameters.category == nil && parameters.sort == nil && parameters.wilaya == nil)
    }

    @Test func valuesTheApiWouldRejectAreDropped() {
        let long = String(repeating: "a", count: 150)
        let parameters = ListingSearchParameters(ExploreQuery(
            text: "  \(long) ", wilaya: 0, condition: "BRAND_NEW", minPrice: -1, maxPrice: 5000, sort: "cheapest"
        ))
        #expect(parameters.text?.count == ListingSearchParameters.maxTextLength)
        #expect(parameters.wilaya == nil)
        #expect(parameters.condition == nil)
        #expect(parameters.minPrice == nil)
        #expect(parameters.maxPrice == 5000)
        #expect(parameters.sort == nil)
    }

    @Test func knownValuesPassThrough() {
        let parameters = ListingSearchParameters(ExploreQuery(category: "women", wilaya: 16, condition: "GOOD",
                                                              sort: "price_asc"))
        #expect(parameters.category == "women")
        #expect(parameters.wilaya == 16)
        #expect(parameters.condition == "GOOD")
        #expect(parameters.sort == "price_asc")
    }
}

// MARK: - Mapping the API's card

struct ListingSummaryMappingTests {
    private func card(condition: TaleedAPI.ListingCondition = .veryGood, status: TaleedAPI.ListingStatus = .active,
                      size: String? = "M", rating: Rating? = nil) -> TaleedAPI.ListingCard {
        TaleedAPI.ListingCard(id: "l1", title: "Robe", price: 2500, size: size, brandName: nil, condition: condition,
                              status: status, imageUrl: "https://example.com/a.jpg", favoritesCount: 2, isFavorited: true,
                              isBoosted: true, shipsFrom: Wilaya(id: 31, name: "Oran"), sellerRating: rating)
    }

    @Test func aCardKeepsItsFields() {
        let listing = ListingSummary(card(rating: Rating(average: 4.5, count: 3)))
        #expect(listing.condition == "VERY_GOOD")
        #expect(listing.status == .active)
        #expect(listing.imageURL == URL(string: "https://example.com/a.jpg"))
        #expect(listing.shipsFrom == CatalogWilaya(id: 31, name: "Oran"))
        #expect(listing.sellerRating == MemberRating(average: 4.5, count: 3))
        #expect(listing.isFavorited && listing.isBoosted && listing.favoritesCount == 2)
    }

    @Test func unknownValuesShowNoTagAndNoBanner() {
        let listing = ListingSummary(card(condition: .unknownDefaultOpenApi, status: .unknownDefaultOpenApi, size: "  "))
        #expect(listing.condition == nil)
        #expect(listing.status == .unknown)
        #expect(listing.size == nil)
    }

    @Test func statusCodes() {
        #expect(Taleed.ListingStatus(code: "RESERVED") == .reserved)
        #expect(Taleed.ListingStatus(code: "SOLD") == .sold)
        #expect(Taleed.ListingStatus(code: "ARCHIVED") == .unknown)
    }
}

// MARK: - What a card shows

@MainActor
struct ListingCardContentTests {
    private let text: (L10nKey) -> String = { $0.rawValue }

    @Test func statusStripOnlyWhenNotForSale() {
        #expect(ListingCardContent.statusKey(.active) == nil)
        #expect(ListingCardContent.statusKey(.reserved) == .listingStatusReserved)
        #expect(ListingCardContent.statusKey(.sold) == .listingStatusSold)
        #expect(ListingCardContent.statusKey(.hidden) == .listingStatusHidden)
        #expect(ListingCardContent.statusKey(.draft) == nil)
        #expect(ListingCardContent.statusKey(.unknown) == nil)
    }

    @Test func theHeartComesFromTheStoreAndTheCountHidesAtZero() {
        let listing = ListingSummary.fixture(isFavorited: false, favoritesCount: 0)
        let empty = ListingCardContent.product(for: listing, favorite: Taleed.FavoriteState(isFavorited: false, count: 0),
                                               catalog: nil, text: text)
        #expect(empty.favoriteCount == nil)
        #expect(!empty.isFavorite)
        let saved = ListingCardContent.product(for: listing, favorite: Taleed.FavoriteState(isFavorited: true, count: 1),
                                               catalog: nil, text: text)
        #expect(saved.favoriteCount == 1)
        #expect(saved.isFavorite)
    }

    @Test func boostedAndSoldLabels() {
        let listing = ListingSummary.fixture(status: .sold, isBoosted: true)
        let product = ListingCardContent.product(for: listing, favorite: Taleed.FavoriteState(isFavorited: false, count: 3),
                                                 catalog: nil, text: text)
        #expect(product.boostedLabel == "listing_boosted")
        #expect(product.statusLabel == "listing_status_sold")
        #expect(product.location == "Alger")
        #expect(product.sizeLabel == "M")
    }

    @Test func conditionTagUsesTheCatalogAndHidesUnknownCodes() {
        let catalog = Catalog.fixture()
        #expect(ListingCardContent.conditionTag("VERY_GOOD", catalog: catalog)?.shortLabel == "Très bon")
        // Before the catalog arrived, the five known codes still have the app's labels.
        #expect(ListingCardContent.conditionTag("GOOD", catalog: nil)?.code == "GOOD")
        #expect(ListingCardContent.conditionTag("MINT", catalog: catalog) == nil)
        #expect(ListingCardContent.conditionTag(nil, catalog: catalog) == nil)
    }
}

// MARK: - Favorites

@MainActor
struct FavoriteStoreTests {
    private let api = FakeFavoritesApi()

    @Test func aTapFillsTheHeartAtOnceThenTakesTheApisCount() async {
        let store = FavoriteStore(api: api)
        let listing = ListingSummary.fixture(favoritesCount: 3)
        api.holds = true
        let task = store.toggle(listing)
        #expect(store.state(for: listing) == Taleed.FavoriteState(isFavorited: true, count: 4))
        await waitUntil { api.isWaiting }
        api.count = 7
        api.release()
        await task?.value
        #expect(store.state(for: listing) == Taleed.FavoriteState(isFavorited: true, count: 7))
        #expect(api.sent.map(\.favorited) == [true])
    }

    @Test func aFailurePutsTheHeartBackAndReportsIt() async {
        let store = FavoriteStore(api: api)
        var failures: [Taleed.ApiError] = []
        store.onFailure = { failures.append($0) }
        let listing = ListingSummary.fixture(isFavorited: true, favoritesCount: 5)
        api.results = [.failure(.network)]
        await store.toggle(listing)?.value
        #expect(store.state(for: listing) == Taleed.FavoriteState(isFavorited: true, count: 5))
        #expect(failures == [.network])
        #expect(store.removedIds.isEmpty)
    }

    @Test func aRemovedListingLeavesTheLists() async {
        let store = FavoriteStore(api: api)
        var removed: [String] = []
        store.onRemoved = { removed.append($0) }
        api.results = [.failure(notFound())]
        await store.toggle(.fixture(id: "gone"))?.value
        #expect(store.removedIds == ["gone"])
        #expect(removed == ["gone"])
    }

    @Test func tapsDuringARequestSendTheLastWish() async {
        let store = FavoriteStore(api: api)
        let listing = ListingSummary.fixture(favoritesCount: 3)
        api.holds = true
        let task = store.toggle(listing)
        await waitUntil { api.isWaiting }
        // Two more taps while the first request runs: back to not favorited, then favorited again.
        #expect(store.toggle(listing) == nil)
        #expect(store.toggle(listing) == nil)
        #expect(store.state(for: listing).isFavorited)
        api.holds = false
        api.release()
        await task?.value
        // The API already says favorited, which is the last wish: nothing more to send.
        #expect(api.sent.map(\.favorited) == [true])
        #expect(store.state(for: listing).isFavorited)
    }

    @Test func anUndoDuringARequestIsSentAfterIt() async {
        let store = FavoriteStore(api: api)
        let listing = ListingSummary.fixture(favoritesCount: 3)
        api.holds = true
        let task = store.toggle(listing)
        await waitUntil { api.isWaiting }
        store.toggle(listing)
        #expect(!store.state(for: listing).isFavorited)
        api.holds = false
        api.release()
        await task?.value
        #expect(api.sent.map(\.favorited) == [true, false])
        #expect(!store.state(for: listing).isFavorited)
    }

    @Test func afterSigningInTheHeartAddsEvenWhenAlreadyShownSaved() async {
        let store = FavoriteStore(api: api)
        let listing = ListingSummary.fixture(isFavorited: true, favoritesCount: 4)
        await store.setFavorite(listing, to: true)?.value
        #expect(api.sent.map(\.favorited) == [true])
    }

    @Test func anotherMemberStartsFromTheListsAgain() async {
        let store = FavoriteStore(api: api)
        let listing = ListingSummary.fixture()
        await store.toggle(listing)?.value
        #expect(store.state(for: listing).isFavorited)
        store.sessionDidChange()
        #expect(!store.state(for: listing).isFavorited)
    }
}

// MARK: - Pagination when the screen lets go

@MainActor
struct PagedListCancellationTests {
    @Test func aCancelledNextPageIsNoError() async {
        var slow = false
        let list = PagedList<ListingSummary> { cursor throws(Taleed.ApiError) in
            if cursor == nil {
                return Page(items: [.fixture(id: "a")], nextCursor: "p2", total: 2)
            }
            slow = true
            try? await Task.sleep(for: .seconds(5))
            throw .network
        }
        await list.loadIfNeeded()
        let task = Task { await list.loadMore() }
        await waitUntil { slow }
        task.cancel()
        await task.value
        #expect(list.loadMoreError == nil)
        #expect(!list.isLoadingMore)
        #expect(list.hasMore)
    }
}

// MARK: - Home

@MainActor
struct HomeViewModelTests {
    private let api = FakeListingsApi()
    private let defaults = UserDefaults(suiteName: "home-tests-\(UUID().uuidString)")!

    private func makeModel() -> HomeViewModel {
        let cache = CatalogDiskCache(directory: FileManager.default.temporaryDirectory
            .appending(path: "home-tests-\(UUID().uuidString)", directoryHint: .isDirectory))
        let catalog = CatalogStore(api: FakeTaleedApi(), language: .fr, cache: cache)
        return HomeViewModel(api: api, catalog: catalog, defaults: defaults)
    }

    private func page(_ ids: [String], next: String? = nil) -> Result<Page<ListingSummary>, Taleed.ApiError> {
        .success(Page(items: ids.map { ListingSummary.fixture(id: $0) }, nextCursor: next, total: ids.count))
    }

    @Test func theFeedIsTheUnfilteredSearchLoadedOnce() async {
        api.pages = [nil: page(["a", "b"])]
        let model = makeModel()
        let context = HomeViewModel.FeedContext(memberId: nil, language: .fr)
        await model.show(for: context)
        await model.show(for: context)
        #expect(api.requests.count == 1)
        #expect(api.requests.first?.query == ExploreQuery())
        #expect(api.requests.first?.automatic == false)
        #expect(model.feed.items.map(\.id) == ["a", "b"])
    }

    @Test func anotherMemberOrLanguageReloadsTheFeed() async {
        api.pages = [nil: page(["a", "b"])]
        let model = makeModel()
        await model.show(for: .init(memberId: nil, language: .fr))
        api.pages = [nil: page(["b", "c"])]
        await model.show(for: .init(memberId: "karim", language: .fr))
        #expect(model.feed.items.map(\.id) == ["b", "c"])
        await model.show(for: .init(memberId: "karim", language: .ar))
        #expect(api.requests.count == 3)
    }

    @Test func pagesAreDeduplicated() async {
        api.pages = [nil: page(["a", "b", "c"], next: "p2"), "p2": page(["c", "a", "d"])]
        let model = makeModel()
        await model.show(for: .init(memberId: nil, language: .fr))
        await model.feed.loadMore()
        #expect(model.feed.items.map(\.id) == ["a", "b", "c", "d"])
    }

    @Test func aFailedPullToRefreshKeepsTheCardsAndReportsOnce() async {
        api.pages = [nil: page(["a"])]
        let model = makeModel()
        await model.show(for: .init(memberId: nil, language: .fr))
        api.pages = [:]
        await model.refresh()
        #expect(model.feed.items.map(\.id) == ["a"])
        #expect(model.refreshFailure?.error == .network)
    }

    @Test func theForegroundRefreshIsAutomaticAndSilent() async {
        api.pages = [nil: page(["a"])]
        let model = makeModel()
        await model.show(for: .init(memberId: nil, language: .fr))
        api.pages = [:]
        await model.returnedToForeground()
        #expect(api.requests.last?.automatic == true)
        #expect(model.refreshFailure == nil)
        #expect(model.feed.items.map(\.id) == ["a"])
    }

    @Test func theHeroStaysDismissed() {
        let model = makeModel()
        #expect(!model.isHeroDismissed)
        model.dismissHero()
        #expect(model.isHeroDismissed)
        #expect(makeModel().isHeroDismissed)
    }

    @Test func browseNearYouUsesTheMembersWilaya() {
        var user = User.fixture()
        #expect(HomeViewModel.nearbyQuery(for: nil) == nil)
        #expect(HomeViewModel.nearbyQuery(for: user) == nil)
        user.wilayaId = 31
        #expect(HomeViewModel.nearbyQuery(for: user) == ExploreQuery(wilaya: 31))
    }

    @Test func categoryChipIcons() {
        #expect(HomeCategoryIcon.icon(forSlug: "kids") == .baby)
        #expect(HomeCategoryIcon.icon(forSlug: "women") == .dress)
        #expect(HomeCategoryIcon.icon(forSlug: "food") == nil)
    }
}
