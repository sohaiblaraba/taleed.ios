import SwiftUI
#if DEBUG
import OSLog
#endif

/// Search results (screens.md §2 G3, Figma composed pattern "B. Search results" 8:14404): the search
/// header with back, the editable keywords and clear; the filter chips ("Filtres · 2" opens the filter
/// sheet, each active filter is a removable chip, then "Tout effacer"); the count and the sort control,
/// which opens the sort sheet (§5.3); then the dense result rows, page by page.
///
/// States: skeleton rows while the first page loads, the error (offline included) with Retry, the empty
/// state with "Clear filters", pull-to-refresh, the pagination footer.
struct SearchResultsView: View {
    @State private var viewModel: SearchResultsViewModel
    @State private var showsSort = false
    @State private var sortSelection = ExploreQuery.defaultSort
    @State private var showsFilters = false
    @Environment(LanguageManager.self) private var l10n
    @Environment(CatalogStore.self) private var catalog
    @Environment(ExploreReferenceStore.self) private var references
    @Environment(FavoriteStore.self) private var favorites
    @Environment(ListingChangeCenter.self) private var listingChanges
    @Environment(AppToasts.self) private var toasts
    @Environment(SessionManager.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private static let topID = "results.top"

    init(query: ExploreQuery, api: any ListingsApi) {
        _viewModel = State(initialValue: SearchResultsViewModel(query: query, api: api))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        ShellScreen {
            SearchHeader(text: $viewModel.searchText, placeholder: l10n.string(.appExploreSearchPlaceholder),
                         onBack: { dismiss() }, onSubmit: { viewModel.submitSearch() }, filters: { filterChips })
            .textInputAutocapitalization(.never)
            .onChange(of: viewModel.searchText) { _, text in
                if text.utf16.count > ListingSearchParameters.maxTextLength {
                    viewModel.searchText = text.prefix(utf16Units: ListingSearchParameters.maxTextLength)
                }
            }
        } content: {
            results
                .background(TaleedColor.surfaceGrouped)
        }
        .task(id: ObjectIdentifier(viewModel.results)) { await viewModel.results.loadIfNeeded() }
        .task(id: viewModel.query.brand) {
            // The brand chip shows the brand's name, not its slug.
            if viewModel.query.brand != nil { await references.loadBrands() }
        }
        #if DEBUG
        .onChange(of: viewModel.results.items.count) { _, count in
            let unique = Set(viewModel.results.items.map(\.id)).count
            Logger(subsystem: "app.taleed", category: "search").notice("results show \(count) cards, \(unique) unique")
        }
        #endif
        .onChange(of: viewModel.results.refreshError) { _, error in
            if let error { toasts.show(error: error) }
        }
        .onChange(of: session.user?.id) { _, _ in viewModel.memberDidChange() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: viewModel.wentToBackground()
            case .active: Task { await viewModel.returnedToForeground() }
            default: break
            }
        }
        .sortBottomSheet(isPresented: $showsSort, title: l10n.string(.filtersSort),
                         options: ExploreLabels.sorts(catalog: catalog.catalog, text: l10n.string),
                         selection: $sortSelection) {
            viewModel.sort(by: sortSelection)
        }
        .sheet(isPresented: $showsFilters) {
            FilterSheetView(query: viewModel.query) { viewModel.apply($0) }
                .appLanguage(l10n.language)
        }
    }

    // MARK: Header

