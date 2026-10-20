import SwiftUI

/// My listings (screens.md §2 G8 and §7 G8; Figma: the product list row and the confirmation modal;
/// the website has no such page): back and "Mes annonces", the design-system tabs En vente, Masqué,
/// Réservé, Vendu with their counts, then the member's listings as list rows. A row opens the listing;
/// its menu offers the seller's actions its status allows (Edit, Hide or "Remettre en vente", Delete
/// after the Figma confirmation). Opened from Profile and the member's own profile, signed in only.
///
/// States per tab: loading, the error (offline included) with Retry, the tab's empty state,
/// pull-to-refresh, the pagination footer, a quiet reload after a while in the background.
struct MyListingsView: View {
    @State private var model: MyListingsViewModel
    /// The row waiting for the delete confirmation.
    @State private var pendingDelete: ListingSummary?
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(AppToasts.self) private var toasts
    @Environment(FavoriteStore.self) private var favorites
    @Environment(ListingChangeCenter.self) private var listingChanges
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(dependencies: MyListingsDependencies, changesSeq: Int) {
        _model = State(initialValue: MyListingsViewModel(api: dependencies.listings, owner: dependencies.owner,
                                                         changesSeq: changesSeq))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.appProfileMyListings), onBack: { dismiss() })
        } content: {
            VStack(spacing: 0) {
                TaleedTabs(titles: MyListingsTab.allCases.map(tabTitle), selection: tabSelection,
                           horizontalInset: TaleedLayout.screenMargin)
                    .accessibilityIdentifier("myListings.tabs")
                MyListingsTabContent(model: model, tab: model.selectedTab, handlers: handlers)
                    // A fresh scroll position per tab.
                    .id(model.selectedTab)
            }
        }
        .task { await model.load() }
        // Edited, hidden, deleted or published on another screen.
        .onChange(of: listingChanges.seq) { _, _ in Task { await model.sync(with: listingChanges) } }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: model.wentToBackground()
            case .active: Task { await model.returnedToForeground() }
            default: break
            }
        }
        .taleedConfirmation(isPresented: pendingDelete != nil) {
            ConfirmationModalCard(title: l10n.string(.appListingDeleteTitle), message: l10n.string(.appListingDeleteBody),
                                  confirmTitle: l10n.string(.commonDelete),
                                  onConfirm: confirmDelete,
                                  onCancel: { pendingDelete = nil })
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(get: { model.selectedTab.rawValue }, set: { index in
            guard let tab = MyListingsTab(rawValue: index), tab != model.selectedTab else { return }
            Task { await model.select(tab) }
        })
    }

    /// "En vente (4)": the website's status labels, with the count once known.
    private func tabTitle(_ tab: MyListingsTab) -> String {
        let title = l10n.string(MyListingsText.tabKey(tab))
        guard let count = model.count(tab) else { return title }
        return l10n.format(.appMyListingsTabCount, title, count)
    }

    // MARK: Actions

    private var handlers: MyListingRow.Handlers {
        MyListingRow.Handlers(
            open: { router.push(.listing(id: $0.id)) },
            edit: { router.push(.editListing(id: $0.id)) },
            visibility: setVisibility,
            delete: { pendingDelete = $0 }
        )
    }

    private func setVisibility(_ listing: ListingSummary, _ visibility: ListingDetailActions.Visibility) {
        Task {
            let outcome = await model.setHidden(listing, hidden: visibility == .hide, changes: listingChanges)
            handle(outcome, listing: listing)
        }
    }

    private func confirmDelete() {
        guard let listing = pendingDelete else { return }
        pendingDelete = nil
        Task { handle(await model.delete(listing, changes: listingChanges), listing: listing) }
    }

    private func handle(_ outcome: MyListingsViewModel.Outcome, listing: ListingSummary) {
        switch outcome {
        case let .visibilityChanged(visibility):
            toasts.show(l10n.string(visibility == .hide ? .appListingHiddenToast : .appListingResumedToast))
        case .deleted:
            favorites.markRemoved(listing.id)
            toasts.show(l10n.string(.appListingDeletedToast))
        case let .failed(error):
            toasts.show(error: error)
        case .busy:
            break
        }
    }
}

/// The copy of My listings by tab.
enum MyListingsText {
    static func tabKey(_ tab: MyListingsTab) -> L10nKey {
        switch tab {
        case .active: .listingStatusActive
        case .hidden: .listingStatusHidden
        case .reserved: .listingStatusReserved
        case .sold: .listingStatusSold
        }
    }

