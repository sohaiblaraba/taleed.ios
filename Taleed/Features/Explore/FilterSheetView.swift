import SwiftUI

/// The filters sheet (search-results.md, Figma "Filters" 218:3162; screens.md §2 G3 screen 3, §7 G3): the
/// drag handle, then "SORT BY" with the API's sorts as single-select chips, then "FILTERS": one value per
/// filter, as on the website — category (two levels in one list), brand (searchable), condition, size,
/// the wilaya the item ships from — and the price: a two-thumb slider over 0–200 000 DA (step 500) with
/// the two amounts below, which are the source of truth and checked on the device (`min ≤ max`). The
/// sticky footer: "Tout effacer" empties the sheet, "Appliquer" shows the results. The keywords stay.
///
/// It covers the bottom navigation; each list opens inside the sheet and comes back to it.
struct FilterSheetView: View {
    let query: ExploreQuery
    let onApply: (ExploreQuery) -> Void
    @State private var draft: FilterDraft
    @State private var path: [FilterPicker] = []
    @State private var detent: PresentationDetent
    @Environment(LanguageManager.self) private var l10n
    @Environment(CatalogStore.self) private var catalog
    @Environment(ExploreReferenceStore.self) private var references
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Figma's sheet stands over about 70 % of the screen; it grows to the full height for a list.
    private static let partialDetent = PresentationDetent.fraction(0.75)

