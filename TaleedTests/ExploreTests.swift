import Foundation
@testable import Taleed
import Testing

// MARK: - Fakes

/// An `ExploreApi` with canned answers, recording what it was asked.
@MainActor
final class FakeExploreApi: ExploreApi {
    var brandsResult: Result<[CatalogBrand], ApiError> = .success([CatalogBrand(id: "b1", slug: "zara", name: "Zara")])
    var sizesResult: Result<[String], ApiError> = .success(["38", "M"])
    var createResult: Result<VisualSearchPage, ApiError> = .success(.fixture())
    var pages: [String?: Result<VisualSearchPage, ApiError>] = [nil: .success(.fixture())]
    private(set) var brandsCalls = 0
    private(set) var sizesCalls = 0
    private(set) var uploadedFiles: [URL] = []
    /// Whether each uploaded file was still on disk during the call.
    private(set) var uploadedFileExisted: [Bool] = []

    func brands() async throws(ApiError) -> [CatalogBrand] {
        brandsCalls += 1
        return try brandsResult.get()
    }

    func sizes() async throws(ApiError) -> [String] {
        sizesCalls += 1
        return try sizesResult.get()
    }

    func createVisualSearch(photo: URL) async throws(ApiError) -> VisualSearchPage {
        uploadedFiles.append(photo)
        uploadedFileExisted.append(FileManager.default.fileExists(atPath: photo.path))
        return try createResult.get()
    }

    func visualSearch(id: String, cursor: String?) async throws(ApiError) -> VisualSearchPage {
        guard let result = pages[cursor] else { throw .network }
        return try result.get()
    }
}

extension VisualSearchPage {
    static func fixture(id: String = "vs1", weakMatch: Bool = false, items: [ListingSummary] = [.fixture()],
                        nextCursor: String? = nil) -> VisualSearchPage {
        VisualSearchPage(id: id, photoURL: URL(string: "https://media.taleed.app/visual/a.webp"), weakMatch: weakMatch,
                         page: Page(items: items, nextCursor: nextCursor, total: items.count),
                         expiresAt: Date(timeIntervalSince1970: 2_000_000_000))
    }
}

// MARK: - The query

struct ExploreQueryTests {
    @Test func activeFiltersFollowTheChipOrderAndWhatTheApiReceives() {
        let query = ExploreQuery(text: "robe", category: "women", brand: "zara", wilaya: 16, condition: "GOOD", size: "M",
                                 minPrice: 1000, sort: "price_asc")
        #expect(query.activeFilters == [.category, .brand, .condition, .size, .wilaya, .price])
        // Values the API would reject are not sent, so they show no chip.
        let rejected = ExploreQuery(category: " ", wilaya: 0, condition: "BRAND_NEW", minPrice: -5)
        #expect(rejected.activeFilters.isEmpty)
        #expect(ExploreQuery(text: "zara", sort: "newest").activeFilters.isEmpty)
    }

    @Test func thePriceRangeIsOneFilter() {
        #expect(ExploreQuery(maxPrice: 5000).activeFilters == [.price])
        #expect(ExploreQuery(minPrice: 0, maxPrice: 5000).removing(.price) == ExploreQuery())
    }

    @Test func removingOneFilterKeepsTheOthers() {
        let query = ExploreQuery(text: "robe", category: "women", brand: "zara", sort: "newest")
        #expect(query.removing(.brand) == ExploreQuery(text: "robe", category: "women", sort: "newest"))
        #expect(query.removing(.category).activeFilters == [.brand])
    }

    @Test func clearingKeepsOnlyTheKeywordsAsOnTheWebsite() {
        let query = ExploreQuery(text: "robe", category: "women", wilaya: 31, minPrice: 100, sort: "price_desc")
        #expect(query.clearingFilters == ExploreQuery(text: "robe"))
        #expect(ExploreQuery(category: "women").clearingFilters == ExploreQuery())
    }

