@testable import Taleed
import Testing

// MARK: - The filter sheet

struct FilterDraftTests {
    @Test func startsFromTheQueryAndKeepsKeywordsAndSort() {
        let query = ExploreQuery(text: "robe", category: "women", wilaya: 16, minPrice: 1000, sort: "newest")
        var draft = FilterDraft(query)
        #expect(draft.category == "women")
        #expect(draft.minPriceText == "1000")
        #expect(draft.maxPriceText.isEmpty)
        draft.brand = "zara"
        draft.maxPriceText = "5000"
        #expect(draft.applied(to: query) == ExploreQuery(text: "robe", category: "women", brand: "zara", wilaya: 16,
                                                         minPrice: 1000, maxPrice: 5000, sort: "newest"))
        #expect(draft.activeCount == 4)
    }

    @Test func clearEmptiesEveryFilter() {
        var draft = FilterDraft(ExploreQuery(category: "women", condition: "GOOD", size: "M", maxPrice: 900))
        draft.clear()
        #expect(draft == FilterDraft(ExploreQuery()))
        // The sort goes too, as the website's "Tout effacer"; the keywords stay.
        #expect(draft.applied(to: ExploreQuery(text: "robe", sort: "newest")) == ExploreQuery(text: "robe"))
    }

    @Test func theSortIsChosenInTheSheetAndNotCountedAsAFilter() {
        let query = ExploreQuery(text: "robe", category: "women")
        var draft = FilterDraft(query)
        #expect(draft.sort == ExploreQuery.defaultSort)
        draft.sort = "price_desc"
        #expect(draft.applied(to: query) == ExploreQuery(text: "robe", category: "women", sort: "price_desc"))
        #expect(draft.activeCount == 1)
        // The default sort is left out of the query, as the website leaves it out of the address.
        draft.sort = ExploreQuery.defaultSort
        #expect(draft.applied(to: ExploreQuery(category: "women", sort: "newest")) == ExploreQuery(category: "women"))
        // A sort the API does not know starts as the default one.
        #expect(FilterDraft(ExploreQuery(sort: "distance")).sort == ExploreQuery.defaultSort)
    }

    @Test func theSliderFollowsTheFields() {
        var draft = FilterDraft(ExploreQuery())
        // No limits: the thumbs at both ends.
        #expect(draft.sliderLower == 0)
        #expect(draft.sliderUpper == 200_000)
        draft.minPriceText = "2500"
        draft.maxPriceText = "350000"
        #expect(draft.sliderLower == 2500)
        // Past the end: the thumb is pinned there, the field keeps the amount.
        #expect(draft.sliderUpper == 200_000)
        draft.setSliderUpper(200_000)
        #expect(draft.maxPriceText == "350000")
    }

    @Test func movingAThumbFillsItsField() {
        var draft = FilterDraft(ExploreQuery(minPrice: 1000, maxPrice: 9000))
        draft.setSliderLower(3_500)
        draft.setSliderUpper(60_000)
        #expect(draft.minPriceText == "3500")
        #expect(draft.maxPriceText == "60000")
        // Back at an end: no limit on that side.
        draft.setSliderLower(0)
        draft.setSliderUpper(200_000)
        #expect(draft.minPriceText.isEmpty)
        #expect(draft.maxPriceText.isEmpty)
        #expect(draft.applied(to: ExploreQuery()).activeFilters.isEmpty)
    }

    @Test(arguments: [(0, 0), (249, 0), (250, 500), (12_345, 12_500), (199_900, 200_000), (250_000, 200_000), (-10, 0)])
    func sliderValuesSnapToTheStep(value: Int, snapped: Int) {
        #expect(TaleedRangeSlider.snapped(value, bounds: FilterDraft.priceSliderBounds, step: FilterDraft.priceSliderStep)
            == snapped)
    }

    @Test func minimumAboveMaximumIsRefused() {
        var draft = FilterDraft(ExploreQuery())
        draft.minPriceText = "5000"
        draft.maxPriceText = "3000"
        #expect(draft.hasPriceRangeError)
        #expect(!draft.canApply)
        draft.maxPriceText = "5000"
        #expect(!draft.hasPriceRangeError)
        draft.maxPriceText = ""
        #expect(draft.canApply)
    }

    @Test(arguments: [
        ("5000", "5000"),
        ("٥٠٠٠", "5000"),
        ("۱۲۰۰", "1200"),
        ("5 000 DA", "5000"),
        ("-12.5", "125"),
        ("007", "7"),
        ("0", "0"),
        ("abc", ""),
        ("12345678901", "123456789"),
    ])
    func pricesKeepDigitsOnly(typed: String, kept: String) {
        #expect(FilterDraft.priceText(typed) == kept)
    }

    @Test func categoriesAreTwoLevelsInOneList() {
        let categories = [CatalogCategory(id: "1", slug: "women", name: "Femmes", children: [
            CatalogCategory(id: "2", slug: "women-shoes", name: "Chaussures"),
        ])]
        let options = FilterOption.categories(categories)
        #expect(options.map(\.value) == ["women", "women-shoes"])
        #expect(options[0].isGroup && !options[0].isIndented)
        #expect(options[1].isIndented)
        // A subcategory is found by its name or its category's name, without accents.
        #expect(options[1].matches("chaussure"))
        #expect(options[1].matches("femmes"))
        #expect(FilterOption(value: "16", title: "Béjaïa", searchText: "6").matches("bejaia"))
        #expect(!FilterOption(value: nil, title: "Tout").matches("tout"))
    }
}