    static func emptyTitleKey(_ tab: MyListingsTab) -> L10nKey {
        switch tab {
        case .active: .appMyListingsEmptyActiveTitle
        case .hidden: .appMyListingsEmptyHiddenTitle
        case .reserved: .appMyListingsEmptyReservedTitle
        case .sold: .appMyListingsEmptySoldTitle
        }
    }

    static func emptyBodyKey(_ tab: MyListingsTab) -> L10nKey {
        switch tab {
        case .active: .appMyListingsEmptyActiveBody
        case .hidden: .appMyListingsEmptyHiddenBody
        case .reserved: .appMyListingsEmptyReservedBody
        case .sold: .appMyListingsEmptySoldBody
        }
    }

    static func emptyIcon(_ tab: MyListingsTab) -> TaleedIcon {
        switch tab {
        case .active: .storefront
        case .hidden: .eye
        case .reserved: .clock
        case .sold: .money
        }
    }
}

/// One tab: its states, then the rows in the design-system list container.
private struct MyListingsTabContent: View {
    let model: MyListingsViewModel
    let tab: MyListingsTab
    let handlers: MyListingRow.Handlers
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(AppToasts.self) private var toasts

    var body: some View {
        let list = model.list(tab)
        Group {
            if list.hasLoaded {
                ScrollView {
                    if list.items.isEmpty {
                        emptyState
                            .padding(.top, TaleedSpacing.s48)
                            .padding(.horizontal, TaleedLayout.screenMargin)
                    } else {
                        LazyVStack(spacing: TaleedSpacing.s8) {
                            ForEach(list.items) { listing in
                                MyListingRow(listing: listing, actions: model.actions(for: listing),
                                             isBusy: model.isRunning(listing.id), handlers: handlers)
                            }
                            PaginationFooter(list: list)
                        }
                        .padding(TaleedSpacing.s8)
                        .background(TaleedColor.surfaceGrouped,
                                    in: RoundedRectangle(cornerRadius: TaleedRadius.l, style: .continuous))
                        .padding(.horizontal, TaleedLayout.screenMargin)
                        .padding(.vertical, TaleedSpacing.s16)
                        .animation(.easeOut(duration: 0.2), value: list.items.map(\.id))
                    }
                }
                .refreshable { await model.refresh() }
                .accessibilityIdentifier("myListings.scroll")
            } else if let error = list.error {
                ErrorStateView(error: error) { Task { await list.reload() } }
            } else {
                MyListingsSkeleton()
            }
        }
        .onChange(of: list.refreshError) { _, error in
            if let error { toasts.show(error: error) }
        }
    }

    private var emptyState: some View {
        EmptyState(
            title: l10n.string(MyListingsText.emptyTitleKey(tab)),
            message: l10n.string(MyListingsText.emptyBodyKey(tab)),
            actionTitle: tab == .active ? l10n.string(.sellTitle) : nil,
            action: tab == .active ? { router.selectedTab = .sell } : nil,
            icon: MyListingsText.emptyIcon(tab)
        )
        .accessibilityIdentifier("myListings.empty")
    }
}

/// Rows of the list's shape while the first page loads (design-system §3.6: never more than six).
private struct MyListingsSkeleton: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ScrollView {
            VStack(spacing: TaleedSpacing.s8) {
                ForEach(0 ..< 4, id: \.self) { _ in
                    HStack(spacing: TaleedSize.productListRowGap) {
                        SkeletonBlock(width: TaleedSize.productListRowMedia, height: TaleedSize.productListRowMedia,
                                      radius: TaleedRadius.m)
                        VStack(alignment: .leading, spacing: 10) {
                            SkeletonBlock(width: 80, height: 14)
                            SkeletonBlock(height: 16)
                            SkeletonBlock(width: 110, height: 20, color: TaleedColor.surfaceSubtle)
                        }
                    }
                    .padding(TaleedSize.productListRowPadding)
                    .background(TaleedColor.surfacePrimary,
                                in: RoundedRectangle(cornerRadius: TaleedRadius.l, style: .continuous))
                }
            }
            .padding(TaleedSpacing.s8)
            .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.l, style: .continuous))
            .padding(.horizontal, TaleedLayout.screenMargin)
            .padding(.vertical, TaleedSpacing.s16)
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.string(.commonLoading))
    }
}
