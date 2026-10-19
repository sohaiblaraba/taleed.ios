import SwiftUI

/// Favorites (screens.md §2 G6 and §7 G6; Figma: the Home product grid and the empty-state pattern):
/// back and "Favoris", the count ("3 articles", as on the website), then the two-column product grid,
/// page by page. Reserved and sold items keep their strips. Opened from Profile and by `/favorites`
/// links, signed in only (the router asks to sign in first).
///
/// Un-hearting a card removes it at once, with "Annuler" on the toast. States: skeleton cards while
/// the first page loads, the error (offline included) with Retry, the empty state with a way to
/// Explore, pull-to-refresh, the pagination footer, a quiet reload after a while in the background
/// (once the member is back at the top, and without a toast when it fails).
struct FavoritesView: View {
    @State private var model: FavoritesViewModel
    @Environment(LanguageManager.self) private var l10n
    @Environment(FavoriteStore.self) private var favorites
    @Environment(AppRouter.self) private var router
    @Environment(AppToasts.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(api: any FavoritesListApi, store: FavoriteStore) {
        _model = State(initialValue: FavoritesViewModel(api: api, store: store))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.navFavorites), onBack: { dismiss() })
        } content: {
            content
        }
        .task { await model.load() }
        // Hearts changed here or on another screen (even while this one is under it in the stack).
        .onChange(of: favorites.changeSeq) { _, _ in model.syncWithStore() }
        // Only a refresh the member asked for: the quiet foreground reload fails silently.
        .onChange(of: model.refreshFailure) { _, failure in
            if let failure { toasts.show(error: failure.error) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: model.wentToBackground()
            case .active: Task { await model.returnedToForeground() }
            default: break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let list = model.list
        if list.hasLoaded {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: TaleedSpacing.s12) {
                    if model.isEmpty {
                        emptyState
                            .padding(.top, TaleedSpacing.s48)
                            .onAppear { Task { await model.topAppeared() } }
                            .onDisappear { model.topDisappeared() }
                    } else {
                        countRow
                            // Whether the member is at the top: the quiet foreground reload waits for it.
                            .onAppear { Task { await model.topAppeared() } }
                            .onDisappear { model.topDisappeared() }
                        ListingGrid(listings: model.cards, onFavorite: heartTapped)
                        PaginationFooter(list: list)
                    }
                }
                .padding(.top, TaleedSpacing.s16)
                .padding(.bottom, TaleedSpacing.s24)
                .animation(.easeOut(duration: 0.2), value: model.cards.map(\.id))
            }
            .refreshable { await model.refresh() }
            .accessibilityIdentifier("favorites.scroll")
        } else if let error = list.error {
            ErrorStateView(error: error, retry: { Task { await model.retry() } }, onBack: { dismiss() })
        } else {
            ScrollView {
                SkeletonProductGrid(count: TaleedMotion.skeletonMaxPlaceholders)
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .padding(.top, TaleedSpacing.s16)
            }
            .scrollDisabled(true)
            .accessibilityLabel(l10n.string(.commonLoading))
        }
    }

    /// "3 articles" (the website's `filters.results` under the title).
    private var countRow: some View {
        Text(l10n.format(.filtersResults, model.resultCount))
            .taleedFont(TaleedFont.bodyRegular)
            .foregroundStyle(TaleedColor.textBody)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TaleedLayout.screenMargin)
            .accessibilityIdentifier("favorites.count")
    }

    /// No favorites yet (the website reuses the search sentence; §7 G6 asks for a dedicated one), with
    /// the website's "Parcourir les articles", which opens Explore.
    private var emptyState: some View {
        EmptyState(
            title: l10n.string(.appFavoritesEmptyTitle),
            message: l10n.string(.appFavoritesEmptyBody),
            actionTitle: l10n.string(.homeCtaBrowse),
            action: { router.selectedTab = .explore },
            icon: .heart
        )
        .accessibilityIdentifier("favorites.empty")
    }

    /// The card leaves at once; the toast offers to put it back.
    private func heartTapped(_ listing: ListingSummary) {
        guard model.heartTapped(listing) else { return }
        toasts.show(l10n.string(.appFavoritesRemoved), actionTitle: l10n.string(.commonCancel)) { [model] in
            model.undoRemoval(of: listing)
        }
    }
}