    @Test func theDefaultSortIsLeftOut() {
        let query = ExploreQuery(category: "women", sort: "newest")
        #expect(query.sorted(by: "recommended").sort == nil)
        #expect(query.sorted(by: "price_asc").sort == "price_asc")
        #expect(ExploreQuery().effectiveSort == "recommended")
        #expect(ExploreQuery(sort: "cheapest").effectiveSort == "recommended")
        #expect(ExploreQuery(sort: "price_desc").effectiveSort == "price_desc")
    }

    @Test func searchingTrimsAndCapsTheKeywords() {
        let query = ExploreQuery(category: "women")
        #expect(query.searching("  zara  ") == ExploreQuery(text: "zara", category: "women"))
        #expect(query.searching("   ").text == nil)
        #expect(query.searching(String(repeating: "a", count: 140)).text?.count == 100)
    }
}

// MARK: - Labels

@MainActor
struct ExploreLabelsTests {
    private func text(_ key: L10nKey) -> String { DesignSystemStrings.string(key, language: .fr) }

    @Test func chipsUseTheCatalogAndTheBrandList() {
        let catalog = Catalog.fixture(categories: [CatalogCategory(id: "1", slug: "women", name: "Femmes", children: [
            CatalogCategory(id: "2", slug: "women-shoes", name: "Chaussures"),
        ])])
        let context = ExploreLabels.Context(catalog: catalog, brands: [CatalogBrand(id: "b", slug: "h-m", name: "H&M")],
                                            language: .fr, text: text)
        let query = ExploreQuery(category: "women-shoes", brand: "h-m", wilaya: 16, condition: "VERY_GOOD", size: "M")
        #expect(ExploreLabels.chip(.category, query: query, context: context) == "Chaussures · Femmes")
        #expect(ExploreLabels.chip(.category, query: ExploreQuery(category: "women"), context: context) == "Femmes")
        #expect(ExploreLabels.chip(.brand, query: query, context: context) == "H&M")
        #expect(ExploreLabels.chip(.wilaya, query: query, context: context) == "Alger")
        #expect(ExploreLabels.chip(.condition, query: query, context: context) == "Très bon état")
        #expect(ExploreLabels.chip(.size, query: query, context: context) == "M")
    }

    @Test func unknownValuesShowTheirCode() {
        let context = ExploreLabels.Context(catalog: nil, language: .fr, text: text)
        let query = ExploreQuery(category: "vintage", brand: "unknown-brand", wilaya: 99)
        #expect(ExploreLabels.chip(.category, query: query, context: context) == "vintage")
        #expect(ExploreLabels.chip(.brand, query: query, context: context) == "unknown-brand")
        #expect(ExploreLabels.chip(.wilaya, query: query, context: context) == "99")
    }

    @Test func priceFieldsShowTheCurrencyOfThePrices() {
        #expect(PriceFormatter.currencySuffix(language: .fr) == "DA")
        #expect(PriceFormatter.currencySuffix(language: .en) == "DA")
        #expect(PriceFormatter.currencySuffix(language: .ar) == "د.ج.")
        #expect(PriceFormatter.format(500, language: .ar).contains(PriceFormatter.currencySuffix(language: .ar)))
    }

