import SwiftUI
#if DEBUG
import OSLog
#endif

/// Home (Figma Home 58:3131): brand app bar, the search field that opens Explore, the hero banner
/// "Browse near you", the category chips, then the personalized feed in a two-column grid, with the
/// trust strip after the first ten cards. Every state of the feed: skeleton cards while it loads, the
/// error (offline included) with Retry, the website's empty text, pull-to-refresh, and the next pages
/// as the member scrolls.
struct HomeView: View {
    let viewModel: HomeViewModel
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(SessionManager.self) private var session
    @Environment(FavoriteStore.self) private var favorites
    @Environment(AppToasts.self) private var toasts

    /// Cards before the trust strip (the wireframe shows ten, then the strip).
    static let cardsBeforeTrustStrip = 10
    private static let topID = "home.top"
    /// The chip row ends with 7 pt under its chips: 8 between the chips and the grid in all.
    private static let gridTop = TaleedSpacing.s8 - 7

    var body: some View {
        ShellScreen {
            ShellBrandAppBar(showsDivider: false)
        } content: {
            ScrollViewReader { proxy in
                ScrollView {
                    // Lazy, so that the pagination footer only appears (and loads the next page) when
                    // the member reaches it.
                    LazyVStack(spacing: 0) {
                        searchField
                            .padding(.horizontal, TaleedLayout.screenMargin)
                            .padding(.top, TaleedSpacing.s8)
                            .id(Self.topID)
                            // Whether the member is at the top: the quiet foreground reload waits for it.
                            .onAppear { Task { await viewModel.topAppeared() } }
                            .onDisappear { viewModel.topDisappeared() }
                        if !viewModel.isHeroDismissed {
                            hero
                        }
                        categoryChips { withAnimation { proxy.scrollTo(Self.topID, anchor: .top) } }
                            // The chip row has 7 pt above and below its 30 pt chips: 16 above, 8 below in all.
                            .padding(.top, TaleedSpacing.s16 - 7)
                        feedSection
                    }
                    .padding(.bottom, TaleedSpacing.s24)
                }
                .refreshable { await viewModel.refresh() }
            }
        }
        .task(id: feedContext) { await viewModel.show(for: feedContext) }
        #if DEBUG
        .onChange(of: viewModel.feed.items.count) { _, count in
            let unique = Set(viewModel.feed.items.map(\.id)).count
            Logger(subsystem: "app.taleed", category: "home").notice("feed shows \(count) cards, \(unique) unique")
        }
        #endif
        .onChange(of: viewModel.refreshFailure) { _, failure in
            if let failure { toasts.show(error: failure.error) }
        }
    }

    private var feedContext: HomeViewModel.FeedContext {
        HomeViewModel.FeedContext(memberId: session.user?.id, language: l10n.language)
    }

    // MARK: Header

    /// Looks like the search field but is a button that opens Explore, so VoiceOver announces a button
    /// with a hint, not a search field.
    private var searchField: some View {
        Button { router.selectedTab = .explore } label: {
            HStack(spacing: TaleedSize.inputGap) {
                TaleedIconView(.magnifyingGlass, size: TaleedSize.inputIconLeading, color: TaleedColor.textSecondary)
                Text(l10n.string(.homeSearchHint))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, TaleedSize.inputPaddingX)
            .frame(minHeight: TaleedSize.inputHeight)
            .taleedCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n.string(.homeSearchHint))
        .accessibilityHint(l10n.string(.a11yOpensExplore))
    }

    /// The banner sits 16 under the search field; its cut-out rises 24 above it, over that gap.
    private var hero: some View {
        HeroBanner(
            title: l10n.string(.homeHeroTitle),
            ctaLabel: l10n.string(.homeHeroCta),
            onCta: browseNearYou,
            onDismiss: { withAnimation { viewModel.dismissHero() } }
        )
        .padding(.horizontal, TaleedLayout.screenMargin)
        .padding(.top, TaleedSpacing.s16 - TaleedSize.heroBannerForegroundOverflowTop)
        .transition(.opacity)
    }

    /// "All" (this feed) then the top-level categories of the catalog; a category opens its results
    /// (screens.md §2 G2), "All" goes back to the top of the feed.
    private func categoryChips(onAll: @escaping () -> Void) -> some View {
        ChipRow {
            CategoryChip(title: l10n.string(.navAllItems), isSelected: true, action: onAll)
            ForEach(viewModel.categories) { category in
                CategoryChip(title: category.name, icon: HomeCategoryIcon.icon(forSlug: category.slug),
                             iconSize: category.slug == "kids" ? 18 : TaleedSize.chipIconSize) {
                    router.push(.search(ExploreQuery(category: category.slug)))
                }
            }
        }
    }

    // MARK: Feed

    @ViewBuilder
    private var feedSection: some View {
        let feed = viewModel.feed
        if feed.hasLoaded {
            let listings = feed.items.filter { !favorites.removedIds.contains($0.id) }
            if listings.isEmpty {
                EmptyState(title: l10n.string(.homeEmptyFeed), actionTitle: l10n.string(.homeCtaSell),
                           action: { router.selectedTab = .sell }, icon: .storefront)
                    .padding(.top, TaleedSpacing.s32)
            } else {
                // Siblings in the screen's lazy stack: the grid after the strip and the footer load
                // only when scrolled to.
                ListingGrid(listings: Array(listings.prefix(Self.cardsBeforeTrustStrip)))
                    .padding(.top, Self.gridTop)
                TrustStrip()
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .padding(.top, TaleedSpacing.s24)
                if listings.count > Self.cardsBeforeTrustStrip {
                    ListingGrid(listings: Array(listings.dropFirst(Self.cardsBeforeTrustStrip)))
                        .padding(.top, TaleedSpacing.s24)
                }
                PaginationFooter(list: feed)
            }
        } else if let error = feed.error {
            ErrorStateView(error: error) { Task { await viewModel.retry() } }
                .frame(height: 320)
        } else {
            SkeletonProductGrid(count: TaleedMotion.skeletonMaxPlaceholders)
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.top, Self.gridTop)
        }
    }

    // MARK: Actions

    /// Decision 3: the results for the member's wilaya; Explore without a filter otherwise.
    private func browseNearYou() {
        if let query = HomeViewModel.nearbyQuery(for: session.user) {
            router.push(.search(query))
        } else {
            router.selectedTab = .explore
        }
    }
}

/// The icons of the Home category chips (Figma Home #5), by top-level category slug. Other
/// categories show their name only.
enum HomeCategoryIcon {
    static func icon(forSlug slug: String) -> TaleedIcon? {
        switch slug {
        case "kids": .baby
        case "women": .dress
        case "men": .tShirt
        case "home": .houseLine
        case "electronics": .washingMachine
        default: nil
        }
    }
}
