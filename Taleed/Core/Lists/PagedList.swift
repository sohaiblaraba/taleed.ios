import Foundation
import Observation

/// A list the API serves page by page (api-guide.md, Pagination): cursor pages, de-duplicated by `id`,
/// pull-to-refresh from the first page, and a restart when the API no longer accepts a cursor.
///
/// Own one per screen (in the view model, or `@State` in the screen) so that it survives navigation:
/// back to the list keeps its items and scroll position. Show it with `PagedListView`.
///
/// ```swift
/// let orders = PagedList<OrderSummary> { cursor in try await api.orders(cursor: cursor) }
/// ```
@MainActor
@Observable
final class PagedList<Item: Identifiable & Sendable> where Item.ID: Sendable {
    typealias Fetch = (_ cursor: String?) async throws(ApiError) -> Page<Item>

    /// The items so far, without duplicates, in the order the pages gave them.
    private(set) var items: [Item] = []
    /// The count across all pages, from the last page received.
    private(set) var total: Int?
    /// True once a first page arrived: before, the screen shows its loading or error state.
    private(set) var hasLoaded = false
    private(set) var isLoadingFirstPage = false
    private(set) var isRefreshing = false
    private(set) var isLoadingMore = false
    /// The first page failed and nothing is on screen: the full-screen error with "Retry".
    private(set) var error: ApiError?
    /// A later page failed: the footer shows "Retry".
    private(set) var loadMoreError: ApiError?
    /// A pull-to-refresh failed while items stay on screen: show it as a toast.
    private(set) var refreshError: ApiError?

    var hasMore: Bool { nextCursor != nil }
    var isEmpty: Bool { hasLoaded && items.isEmpty }

    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private var ids = Set<Item.ID>()
    /// Bumped by every first-page load, so that a slower answer for an older load is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let fetch: Fetch

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// Loads the first page unless one is on screen or loading (call it from `.task`).
    func loadIfNeeded() async {
        guard !hasLoaded, !isLoadingFirstPage else { return }
        await loadFirstPage(refreshing: false)
    }

    /// Loads the first page again, showing the loading state when nothing is on screen.
    func reload() async {
        await loadFirstPage(refreshing: false)
    }

    /// Pull-to-refresh: starts again without a cursor and keeps the items on screen until the first
    /// page arrives.
    func refresh() async {
        await loadFirstPage(refreshing: true)
    }

    /// The footer's retry, or the error state's.
    func retry() async {
        if hasLoaded, loadMoreError != nil {
            await loadMore()
        } else {
            await reload()
        }
    }

    /// Loads the next page, once at a time.
    func loadMore() async {
        guard hasLoaded, let cursor = nextCursor, !isLoadingMore, !isLoadingFirstPage, !isRefreshing else { return }
        let current = generation
        isLoadingMore = true
        loadMoreError = nil
        defer { if current == generation { isLoadingMore = false } }
        do {
            let page = try await fetch(cursor)
            guard current == generation else { return }
            append(page)
        } catch {
            guard current == generation else { return }
            if error.isInvalidCursor {
                // The cursor expired (or the list changed too much): start again from the top.
                isLoadingMore = false
                await loadFirstPage(refreshing: true)
            } else {
                loadMoreError = error
            }
        }
    }

    /// Loads the next page when `item` is among the last few on screen. Call it from each row's
    /// `.onAppear` when the list has no `PagedListView` footer.
    func loadMoreIfNeeded(after item: Item, threshold: Int = 5) async {
        guard let index = items.lastIndex(where: { $0.id == item.id }), index >= items.count - threshold else { return }
        await loadMore()
    }

    // MARK: Local changes (after an action the screen made)

    /// Replaces the item with the same id, such as after a favorite toggle.
    func update(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    /// Removes an item, such as a deleted listing.
    func remove(id: Item.ID) {
        guard ids.remove(id) != nil else { return }
        items.removeAll { $0.id == id }
        total = total.map { max(0, $0 - 1) }
    }

    /// Adds an item at the top, such as a message just sent. Ignored when it is already listed.
    func prepend(_ item: Item) {
        guard ids.insert(item.id).inserted else { return }
        items.insert(item, at: 0)
        total = total.map { $0 + 1 }
    }

    // MARK: Loading

    private func loadFirstPage(refreshing: Bool) async {
        generation += 1
        let current = generation
        if refreshing && hasLoaded { isRefreshing = true } else { isLoadingFirstPage = true }
        isLoadingMore = false
        error = nil
        loadMoreError = nil
        refreshError = nil
        defer {
            if current == generation {
                isRefreshing = false
                isLoadingFirstPage = false
            }
        }
        do {
            let page = try await fetch(nil)
            guard current == generation else { return }
            items = []
            ids = []
            nextCursor = nil
            append(page)
            hasLoaded = true
        } catch {
            guard current == generation else { return }
            if hasLoaded {
                refreshError = error
            } else {
                self.error = error
            }
        }
    }

    private func append(_ page: Page<Item>) {
        // A page can repeat items of an earlier one: the list moved while the member scrolled.
        let fresh = page.items.filter { ids.insert($0.id).inserted }
        items.append(contentsOf: fresh)
        nextCursor = page.nextCursor
        total = page.total
    }
}
