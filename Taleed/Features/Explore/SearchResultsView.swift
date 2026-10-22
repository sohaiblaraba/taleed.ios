import SwiftUI
#if DEBUG
import OSLog
#endif

/// Search results (search-results.md, Figma "Search Results" 218:2909; screens.md §2 G3): the app bar
/// with back, the centred "Résultats" and the trust shield (buyer protection); the search row — the editable keywords with
/// clear, and the filter button with the number of active filters (sort excluded) that opens the
/// filters sheet, where the sort lives too; one removable chip per active filter; then the count and the
/// two-column product-card grid, page by page.
///
/// States: skeleton cards while the first page loads, the error (offline included) with Retry, the empty
/// state with "Clear filters", pull-to-refresh, the pagination footer.
struct SearchResultsView: View {
    @State private var viewModel: SearchResultsViewModel
    @State private var showsFilters = false
    @Environment(LanguageManager.self) private var l10n
    @Environment(CatalogStore.self) private var catalog
    @Environment(ExploreReferenceStore.self) private var references
    @Environment(FavoriteStore.self) private var favorites
    @Environment(ListingChangeCenter.self) private var listingChanges
    @Environment(AppToasts.self) private var toasts
    @Environment(SessionManager.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let topID = "results.top"
    private static let chipsStartID = "results.chips.start"

    init(query: ExploreQuery, api: any ListingsApi) {
        _viewModel = State(initialValue: SearchResultsViewModel(query: query, api: api))
    }

    var body: some View {
        ShellScreen {
            header
        } content: {
            results
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
        .task {
            // `-TaleedDebugSearchFilters YES` opens the filters sheet (screenshots).
            if UserDefaults.standard.bool(forKey: "TaleedDebugSearchFilters") { showsFilters = true }
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
        .sheet(isPresented: $showsFilters) {
            FilterSheetView(query: viewModel.query, startsExpanded: dynamicTypeSize.isAccessibilitySize) {
                viewModel.apply($0)
            }
            .appLanguage(l10n.language)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            TaleedTopAppBar(
                title: l10n.string(.appExploreResultsTitle),
                onBack: { dismiss() },
                // The wireframe's trust shield, as on Checkout: opens the buyer-protection page.
                actions: [router.buyerProtectionAction(accessibilityLabel: l10n.string(.appA11yBuyerProtection))]
            )
            VStack(spacing: TaleedSpacing.s16) {
                searchRow
                if !viewModel.query.activeFilters.isEmpty {
                    filterChips
                }
            }
            .padding(.top, TaleedSpacing.s16)
        }
        .background(TaleedColor.surfacePrimary)
    }

    /// The keywords (Search keeps the filters) and the 44 pt filter button with its count badge.
    private var searchRow: some View {
        @Bindable var viewModel = viewModel
        let count = viewModel.query.activeFilters.count
        return HStack(spacing: TaleedSpacing.s12) {
            TaleedTextField(text: $viewModel.searchText, placeholder: l10n.string(.appExploreSearchPlaceholder),
                            leadingIcon: .magnifyingGlass, maxLength: ListingSearchParameters.maxTextLength)
                .submitLabel(.search)
                .onSubmit { viewModel.submitSearch() }
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("results.search")
            TaleedIconOnlyButton(icon: .slidersHorizontal, accessibilityLabel: l10n.string(.filtersTitle),
                                 kind: .tertiary, size: .medium, boxSize: TaleedSize.inputHeight) {
                showsFilters = true
            }
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    // Centred on the button's corner, as in Figma (18 pt, 8 pt past the edges).
                    CountBadge(count: count, accessibilityLabel: "", size: .small)
                        // SwiftUI mirrors the offset in right-to-left.
                        .offset(x: 8, y: -8)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityValue(count > 0 ? "\(count)" : "")
            .accessibilityIdentifier("results.filters")
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
    }

    /// One removable chip per active filter, in the brand tone as in Figma.
    private var filterChips: some View {
        let chips = viewModel.query.activeFilters.map { (filter: $0, title: chipLabel($0)) }
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TaleedSpacing.s8) {
                    // The start margin (with the spacing), which the row scrolls back to.
                    Color.clear.frame(width: TaleedLayout.screenMargin - TaleedSpacing.s8, height: 1).id(Self.chipsStartID)
                    ForEach(chips, id: \.filter) { chip in
                        let filter = chip.filter
                        RemovableFilterChip(title: chip.title, tone: .brand) {
                            withAnimation { viewModel.remove(filter) }
                        }
                        .accessibilityIdentifier("results.chip.\(filter.rawValue)")
                    }
                    Color.clear.frame(width: TaleedLayout.screenMargin - TaleedSpacing.s8, height: 1)
                }
                .padding(.vertical, 2)
            }
            // The row starts at its first chip, also in right-to-left, where a row pushed on the stack
            // otherwise opens on its end; again when a label changes (the catalog's names arrive late).
            .onAppear { proxy.scrollTo(Self.chipsStartID) }
            .onChange(of: chips.map(\.title)) { _, _ in proxy.scrollTo(Self.chipsStartID) }
        }
    }

    private func chipLabel(_ filter: ExploreFilter) -> String {
        ExploreLabels.chip(filter, query: viewModel.query,
                           context: .init(catalog: catalog.catalog, brands: references.brands.value ?? [],
                                          language: l10n.language, text: { l10n.string($0) }))
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        let list = viewModel.results
        if list.hasLoaded {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: TaleedSpacing.s12) {
                        let listings = listingChanges.cards(list.items.filter { !favorites.removedIds.contains($0.id) })
                        // No count over the empty state, which already says there is nothing.
                        Group {
                            if listings.isEmpty {
                                Color.clear.frame(height: 0)
                            } else {
                                countRow
                            }
                        }
                        .id(Self.topID)
                        .onAppear { Task { await viewModel.topAppeared() } }
                        .onDisappear { viewModel.topDisappeared() }
                        if listings.isEmpty {
                            emptyState
                                .padding(.horizontal, TaleedLayout.screenMargin)
                                .padding(.top, TaleedSpacing.s24)
                        } else {
                            ListingGrid(listings: listings)
                            PaginationFooter(list: list)
                        }
                    }
                    .padding(.top, TaleedSpacing.s16)
                    .padding(.bottom, TaleedSpacing.s24)
                }
                .refreshable { await list.refresh() }
                .scrollDismissesKeyboard(.immediately)
                .accessibilityIdentifier("results.scroll")
                .onChange(of: ObjectIdentifier(list)) { _, _ in proxy.scrollTo(Self.topID, anchor: .top) }
            }
        } else if let error = list.error {
            ErrorStateView(error: error, retry: { Task { await list.reload() } }, onBack: { dismiss() })
        } else {
            ScrollView {
                SkeletonProductGrid(count: TaleedMotion.skeletonMaxPlaceholders)
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .padding(.top, TaleedSpacing.s16)
            }
            .scrollDisabled(true)
        }
    }

    /// "126 articles" over the grid (kept from the build: Figma draws no count).
    private var countRow: some View {
        let count = l10n.format(.filtersResults, viewModel.results.total ?? 0)
        return Text(count)
            .taleedFont(PatternStyles.body13)
            .foregroundStyle(TaleedColor.textBody)
            .padding(.horizontal, TaleedLayout.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(countAccessibilityLabel(count: count))
            .accessibilityIdentifier("results.count")
    }

    /// "Résultats pour « zara », 1 article" (the website's heading and count) for VoiceOver.
    private func countAccessibilityLabel(count: String) -> String {
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