    init(query: ExploreQuery, startsExpanded: Bool = false, onApply: @escaping (ExploreQuery) -> Void) {
        self.query = query
        self.onApply = onApply
        _draft = State(initialValue: FilterDraft(query))
        _detent = State(initialValue: startsExpanded ? .large : Self.partialDetent)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                handle
                ScrollView {
                    fields
                        .padding(.horizontal, TaleedLayout.screenMargin)
                        .padding(.top, TaleedSpacing.s24)
                        .padding(.bottom, TaleedSpacing.s24)
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("filters.scroll")
                footer
            }
            .background(TaleedColor.surfacePrimary.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: FilterPicker.self) { picker in
                FilterOptionsView(title: title(of: picker), options: options(for: picker), selection: selection(of: picker),
                                  isSearchable: picker.isSearchable, remote: remoteState(of: picker),
                                  retry: { Task { await load(picker) } },
                                  onSelect: { value in
                                      select(value, in: picker)
                                      path.removeAll()
                                  })
                .task { await load(picker) }
            }
        }
        .task {
            // The sizes decide whether the size field shows; the brands name the chosen brand.
            async let sizes: Void = references.loadSizes()
            async let brands: Void = references.loadBrands()
            _ = await (sizes, brands)
        }
        // A list needs the height (and its search field the keyboard's room).
        .onChange(of: path) { _, path in if !path.isEmpty { detent = .large } }
        .presentationDetents([Self.partialDetent, .large], selection: $detent)
        .presentationCornerRadius(TaleedSize.bottomSheetTopRadius)
        .presentationDragIndicator(.hidden)
        .presentationBackground(TaleedColor.surfacePrimary)
        .accessibilityAction(.escape) { dismiss() }
    }

    // MARK: Chrome

    /// The design-system sheet handle (§5.3); Figma's sheet has no title or close button.
    private var handle: some View {
        Capsule()
            .fill(TaleedColor.sheetHandle)
            .frame(width: TaleedSize.bottomSheetHandleWidth, height: TaleedSize.bottomSheetHandleHeight)
            .frame(maxWidth: .infinity)
            .padding(.top, TaleedSize.bottomSheetPaddingTop)
            .accessibilityHidden(true)
    }

    /// "Tout effacer" and "Appliquer", above the keyboard and the home indicator; one above the other
    /// from accessibility text sizes on, so that neither label breaks.
    private var footer: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: TaleedSpacing.s8))
            : AnyLayout(HStackLayout(spacing: TaleedSpacing.s12))
        return layout {
            if stacked { applyButton }
            TaleedButton(title: l10n.string(.filtersClear), kind: .outline, size: .large, isFullWidth: stacked) {
                withAnimation { draft.clear() }
            }
            .disabled(draft == FilterDraft(ExploreQuery()))
            .accessibilityIdentifier("filters.clear")
            if !stacked { applyButton }
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
        .padding(.vertical, TaleedSpacing.s12)
        .background(TaleedColor.surfacePrimary)
        .overlay(alignment: .top) { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
    }

    private var applyButton: some View {
        TaleedButton(title: l10n.string(.commonApply), kind: .primary, size: .large, isFullWidth: true) {
            onApply(draft.applied(to: query))
            dismiss()
        }
        .disabled(!draft.canApply)
        .accessibilityIdentifier("filters.apply")
    }

    // MARK: Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
            Eyebrow(text: l10n.string(.appExploreSortBy))
                .accessibilityAddTraits(.isHeader)
            sortChips
            Eyebrow(text: l10n.string(.filtersTitle))
                .accessibilityAddTraits(.isHeader)
            select(.category, value: ExploreLabels.categoryName(draft.category, catalog: catalog.catalog))
            select(.brand, value: ExploreLabels.brandName(draft.brand, brands: references.brands.value ?? []))
            select(.condition,
                   value: ExploreLabels.conditionName(draft.condition, catalog: catalog.catalog, language: l10n.language))
            // As on the website, the size only shows while some item on sale has one.
            if draft.size != nil || !(references.sizes.value?.isEmpty ?? true) {
                select(.size, value: draft.size)
            }
            // Not in Figma; the website filters on it (search-results.md).
            select(.wilaya, value: ExploreLabels.wilayaName(draft.wilaya, catalog: catalog.catalog))
            priceRange
        }
    }

    /// The API's sorts in one scrolling row, edge to edge.
    private var sortChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TaleedSpacing.s8) {
                ForEach(ExploreLabels.sorts(catalog: catalog.catalog, text: l10n.string)) { option in
                    ChoiceChip(title: option.title, isSelected: option.id == draft.sort) { draft.sort = option.id }
                        .accessibilityIdentifier("filters.sort.\(option.id)")
                }
            }
            .padding(.horizontal, TaleedLayout.screenMargin)
            .padding(.vertical, 2)
        }
        .padding(.horizontal, -TaleedLayout.screenMargin)
    }

    private func select(_ picker: FilterPicker, value: String?) -> some View {
        TaleedSelectField(label: title(of: picker), value: value, placeholder: placeholder(of: picker)) {
            path.append(picker)
        }
        .accessibilityIdentifier("filters.\(picker.rawValue)")
    }

    /// "Prix", the slider, then "Min" "à" "Max" (amounts with the DA suffix, decision D-5).
    private var priceRange: some View {
        let error = draft.hasPriceRangeError ? l10n.string(.appExplorePriceRangeInvalid) : nil
        let currency = PriceFormatter.currencySuffix(language: l10n.language)
        return VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            FieldLabel(text: l10n.string(.filtersPrice),
                       color: error == nil ? TaleedColor.textPrimary : TaleedColor.feedbackError)
            TaleedRangeSlider(lower: Binding(get: { draft.sliderLower }, set: { draft.setSliderLower($0) }),
                              upper: Binding(get: { draft.sliderUpper }, set: { draft.setSliderUpper($0) }),
                              bounds: FilterDraft.priceSliderBounds, step: FilterDraft.priceSliderStep,
                              accessibilityStep: 5_000,
                              lowerLabel: l10n.string(.filtersMinPrice), upperLabel: l10n.string(.filtersMaxPrice),
                              valueText: { PriceFormatter.format($0, language: l10n.language) })
                .accessibilityIdentifier("filters.priceSlider")
            HStack(spacing: TaleedSpacing.s16) {
                TaleedTextField(text: priceBinding(\.minPriceText), placeholder: l10n.string(.filtersMinPrice),
                                suffix: currency, error: error, showsClearButton: false, showsMessage: false)
                    .accessibilityIdentifier("filters.minPrice")
                Text(l10n.string(.appExplorePriceTo))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textSecondary)
                    .fixedSize()
                    .accessibilityHidden(true)
                TaleedTextField(text: priceBinding(\.maxPriceText), placeholder: l10n.string(.filtersMaxPrice),
                                suffix: currency, error: error, showsClearButton: false, showsMessage: false)
                    .accessibilityIdentifier("filters.maxPrice")
            }
            .keyboardType(.numberPad)
            .onChange(of: draft.minPriceText) { _, _ in cleanPrice(\.minPriceText) }
            .onChange(of: draft.maxPriceText) { _, _ in cleanPrice(\.maxPriceText) }
            if let error {
                FieldHelper(text: error, color: TaleedColor.feedbackError)
            }
        }
    }

    /// A price field keeps digits only (Arabic-Indic digits become ASCII ones), as whole dinars. The
    /// text is cleaned after the change, so the field shows the cleaned text (a binding that refuses the
    /// change would leave the typed characters on screen).
    private func priceBinding(_ keyPath: WritableKeyPath<FilterDraft, String>) -> Binding<String> {
        Binding(get: { draft[keyPath: keyPath] }, set: { draft[keyPath: keyPath] = $0 })
    }

    private func cleanPrice(_ keyPath: WritableKeyPath<FilterDraft, String>) {
        let cleaned = FilterDraft.priceText(draft[keyPath: keyPath])
        if cleaned != draft[keyPath: keyPath] { draft[keyPath: keyPath] = cleaned }
    }

    // MARK: Pickers

    private func title(of picker: FilterPicker) -> String {
        switch picker {
        case .category: l10n.string(.filtersCategory)
        case .brand: l10n.string(.filtersBrand)
        case .condition: l10n.string(.filtersCondition)
        case .size: l10n.string(.filtersSize)
        case .wilaya: l10n.string(.listingShipsFrom)
        }
    }

    /// Figma's placeholders ("Choose brand"), in the website's words where it has them.
    private func placeholder(of picker: FilterPicker) -> String {
        switch picker {
        case .category: l10n.string(.sellSelectCategory)
        case .brand: l10n.string(.sellSelectBrand)
        case .condition: l10n.string(.sellSelectCondition)
        case .size: l10n.string(.appExploreSelectSize)
        case .wilaya: l10n.string(.checkoutSelectWilaya)
        }
    }

    private func selection(of picker: FilterPicker) -> String? {
        switch picker {
        case .category: draft.category
        case .brand: draft.brand
        case .condition: draft.condition
        case .size: draft.size
        case .wilaya: draft.wilaya.map(String.init)
        }
    }

    private func select(_ value: String?, in picker: FilterPicker) {
        switch picker {
        case .category: draft.category = value
        case .brand: draft.brand = value
        case .condition: draft.condition = value
        case .size: draft.size = value
        case .wilaya: draft.wilaya = value.flatMap(Int.init)
        }
    }

    private func options(for picker: FilterPicker) -> [FilterOption] {
        let all = FilterOption(value: nil, title: l10n.string(.navAllItems))
        let catalog = catalog.catalog
        switch picker {
        case .category:
            return [all] + FilterOption.categories(catalog?.categories ?? [])
        case .brand:
            return [all] + (references.brands.value ?? []).map { FilterOption(value: $0.slug, title: $0.name) }
        case .condition:
            let codes = catalog?.conditions.map(\.value).filter(ListingSearchParameters.conditions.contains)
                ?? ProductCondition.allCases.map(\.rawValue)
            return [all] + codes.map {
                FilterOption(value: $0, title: ExploreLabels.conditionName($0, catalog: catalog, language: l10n.language) ?? $0)
            }
        case .size:
            var sizes = references.sizes.value ?? []
            if let chosen = draft.size, !sizes.contains(where: { $0.caseInsensitiveCompare(chosen) == .orderedSame }) {
                sizes.insert(chosen, at: 0)
            }
            return [all] + sizes.map { FilterOption(value: $0, title: $0) }
        case .wilaya:
            return [all] + (catalog?.wilayas ?? []).map {
                FilterOption(value: String($0.id), title: $0.name, searchText: String($0.id))
            }
        }
    }

    /// The loading state of the lists that come from the API.
    private func remoteState(of picker: FilterPicker) -> FilterOptionsView.Remote {
        switch picker {
        case .brand: FilterOptionsView.Remote(isLoading: references.brands.value == nil && references.brands.isLoading,
                                              error: references.brands.value == nil ? references.brands.error : nil)
        case .size: FilterOptionsView.Remote(isLoading: references.sizes.value == nil && references.sizes.isLoading,
                                             error: references.sizes.value == nil ? references.sizes.error : nil)
        case .category, .condition, .wilaya:
            FilterOptionsView.Remote(isLoading: catalog.catalog == nil && catalog.isRefreshing,
                                     error: catalog.catalog == nil ? catalog.error : nil)
        }
    }

    private func load(_ picker: FilterPicker) async {
        switch picker {
        case .brand: await references.loadBrands()
        case .size: await references.loadSizes()
        case .category, .condition, .wilaya: if catalog.catalog == nil { await catalog.refresh() }
        }
    }
}
