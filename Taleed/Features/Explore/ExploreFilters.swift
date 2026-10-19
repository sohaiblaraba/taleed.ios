import Foundation

/// A filter of a search, as the results show it: one removable chip each (screens.md §7 G3, the
/// website's `FiltersBar`). The keywords and the sort are not filters.
enum ExploreFilter: String, Hashable, CaseIterable, Sendable {
    case category, brand, condition, size, wilaya, price
}

extension ExploreQuery {
    /// The sort the API applies when none is sent (`lib/search-sort.ts` `DEFAULT_SORT`).
    static let defaultSort = "recommended"

    /// The filters the API receives, in chip order. A value the API would reject (an unknown condition,
    /// a negative price) is not sent, so it shows no chip either.
    var activeFilters: [ExploreFilter] {
        let sent = ListingSearchParameters(self)
        var filters: [ExploreFilter] = []
        if sent.category != nil { filters.append(.category) }
        if sent.brand != nil { filters.append(.brand) }
        if sent.condition != nil { filters.append(.condition) }
        if sent.size != nil { filters.append(.size) }
        if sent.wilaya != nil { filters.append(.wilaya) }
        if sent.minPrice != nil || sent.maxPrice != nil { filters.append(.price) }
        return filters
    }

    /// The sort in effect: the query's when the API knows it, otherwise the default.
    var effectiveSort: String { ListingSearchParameters(self).sort ?? Self.defaultSort }

    /// Without one filter (its chip's ×).
    func removing(_ filter: ExploreFilter) -> ExploreQuery {
        var query = self
        switch filter {
        case .category: query.category = nil
        case .brand: query.brand = nil
        case .condition: query.condition = nil
        case .size: query.size = nil
        case .wilaya: query.wilaya = nil
        case .price:
            query.minPrice = nil
            query.maxPrice = nil
        }
        return query
    }

    /// "Tout effacer": the website keeps only the keywords (`FiltersBar.clearAll`), the sort included.
    var clearingFilters: ExploreQuery { ExploreQuery(text: text) }

    /// With another sort; the default one is left out, as the website leaves it out of the address.
    func sorted(by sort: String) -> ExploreQuery {
        var query = self
        query.sort = sort == Self.defaultSort ? nil : sort
        return query
    }

    /// With the keywords typed in the search field: trimmed, at most 100 characters (the API answers
    /// `400` beyond), none when blank. The filters stay.
    func searching(_ text: String) -> ExploreQuery {
        var query = self
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        query.text = trimmed.isEmpty ? nil : String(trimmed.prefix(ListingSearchParameters.maxTextLength))
        return query
    }
}

/// What the filter sheet edits before "Apply": every filter of the query, with the prices as typed.
struct FilterDraft: Equatable, Sendable {
    /// Prices are whole dinars; nine digits is far above any price the API accepts.
    static let maxPriceDigits = 9

    var category: String?
    var brand: String?
    var condition: String?
    var size: String?
    var wilaya: Int?
    var minPriceText: String
    var maxPriceText: String

    init(_ query: ExploreQuery) {
        let sent = ListingSearchParameters(query)
        category = sent.category
        brand = sent.brand
        condition = sent.condition
        size = sent.size
        wilaya = sent.wilaya
        minPriceText = sent.minPrice.map(String.init) ?? ""
        maxPriceText = sent.maxPrice.map(String.init) ?? ""
    }

    var minPrice: Int? { Int(minPriceText) }
    var maxPrice: Int? { Int(maxPriceText) }

    /// The minimum is above the maximum: the API would find nothing, so the sheet says so instead
    /// (screens.md §2 G3: validate `minPrice ≤ maxPrice` on the device).
    var hasPriceRangeError: Bool {
        guard let minPrice, let maxPrice else { return false }
        return minPrice > maxPrice
    }

    var canApply: Bool { !hasPriceRangeError }

    /// The filters set in the sheet, the price range counting once ("Filtres · 2").
    var activeCount: Int { applied(to: ExploreQuery()).activeFilters.count }

    /// The query with these filters; the keywords and the sort stay.
    func applied(to query: ExploreQuery) -> ExploreQuery {
        var result = query
        result.category = category
        result.brand = brand
        result.condition = condition
        result.size = size
        result.wilaya = wilaya
        result.minPrice = minPrice
        result.maxPrice = maxPrice
        return result
    }

