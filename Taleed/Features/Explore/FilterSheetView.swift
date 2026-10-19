import SwiftUI

/// The filter sheet (screens.md §2 G3 screen 3, §7 G3): one value per filter, as on the website —
/// category (two levels in one list), brand (searchable), condition, size, the wilaya the item ships
/// from, and a price range checked on the device (`min ≤ max`). "Tout effacer" empties the sheet;
/// "Appliquer" shows the results. The keywords and the sort are not touched.
///
/// A sheet for filters (design-system §5.3: handle, start-aligned title, close), full height because
/// the lists are long; each list opens inside the sheet and comes back to it.
struct FilterSheetView: View {
    let query: ExploreQuery
    let onApply: (ExploreQuery) -> Void
    @State private var draft: FilterDraft
    @State private var path: [FilterPicker] = []
    @Environment(LanguageManager.self) private var l10n
    @Environment(CatalogStore.self) private var catalog
    @Environment(ExploreReferenceStore.self) private var references
    @Environment(\.dismiss) private var dismiss

    init(query: ExploreQuery, onApply: @escaping (ExploreQuery) -> Void) {
        self.query = query
        self.onApply = onApply
        _draft = State(initialValue: FilterDraft(query))
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                ScrollView {
                    fields
                        .padding(.horizontal, TaleedSize.bottomSheetPaddingX)
                        .padding(.top, TaleedSpacing.s8)
                        .padding(.bottom, TaleedSpacing.s24)
                }
                .scrollDismissesKeyboard(.interactively)
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
        .presentationDetents([.large])
        .presentationCornerRadius(TaleedSize.bottomSheetTopRadius)
        .presentationDragIndicator(.hidden)
        .presentationBackground(TaleedColor.surfacePrimary)
    }

    // MARK: Chrome

    private var header: some View {
        VStack(spacing: TaleedSize.bottomSheetGap) {
            Capsule()
                .fill(TaleedColor.sheetHandle)
                .frame(width: TaleedSize.bottomSheetHandleWidth, height: TaleedSize.bottomSheetHandleHeight)
                .accessibilityHidden(true)
            HStack {
                Text(l10n.string(.filtersTitle))
                    .taleedFont(TaleedTextStyle(size: 18, weight: .regular, lineHeight: nil, letterSpacing: 0, relativeTo: .body))
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { dismiss() } label: {
                    TaleedIconView(.x, size: 20, color: TaleedColor.textSecondary)
                        .frame(width: TaleedSize.touchTargetMin, height: TaleedSize.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.string(.commonClose))
            }
        }
        .padding(.top, TaleedSize.bottomSheetPaddingTop)
        .padding(.horizontal, TaleedSize.bottomSheetPaddingX)
        .padding(.bottom, TaleedSpacing.s8)
    }

    /// "Tout effacer" and "Appliquer", above the keyboard and the home indicator.
    private var footer: some View {
        HStack(spacing: TaleedSpacing.s12) {
            TaleedButton(title: l10n.string(.filtersClear), kind: .outline, size: .large) {
                withAnimation { draft.clear() }
            }
            .disabled(draft == FilterDraft(ExploreQuery()))
            TaleedButton(title: l10n.string(.commonApply), kind: .primary, size: .large, isFullWidth: true) {
                onApply(draft.applied(to: query))
                dismiss()
            }
            .disabled(!draft.canApply)
            .accessibilityIdentifier("filters.apply")
        }
        .padding(.horizontal, TaleedSize.bottomSheetPaddingX)
        .padding(.vertical, TaleedSpacing.s12)
        .background(TaleedColor.surfacePrimary)
        .overlay(alignment: .top) { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
    }

    // MARK: Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
            select(.category, value: ExploreLabels.categoryName(draft.category, catalog: catalog.catalog))
            select(.brand, value: ExploreLabels.brandName(draft.brand, brands: references.brands.value ?? []))
            select(.condition,
                   value: ExploreLabels.conditionName(draft.condition, catalog: catalog.catalog, language: l10n.language))
            // As on the website, the size only shows while some item on sale has one.
            if draft.size != nil || !(references.sizes.value?.isEmpty ?? true) {
                select(.size, value: draft.size)
            }
            select(.wilaya, value: ExploreLabels.wilayaName(draft.wilaya, catalog: catalog.catalog))
            priceRange
        }
    }

    private func select(_ picker: FilterPicker, value: String?) -> some View {
        TaleedSelectField(label: title(of: picker), value: value, placeholder: l10n.string(.navAllItems)) {
            path.append(picker)
        }
        .accessibilityIdentifier("filters.\(picker.rawValue)")
    }

