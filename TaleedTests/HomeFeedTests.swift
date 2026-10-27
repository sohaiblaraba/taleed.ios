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
    /// When set, each request waits this long first; a cancelled one then fails, as `URLSession` does.
    var delay: Duration?
    private(set) var isWaiting = false

    func searchListings(_ query: ExploreQuery, cursor: String?, automatic: Bool) async throws(Taleed.ApiError)
        -> Page<ListingSummary> {
        requests.append(Request(query: query, cursor: cursor, automatic: automatic))
        if let delay {
            isWaiting = true
            try? await Task.sleep(for: delay)
            isWaiting = false
            if Task.isCancelled { throw .network }
        }
        guard let result = pages[cursor] else { throw .network }
        return try result.get()
    }
}

extension ListingSummary {
    static func fixture(id: String = "l1", isFavorited: Bool = false, favoritesCount: Int = 3,
                        status: Taleed.ListingStatus = .active, condition: String? = "VERY_GOOD",
                        isBoosted: Bool = false, asOf: ContinuousClock.Instant = .now) -> ListingSummary {
        ListingSummary(id: id, title: "Robe", price: 2500, size: "M", brandName: "Zara", condition: condition,
                       status: status, imageURL: nil, favoritesCount: favoritesCount, isFavorited: isFavorited,
                       isBoosted: isBoosted, shipsFrom: CatalogWilaya(id: 16, name: "Alger"), sellerRating: nil,
                       asOf: asOf)
    }
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

    @Test func lengthsAreCountedAsTheApiCountsThem() {
        // 60 letters with a shadda and a fatha each: 60 characters for Swift, 180 UTF-16 units for the API.
        let harakat = String(repeating: "\u{0634}\u{0651}\u{064E}", count: 60)
        #expect(harakat.count == 60)
        let text = ListingSearchParameters(ExploreQuery(text: harakat)).text ?? ""
        #expect(text.utf16.count <= ListingSearchParameters.maxTextLength)
        // Whole letters only: never a letter without its marks.
        #expect(text.count == 33 && text.utf16.count == 99)
        #expect(harakat.hasPrefix(text))

        // Emoji are two units (or more) each.
        let emoji = String(repeating: "👗", count: 60)
        #expect(ListingSearchParameters(ExploreQuery(text: emoji)).text == String(repeating: "👗", count: 50))
        #expect(ListingSearchParameters(ExploreQuery(size: String(repeating: "👗", count: 20))).size?.utf16.count == 30)

        // A slug longer than the API takes names nothing: left out.
        let slug = String(repeating: "a", count: 101)
        let parameters = ListingSearchParameters(ExploreQuery(category: slug, brand: slug))
        #expect(parameters.category == nil && parameters.brand == nil)
        let fits = String(repeating: "a", count: 100)
        #expect(ListingSearchParameters(ExploreQuery(category: fits, brand: fits)).category == fits)

        // The search field's keywords too.
        #expect(ExploreQuery().searching(emoji).text?.utf16.count == 100)
        #expect("abc".prefix(utf16Units: 100) == "abc")
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
                      size: String? = "M", rating: Rating? = nil, isOwner: Bool = false) -> TaleedAPI.ListingCard {
        TaleedAPI.ListingCard(id: "l1", title: "Robe", price: 2500, size: size, brandName: nil, condition: condition,
                              status: status, imageUrl: "https://example.com/a.jpg", favoritesCount: 2, isFavorited: true,
                              isOwner: isOwner, isBoosted: true, shipsFrom: Wilaya(id: 31, name: "Oran"), sellerRating: rating)
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

    @Test func theMembersOwnCardSaysYourItem() {
        let text: (L10nKey) -> String = { $0 == .listingYourItem ? "Your item" : "" }
        let favorite = FavoriteState(isFavorited: false, count: 0)
        let own = ListingSummary(card(isOwner: true))
        #expect(own.isOwner)
        #expect(ListingCardContent.product(for: own, favorite: favorite, catalog: nil, text: text).ownerLabel == "Your item")
        // A wardrobe or "more from this seller": every card is theirs, so no tag.
        #expect(ListingCardContent.product(for: own, favorite: favorite, catalog: nil, showsOwnerTag: false,
                                           text: text).ownerLabel == nil)
        let other = ListingSummary(card())
        #expect(ListingCardContent.product(for: other, favorite: favorite, catalog: nil, text: text).ownerLabel == nil)
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