    private var filterChips: some View {
        let query = viewModel.query
        let active = query.activeFilters
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TaleedSpacing.s8) {
                FilterChip(title: filtersTitle(count: active.count), icon: .slidersHorizontal, tone: .brand) {
                    showsFilters = true
                }
                .accessibilityIdentifier("results.filters")
                ForEach(active, id: \.self) { filter in
                    RemovableFilterChip(title: chipLabel(filter), tone: Self.tone(filter)) {
                        withAnimation { viewModel.remove(filter) }
                    }
                }
                if !active.isEmpty {
                    TaleedButton(title: l10n.string(.filtersClear), kind: .hyperlink, size: .small) {
                        withAnimation { viewModel.clearFilters() }
                    }
                }
            }
            .padding(.horizontal, TaleedLayout.screenMargin)
            .padding(.vertical, 2)
        }
        // Chips that run past the edge fade out there, so the row reads as one that scrolls.
        .mask {
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: TaleedLayout.screenMargin + TaleedSpacing.s8)
                    .flipsForRightToLeftLayoutDirection(true)
            }
        }
    }

    /// "Filtres", or "Filtres · 2" with active filters (the Figma pattern's chip).
    private func filtersTitle(count: Int) -> String {
        let title = l10n.string(.filtersTitle)
        guard count > 0 else { return title }
        return "\(title) · \(count)"
    }

    private func chipLabel(_ filter: ExploreFilter) -> String {
        ExploreLabels.chip(filter, query: viewModel.query,
                           context: .init(catalog: catalog.catalog, brands: references.brands.value ?? [],
                                          language: l10n.language, text: { l10n.string($0) }))
    }

    /// The Figma pattern's chip colours: the location in the success tone, the size neutral, the others
    /// in the brand tone.
    static func tone(_ filter: ExploreFilter) -> TaleedTone {
        switch filter {
        case .wilaya: .success
        case .size: .neutral
        case .category, .brand, .condition, .price: .brand
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        let list = viewModel.results
        if list.hasLoaded {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: TaleedSpacing.s12) {
                        let listings = listingChanges.cards(list.items.filter { !favorites.removedIds.contains($0.id) })
                        // No count and sort over the empty state, which already says there is nothing.
                        Group {
                            if listings.isEmpty {
                                Color.clear.frame(height: 0)
                            } else {
                                summary
                            }
                        }
                        .id(Self.topID)
                        .onAppear { Task { await viewModel.topAppeared() } }
                        .onDisappear { viewModel.topDisappeared() }
                        if listings.isEmpty {
                            emptyState.padding(.top, TaleedSpacing.s24)
                        } else {
                            ForEach(listings) { SearchResultRow(listing: $0) }
                            PaginationFooter(list: list)
                        }
                    }
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .padding(.top, TaleedSpacing.s4)
                    .padding(.bottom, TaleedSpacing.s24)
                }
                .refreshable { await list.refresh() }
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: ObjectIdentifier(list)) { _, _ in proxy.scrollTo(Self.topID, anchor: .top) }
            }
        } else if let error = list.error {
            ErrorStateView(error: error, retry: { Task { await list.reload() } }, onBack: { dismiss() })
        } else {
            ScrollView {
                SkeletonProductList(count: 5)
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .padding(.top, TaleedSpacing.s16)
            }
            .scrollDisabled(true)
        }
    }

    /// "126 articles" and the sort ("Recommandés ⌄"), which opens the sort sheet.
    private var summary: some View {
        let total = viewModel.results.total ?? 0
        let count = l10n.format(.filtersResults, total)
        let sort = viewModel.query.effectiveSort
        let sortName = ExploreLabels.sortName(sort, catalog: catalog.catalog, text: l10n.string)
        return ResultsSummaryRow(countLabel: count, sortLabel: sortName) {
            sortSelection = sort
            showsSort = true
        }
        // One element: the count (with the keywords), then the sort it opens.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryAccessibilityLabel(count: count))
        .accessibilityValue("\(l10n.string(.filtersSort)) : \(sortName)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            sortSelection = sort
            showsSort = true
        }
    }

    /// "Résultats pour « zara », 1 article" (the website's heading and count) for VoiceOver.
    private func summaryAccessibilityLabel(count: String) -> String {
        guard let text = viewModel.query.text, !text.isEmpty else { return count }
        return l10n.format(.filtersSearchFor, text) + ", " + count
    }

    /// Figma's empty state: with filters, "Clear filters". The website's sentence, or Figma's "another
    /// city" one when a wilaya filter is on.
    private var emptyState: some View {
        let filters = viewModel.query.activeFilters
        let hasFilters = !filters.isEmpty
        return EmptyState(
            title: l10n.string(.appExploreEmptyTitle),
            message: l10n.string(filters.contains(.wilaya) ? .appExploreEmptyBody : .filtersNoResults),
            actionTitle: hasFilters ? l10n.string(.appExploreClearFilters) : nil,
            action: hasFilters ? { withAnimation { viewModel.clearFilters() } } : nil
        )
    }
}

/// A result row (design-system §3.3 dense variant, as in the Figma search pattern): photo, condition
/// tag, title, price and wilaya, the heart top right. Opens the listing.
struct SearchResultRow: View {
    let listing: ListingSummary
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoriteStore.self) private var favorites
    @Environment(AppRouter.self) private var router
    @Environment(SessionManager.self) private var session
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ProductListRow(
            product: ListingCardContent.product(for: listing, favorite: favorites.state(for: listing),
                                                catalog: catalog.catalog, text: { l10n.string($0) }),
            style: .dense,
            onTap: { router.push(.listing(id: listing.id)) },
            onFavorite: favorite
        )
    }

    private func favorite() {
        if session.isSignedIn {
            favorites.toggle(listing)
        } else {
            router.requireSignIn { [favorites, listing] in favorites.setFavorite(listing, to: true) }
        }
    }
}