    /// Clears every filter of the sheet.
    mutating func clear() {
        self = FilterDraft(ExploreQuery())
    }

    /// What a price field keeps of the typed text: digits only (Arabic-Indic digits become ASCII ones,
    /// so the Arabic keyboard works), at most `maxPriceDigits`, without leading zeros.
    static func priceText(_ typed: String) -> String {
        var digits = ""
        for character in typed {
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { continue }
            switch scalar.value {
            case 0x30...0x39: digits.unicodeScalars.append(scalar)
            case 0x660...0x669: digits.append(String(scalar.value - 0x660))
            case 0x6F0...0x6F9: digits.append(String(scalar.value - 0x6F0))
            default: continue
            }
        }
        while digits.count > 1, digits.hasPrefix("0") { digits.removeFirst() }
        return String(digits.prefix(maxPriceDigits))
    }
}

/// The labels of chips, fields and the sort control, from the catalog (screens.md §0.1: labels come
/// from the server) with the website's own words before the catalog arrived.
enum ExploreLabels {
    /// The chip of an active filter: the category's or brand's name, the condition's catalog label,
    /// the size, the wilaya's name, or the price range as the website writes it ("1 000 DA — Max").
    struct Context {
        var catalog: Catalog?
        var brands: [CatalogBrand] = []
        var language: AppLanguage
        var text: (L10nKey) -> String
    }

    static func chip(_ filter: ExploreFilter, query: ExploreQuery, context: Context) -> String {
        let (catalog, brands, language, text) = (context.catalog, context.brands, context.language, context.text)
        let sent = ListingSearchParameters(query)
        switch filter {
        case .category: return categoryName(sent.category, catalog: catalog) ?? ""
        case .brand: return brandName(sent.brand, brands: brands) ?? ""
        case .condition: return conditionName(sent.condition, catalog: catalog, language: language) ?? ""
        case .size: return sent.size ?? ""
        case .wilaya: return wilayaName(sent.wilaya, catalog: catalog) ?? ""
        case .price:
            let low = sent.minPrice.map { PriceFormatter.format($0, language: language) } ?? text(.filtersMinPrice)
            let high = sent.maxPrice.map { PriceFormatter.format($0, language: language) } ?? text(.filtersMaxPrice)
            return "\(low) — \(high)"
        }
    }

    /// A category's name in the app language; the slug when the catalog does not list it (the API
    /// ignores an unknown slug, but the member asked for it).
    static func categoryName(_ slug: String?, catalog: Catalog?) -> String? {
        guard let slug else { return nil }
        return catalog?.category(slug: slug)?.name ?? slug
    }

    static func brandName(_ slug: String?, brands: [CatalogBrand]) -> String? {
        guard let slug else { return nil }
        return brands.first { $0.slug == slug }?.name ?? slug
    }

    static func conditionName(_ code: String?, catalog: Catalog?, language: AppLanguage) -> String? {
        guard let code else { return nil }
        if let label = catalog?.condition(code)?.label, !label.isEmpty { return label }
        return ProductCondition.label(code: code, catalogLabel: "", catalogShortLabel: nil, length: .full, language: language)
    }

    static func wilayaName(_ id: Int?, catalog: Catalog?) -> String? {
        guard let id else { return nil }
        return catalog?.wilaya(id)?.name ?? String(id)
    }

    /// The sort options: the catalog's, in its order, without values this build cannot send; the
    /// website's labels before the catalog arrived.
    static func sorts(catalog: Catalog?, text: (L10nKey) -> String) -> [SheetOption<String>] {
        let fromCatalog = (catalog?.sorts ?? [])
            .filter { ListingSearchParameters.sorts.contains($0.value) }
            .map { SheetOption(id: $0.value, title: $0.label) }
        if !fromCatalog.isEmpty { return fromCatalog }
        return [
            SheetOption(id: "recommended", title: text(.filtersSortRecommended)),
            SheetOption(id: "newest", title: text(.filtersSortNewest)),
            SheetOption(id: "price_asc", title: text(.filtersSortPriceAsc)),
            SheetOption(id: "price_desc", title: text(.filtersSortPriceDesc)),
        ]
    }

    static func sortName(_ sort: String, catalog: Catalog?, text: (L10nKey) -> String) -> String {
        sorts(catalog: catalog, text: text).first { $0.id == sort }?.title ?? text(.filtersSortRecommended)
    }
}