    @Test func thePriceChipReadsLikeTheWebsite() {
        let context = ExploreLabels.Context(catalog: nil, language: .fr, text: text)
        let low = PriceFormatter.format(1000, language: .fr)
        let high = PriceFormatter.format(5000, language: .fr)
        #expect(ExploreLabels.chip(.price, query: ExploreQuery(minPrice: 1000), context: context) == "≥ \(low)")
        #expect(ExploreLabels.chip(.price, query: ExploreQuery(maxPrice: 5000), context: context) == "≤ \(high)")
        #expect(ExploreLabels.chip(.price, query: ExploreQuery(minPrice: 1000, maxPrice: 5000), context: context)
            == "\(low) — \(high)")
    }

    @Test func sortsComeFromTheCatalogWithoutUnknownValues() {
        var catalog = Catalog.fixture()
        catalog.sorts = [CatalogOption(value: "price_asc", label: "Prix croissant"), CatalogOption(value: "distance", label: "?")]
        #expect(ExploreLabels.sorts(catalog: catalog, text: text).map(\.id) == ["price_asc"])
        // Before the catalog arrived: the website's four sorts.
        let fallback = ExploreLabels.sorts(catalog: nil, text: text)
        #expect(fallback.map(\.id) == ["recommended", "newest", "price_asc", "price_desc"])
        #expect(fallback.map(\.title) == ["Recommandés", "Plus récents", "Prix croissant", "Prix décroissant"])
    }

    @Test(arguments: [(AppLanguage.fr, 0, "Aucun article"), (.fr, 1, "1 article"), (.fr, 13, "13 articles"),
                      (.ar, 0, "لا نتائج"), (.ar, 2, "نتيجتان"), (.ar, 5, "5 نتائج"), (.en, 0, "No items"),
                      (.en, 1, "1 item")])
    func theResultCountIsPlural(language: AppLanguage, count: Int, text: String) {
        #expect(DesignSystemStrings.format(.filtersResults, locale: language.locale, count) == text)
    }
}

// MARK: - Links

struct ExploreLinkTests {
    @Test func browseLinksReadTheWebsitesPriceNames() {
        let destination = LinkRouter.destination(for: "https://taleed.app/browse?q=robe&min=1000&max=5000&sort=price_asc")
        #expect(destination == .explore(ExploreQuery(text: "robe", minPrice: 1000, maxPrice: 5000, sort: "price_asc")))
        #expect(LinkRouter.destination(for: "/browse?minPrice=200") == .explore(ExploreQuery(minPrice: 200)))
    }

    @Test func categoryLinksFilterOnTheCategory() {
        #expect(LinkRouter.destination(for: "/categories/women") == .explore(ExploreQuery(category: "women")))
        #expect(LinkRouter.destination(for: "/ar/categories/women/women-shoes?sort=newest")
            == .explore(ExploreQuery(category: "women-shoes", sort: "newest")))
        #expect(LinkRouter.destination(for: "/visual-search/vs1") == .screen(.visualSearch(id: "vs1")))
    }
}

// MARK: - Results

@MainActor
struct SearchResultsViewModelTests {
    private func api(total: Int = 30) -> FakeListingsApi {
        let api = FakeListingsApi()
        api.pages = [nil: .success(Page(items: [.fixture(id: "a"), .fixture(id: "b")], nextCursor: "c2", total: total)),
                     "c2": .success(Page(items: [.fixture(id: "b"), .fixture(id: "c")], nextCursor: nil, total: total))]
        return api
    }

    @Test func loadsPagesWithoutDuplicates() async {
        let fake = api()
        let model = SearchResultsViewModel(query: ExploreQuery(category: "women"), api: fake)
        await model.results.loadIfNeeded()
        await model.results.loadMore()
        #expect(model.results.items.map(\.id) == ["a", "b", "c"])
        #expect(model.results.total == 30)
        #expect(fake.requests.map(\.query) == [ExploreQuery(category: "women"), ExploreQuery(category: "women")])
    }

    @Test func aNewQueryStartsANewList() async {
        let fake = api()
        let model = SearchResultsViewModel(query: ExploreQuery(category: "women"), api: fake)
        await model.results.loadIfNeeded()
        let first = model.results
        model.apply(model.query.sorted(by: "price_asc"))
        #expect(model.results !== first)
        #expect(!model.results.hasLoaded)
        await model.results.loadIfNeeded()
        #expect(fake.requests.last?.query == ExploreQuery(category: "women", sort: "price_asc"))
    }