    @Test func aMemberReloadCancelledByTheScreenIsMadeAgain() async {
        api.pages = [nil: page(["a"])]
        let model = makeModel()
        await model.show(for: .init(memberId: nil, language: .fr))
        // Signed in, the member taps a card before the personalized page arrives.
        api.pages = [nil: page(["b"])]
        api.delay = .seconds(5)
        let member = HomeViewModel.FeedContext(memberId: "yasmine", language: .fr)
        let task = Task { await model.show(for: member) }
        await waitUntil { api.isWaiting }
        task.cancel()
        await task.value
        #expect(model.feed.items.map(\.id) == ["a"])
        #expect(model.refreshFailure == nil)
        // Home shows again: the personalized feed loads.
        api.delay = nil
        await model.show(for: member)
        #expect(model.feed.items.map(\.id) == ["b"])
        await model.show(for: member)
        #expect(api.requests.count == 3)
    }

    @Test func aFailedMemberReloadIsMadeAgain() async {
        api.pages = [nil: page(["a"])]
        let model = makeModel()
        await model.show(for: .init(memberId: nil, language: .fr))
        api.pages = [:]
        let member = HomeViewModel.FeedContext(memberId: "yasmine", language: .fr)
        await model.show(for: member)
        #expect(model.refreshFailure?.error == .network)
        api.pages = [nil: page(["b"])]
        await model.show(for: member)
        #expect(model.feed.items.map(\.id) == ["b"])
    }

    @Test func theForegroundRefreshIsAutomaticAndSilent() async {
        api.pages = [nil: page(["a"])]
        let model = makeModel()
        await model.show(for: .init(memberId: nil, language: .fr))
        await model.topAppeared()
        api.pages = [:]
        let left = ContinuousClock.now
        model.wentToBackground(at: left)
        await model.returnedToForeground(at: left + HomeViewModel.foregroundReloadAfter)
        #expect(api.requests.count == 2)
        #expect(api.requests.last?.automatic == true)
        #expect(model.refreshFailure == nil)
        #expect(model.feed.items.map(\.id) == ["a"])
    }

    @Test func aShortAbsenceKeepsTheFeed() async {
        api.pages = [nil: page(["a"])]
        let model = makeModel()
        await model.show(for: .init(memberId: nil, language: .fr))
        await model.topAppeared()
        let left = ContinuousClock.now
        model.wentToBackground(at: left)
        await model.returnedToForeground(at: left + .seconds(10))
        #expect(api.requests.count == 1)
    }

    @Test func deepInTheFeedTheForegroundReloadWaitsForTheTop() async {
        api.pages = [nil: page(["a", "b"], next: "p2"), "p2": page(["c", "d"])]
        let model = makeModel()
        await model.show(for: .init(memberId: nil, language: .fr))
        await model.topAppeared()
        await model.feed.loadMore()
        // The member scrolled down to the second page, then left the app for a while.
        model.topDisappeared()
        let left = ContinuousClock.now
        model.wentToBackground(at: left)
        await model.returnedToForeground(at: left + .seconds(600))
        #expect(api.requests.count == 2)
        #expect(model.feed.items.map(\.id) == ["a", "b", "c", "d"])
        // Back at the top: the quiet reload, once.
        api.pages = [nil: page(["e", "a"], next: "p2")]
        await model.topAppeared()
        #expect(model.feed.items.map(\.id) == ["e", "a"])
        #expect(api.requests.last?.automatic == true)
        model.topDisappeared()
        await model.topAppeared()
        #expect(api.requests.count == 3)
    }

    @Test func theHeroStaysDismissed() {
        let model = makeModel()
        #expect(!model.isHeroDismissed)
        model.dismissHero()
        #expect(model.isHeroDismissed)
        #expect(makeModel().isHeroDismissed)
    }

    @Test func categoryChipIcons() {
        #expect(HomeCategoryIcon.icon(forSlug: "kids") == .baby)
        #expect(HomeCategoryIcon.icon(forSlug: "women") == .dress)
        #expect(HomeCategoryIcon.icon(forSlug: "food") == .storefront)
        #expect(HomeCategoryIcon.icon(forSlug: "entertainment") == .ticket)
        #expect(HomeCategoryIcon.icon(forSlug: "other") == .dotsThree)
        #expect(HomeCategoryIcon.icon(forSlug: "garden") == nil)
    }
}
