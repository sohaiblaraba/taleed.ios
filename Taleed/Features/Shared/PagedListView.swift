import SwiftUI

/// Shows a `PagedList` with every state of the quality bar: loading, error with retry (offline
/// included), empty, the items, pull-to-refresh, and a footer that loads the next page as the member
/// reaches it (spinner, or "Retry" when it failed).
///
/// ```swift
/// PagedListView(list: viewModel.orders) { orders in
///     LazyVStack(spacing: 0) { ForEach(orders) { OrderRow(order: $0) } }
/// } empty: {
///     EmptyState(title: l10n.string(.ordersEmpty))
/// }
/// ```
///
/// The content goes in a `ScrollView`; pass a lazy stack or grid so rows load as they appear.
///
/// A screen that does more after a first page (the notifications mark it read) passes its own `load`,
/// `refresh` and `retry`; by default they are the list's.
struct PagedListView<Item: Identifiable & Sendable, Content: View, Empty: View>: View where Item.ID: Sendable {
    let list: PagedList<Item>
    /// The first load (`.task`). Default: `list.loadIfNeeded()`.
    var load: (() async -> Void)?
    /// Pull-to-refresh. Default: `list.refresh()`.
    var refresh: (() async -> Void)?
    /// The error state's Retry. Default: `list.reload()`.
    var retry: (() async -> Void)?
    /// Centres the empty state in the list's space, as the error state, instead of near the top.
    var centersEmpty = false
    /// The first load's placeholder (skeleton rows); the spinner with "Chargement…" by default.
    var placeholder: AnyView?
    @ViewBuilder let content: ([Item]) -> Content
    @ViewBuilder let empty: () -> Empty
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppToasts.self) private var toasts

    var body: some View {
        Group {
            if list.hasLoaded {
                ScrollView {
                    if list.items.isEmpty {
                        if centersEmpty {
                            empty()
                                .padding(TaleedSpacing.s24)
                                .frame(maxWidth: .infinity)
                                .containerRelativeFrame(.vertical)
                        } else {
                            empty()
                                .frame(maxWidth: .infinity)
                                .padding(.top, TaleedSpacing.s48)
                        }
                    } else {
                        content(list.items)
                        PaginationFooter(list: list)
                    }
                }
                .refreshable {
                    if let refresh { await refresh() } else { await list.refresh() }
                }
            } else if let error = list.error {
                ErrorStateView(error: error) {
                    Task {
                        if let retry { await retry() } else { await list.reload() }
                    }
                }
            } else if let placeholder {
                ScrollView { placeholder }
                    .scrollDisabled(true)
            } else {
                LoadingStateView()
            }
        }
        .task {
            if let load { await load() } else { await list.loadIfNeeded() }
        }
        .onChange(of: list.refreshError) { _, error in
            if let error { toasts.show(error: error) }
        }
    }
}

/// The end of a paged list: loads the next page when it appears; a spinner while it loads, "Retry"
/// when it failed, nothing on the last page.
struct PaginationFooter<Item: Identifiable & Sendable>: View where Item.ID: Sendable {
    let list: PagedList<Item>
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        Group {
            if list.loadMoreError != nil {
                VStack(spacing: TaleedSpacing.s8) {
                    // Android's paging footer: one fixed line, whatever the error.
                    Text(l10n.string(.appListLoadMoreFailed))
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(TaleedColor.textBody)
                        .multilineTextAlignment(.center)
                    TaleedButton(title: l10n.string(.commonRetry), kind: .tertiary, size: .medium) {
                        Task { await list.retry() }
                    }
                }
                .padding(TaleedSpacing.s16)
            } else if list.hasMore {
                ProgressView()
                    .tint(TaleedColor.brandPrimary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .accessibilityLabel(l10n.string(.commonLoading))
                    // Runs again when a page arrived and the footer is still in view (short pages).
                    .task(id: list.items.count) { await list.loadMore() }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