    @Test func theSameRequestKeepsTheList() async {
        let model = SearchResultsViewModel(query: ExploreQuery(category: "women"), api: api())
        let first = model.results
        model.apply(ExploreQuery(category: "women", condition: "UNKNOWN", sort: "recommended"))
        #expect(model.results === first)
    }

    @Test func searchingKeepsTheFiltersAndClearingKeepsTheKeywords() {
        let model = SearchResultsViewModel(query: ExploreQuery(category: "women", sort: "newest"), api: api())
        model.searchText = "  robe "
        model.submitSearch()
        #expect(model.query == ExploreQuery(text: "robe", category: "women", sort: "newest"))
        #expect(model.searchText == "robe")
        model.remove(.category)
        #expect(model.query == ExploreQuery(text: "robe", sort: "newest"))
        model.apply(ExploreQuery(text: "robe", brand: "zara", wilaya: 16))
        model.clearFilters()
        #expect(model.query == ExploreQuery(text: "robe"))
    }

    @Test func anotherMemberReloadsTheResults() async {
        let model = SearchResultsViewModel(query: ExploreQuery(category: "women"), api: api())
        await model.results.loadIfNeeded()
        let first = model.results
        model.memberDidChange()
        #expect(model.results !== first)
        #expect(model.query == ExploreQuery(category: "women"))
    }

    @Test func returningAfterAWhileReloadsQuietlyAtTheTop() async {
        let fake = api()
        let model = SearchResultsViewModel(query: ExploreQuery(category: "women"), api: fake)
        await model.results.loadIfNeeded()
        let start = ContinuousClock.now
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start + .seconds(30))
        #expect(fake.requests.count == 1)
        model.topDisappeared()
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start + .seconds(90))
        #expect(fake.requests.count == 1)
        await model.topAppeared()
        #expect(fake.requests.count == 2)
        #expect(fake.requests.last?.automatic == true)
    }
}

// MARK: - Brands and sizes

@MainActor
struct ExploreReferenceStoreTests {
    @Test func brandsLoadOnceAndAgainAfterAFailure() async {
        let fake = FakeExploreApi()
        fake.brandsResult = .failure(.network)
        let store = ExploreReferenceStore(api: fake)
        await store.loadBrands()
        #expect(store.brands.error == .network)
        fake.brandsResult = .success([CatalogBrand(id: "b", slug: "zara", name: "Zara")])
        await store.loadBrands()
        await store.loadBrands()
        #expect(store.brands.value?.map(\.slug) == ["zara"])
        #expect(store.brands.error == nil)
        #expect(fake.brandsCalls == 2)
    }

    @Test func refreshingTheBrandsAsksAgainAndKeepsThemOnFailure() async {
        let fake = FakeExploreApi()
        fake.brandsResult = .success([CatalogBrand(id: "b", slug: "zara", name: "Zara")])
        let store = ExploreReferenceStore(api: fake)
        await store.loadBrands()
        fake.brandsResult = .success([CatalogBrand(id: "c", slug: "mango", name: "Mango")])
        await store.refreshBrands()
        #expect(store.brands.value?.map(\.slug) == ["mango"])
        #expect(fake.brandsCalls == 2)
        fake.brandsResult = .failure(.network)
        await store.refreshBrands()
        #expect(store.brands.value?.map(\.slug) == ["mango"])
        #expect(store.brands.error == nil)
        #expect(fake.brandsCalls == 3)
    }

    @Test func sizesAreAskedAgainAfterFiveMinutes() async {
        let fake = FakeExploreApi()
        var now = ContinuousClock.now
        let store = ExploreReferenceStore(api: fake, clock: { now })
        await store.loadSizes()
        await store.loadSizes()
        #expect(fake.sizesCalls == 1)
        now += .seconds(301)
        fake.sizesResult = .failure(.server(status: 502))
        await store.loadSizes()
        #expect(fake.sizesCalls == 2)
        // A failure keeps the sizes on screen.
        #expect(store.sizes.value == ["38", "M"])
        #expect(store.sizes.error == nil)
    }
}