    private var priceRange: some View {
        let error = draft.hasPriceRangeError ? l10n.string(.appExplorePriceRangeInvalid) : nil
        return VStack(alignment: .leading, spacing: TaleedSize.inputLabelGap) {
            FieldLabel(text: l10n.string(.filtersPrice),
                       color: error == nil ? TaleedColor.textPrimary : TaleedColor.feedbackError)
            HStack(spacing: TaleedSpacing.s8) {
                TaleedTextField(text: priceBinding(\.minPriceText), placeholder: l10n.string(.filtersMinPrice),
                                error: error, showsMessage: false)
                    .accessibilityIdentifier("filters.minPrice")
                Text(verbatim: "—")
                    .foregroundStyle(TaleedColor.textSecondary)
                    .accessibilityHidden(true)
                TaleedTextField(text: priceBinding(\.maxPriceText), placeholder: l10n.string(.filtersMaxPrice),
                                error: error, showsMessage: false)
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

/// A list of the filter sheet.
enum FilterPicker: String, Hashable, Sendable {
    case category, brand, condition, size, wilaya

    /// Long lists get a search field.
    var isSearchable: Bool { self == .brand || self == .wilaya || self == .category }
}

/// A choice of a filter list: nil `value` is "Tout" (no filter).
struct FilterOption: Identifiable, Hashable, Sendable {
    let value: String?
    let title: String
    /// A top-level category: bold, its subcategories indented under it.
    var isGroup = false
    var isIndented = false
    /// Also matched by the search field (the wilaya's code).
    var searchText: String?

    var id: String { value ?? "" }

    /// The two levels in one list, as the website's category select: each top-level category (which
    /// includes its subcategories), then its subcategories.
    static func categories(_ categories: [CatalogCategory]) -> [FilterOption] {
        categories.flatMap { parent in
            [FilterOption(value: parent.slug, title: parent.name, isGroup: !parent.children.isEmpty)]
                + parent.children.map { FilterOption(value: $0.slug, title: $0.name, isIndented: true, searchText: parent.name) }
        }
    }

    /// Whether the option matches what the member typed: case- and accent-insensitive, on its title,
    /// its extra search text, or (for a subcategory) its category's name.
    func matches(_ typed: String) -> Bool {
        let query = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if value == nil { return false }
        return [title, searchText].compactMap { $0 }.contains { $0.localizedStandardContains(query) }
    }
}

/// One filter's choices, pushed inside the filter sheet: back, the list (searchable when long), a check
/// on the current choice. Choosing goes back to the sheet.
struct FilterOptionsView: View {
    struct Remote {
        var isLoading = false
        var error: ApiError?
    }

    let title: String
    let options: [FilterOption]
    let selection: String?
    let isSearchable: Bool
    let remote: Remote
    let retry: () -> Void
    let onSelect: (String?) -> Void
    @State private var searchText = ""
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TaleedTopAppBar(title: title, onBack: { dismiss() })
            if isSearchable, options.count > 1 {
                TaleedTextField(text: $searchText, placeholder: l10n.string(.commonSearch), leadingIcon: .magnifyingGlass)
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .padding(.vertical, TaleedSpacing.s12)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var content: some View {
        if options.count <= 1, let error = remote.error {
            ErrorStateView(error: error, retry: retry, onBack: { dismiss() })
        } else if options.count <= 1, remote.isLoading {
            LoadingStateView()
        } else {
            let shown = options.filter { $0.matches(searchText) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { option in
                        FilterOptionRow(option: option, isSelected: option.value == selection) { onSelect(option.value) }
                    }
                    if shown.isEmpty {
                        Text(l10n.string(.filtersNoResults))
                            .taleedFont(TaleedFont.bodyRegular)
                            .foregroundStyle(TaleedColor.textBody)
                            .multilineTextAlignment(.center)
                            .padding(TaleedSpacing.s24)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }
}

/// A choice row: at least 56 high, the label (bold for a category, indented for a subcategory) and a
/// check when chosen.
private struct FilterOptionRow: View {
    let option: FilterOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: TaleedSpacing.s12) {
                    Text(verbatim: option.title)
                        .taleedFont(option.isGroup || isSelected ? TaleedFont.bodyLarge.with(weight: .semibold) : TaleedFont.bodyLarge)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isSelected { TaleedIconView(.check, size: 20, color: TaleedColor.brandPrimary) }
                }
                .padding(.vertical, TaleedSpacing.s12)
                .padding(.leading, option.isIndented ? TaleedLayout.screenMargin + TaleedSpacing.s24 : TaleedLayout.screenMargin)
                .padding(.trailing, TaleedLayout.screenMargin)
                .frame(maxWidth: .infinity, minHeight: 56)
                Rectangle()
                    .fill(TaleedColor.borderSubtle)
                    .frame(height: 1)
                    .padding(.leading, TaleedLayout.screenMargin)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
