import Foundation
import Observation

/// The favorites screen (screens.md §2 G6, §7 G6): `GET /me/favorites`, most recently favorited
/// first, 24 cards a page, de-duplicated by id.
///
/// The list follows the shared hearts (`FavoriteStore`): a card un-hearted here or on another screen
/// leaves at once (the website keeps it until the next reload, the app does not, §7 G6), and a listing
/// hearted elsewhere joins at the top, where the API puts it. A `404` on a heart drops the card.
///
/// The screen owns it in `@State`, so going back to it keeps the cards and the scroll position.
@MainActor
@Observable
final class FavoritesViewModel {
    let list: PagedList<ListingSummary>

    @ObservationIgnored private let store: FavoriteStore
    @ObservationIgnored private let pager: FavoritesPager
    /// The store's changes up to this one are in `list`.
    @ObservationIgnored private var appliedSeq: Int
    /// When the app went to the background; nil while in the foreground.
    @ObservationIgnored private var backgroundSince: ContinuousClock.Instant?

    /// A shorter absence keeps the cards as they are (as Home and search).
    static let foregroundReloadAfter: Duration = .seconds(60)

    init(api: FavoritesListApi, store: FavoriteStore) {
        self.store = store
        let pager = FavoritesPager(api: api, store: store)
        self.pager = pager
        list = PagedList { cursor throws(ApiError) in try await pager.fetch(cursor: cursor) }
        pager.list = list
        appliedSeq = store.changeSeq
    }

    // MARK: What the screen shows

    /// The cards on screen: without the ones un-hearted while their request runs, nor listings found gone.
    var cards: [ListingSummary] {
        list.items.filter(isShown)
    }

    /// "3 articles": the API's count, without the cards that already left the screen.
    var resultCount: Int {
        let hidden = list.items.count - cards.count
        return max(0, (list.total ?? list.items.count) - hidden)
    }

    /// Loaded, and no card to show: the empty state.
    var isEmpty: Bool {
        list.hasLoaded && cards.isEmpty
    }

    private func isShown(_ listing: ListingSummary) -> Bool {
        !store.removedIds.contains(listing.id) && store.state(for: listing).isFavorited
    }

    // MARK: Loading

    /// The first page, unless one is on screen or loading (the screen's `.task`).
    func load() async {
        guard !list.hasLoaded, !list.isLoadingFirstPage else { return }
        let base = store.changeSeq
        if await list.reload() { didLoadFirstPage(base: base) }
    }

    /// Pull-to-refresh: the first page again, the cards staying on screen until it arrives.
    func refresh() async {
        let base = store.changeSeq
        if await list.refresh() { didLoadFirstPage(base: base) }
    }

    /// The error state's Retry.
    func retry() async {
        let base = store.changeSeq
        if await list.reload() { didLoadFirstPage(base: base) }
    }

    /// A fresh first page includes what settled before it was asked for; later changes go on top of it.
    private func didLoadFirstPage(base: Int) {
        appliedSeq = base
        syncWithStore()
    }

    // MARK: Following the hearts

    /// Applies the hearts that settled since the last call: a listing favorited elsewhere goes to the top
    /// (the API's order: most recent first), one un-hearted leaves. Call it when `changeSeq` moves.
    func syncWithStore() {
        guard list.hasLoaded else { return }
        for change in store.changes(after: appliedSeq) {
            switch change.kind {
            case let .added(listing): list.prepend(listing)
            case let .removed(id): list.remove(id: id)
            }
        }
        appliedSeq = store.changeSeq
    }

    /// The heart of a card on this screen: removes the favorite (the card leaves at once). Returns
    /// whether it was removed, so that the screen offers to undo it.
    @discardableResult
    func heartTapped(_ listing: ListingSummary) -> Bool {
        let removing = store.state(for: listing).isFavorited
        store.setFavorite(listing, to: !removing)
        return removing
    }

    /// "Annuler" on the toast: the favorite again. Once the API confirms it, the card is back at the top
    /// (or where it was, when the removal had not gone through yet).
    func undoRemoval(of listing: ListingSummary) {
        store.setFavorite(listing, to: true)
    }

    // MARK: Foreground

    func wentToBackground(at instant: ContinuousClock.Instant = .now) {
        backgroundSince = instant
    }

    /// Back after a while (screens.md §0.6): the cards reload quietly (favorites added on the website or
    /// another device).
    func returnedToForeground(at instant: ContinuousClock.Instant = .now) async {
        guard let since = backgroundSince else { return }
        backgroundSince = nil
        guard instant - since >= Self.foregroundReloadAfter, list.hasLoaded, !list.isRefreshing else { return }
        pager.isAutomatic = true
        defer { pager.isAutomatic = false }
        await refresh()
    }
}

/// The pages of `GET /me/favorites`. Its cursors are positions in the list, so a favorite added or
/// removed after the first page moves the cards that follow: the next page would skip some or repeat
/// some. After such a change the next page starts again from the top and goes on until it finds cards
/// that are not on screen yet (`PagedList` drops the repeats).
@MainActor
final class FavoritesPager {
    weak var list: PagedList<ListingSummary>?
    /// Marks the requests of a quiet reload, which pause while the API asks to wait (`429`).
    var isAutomatic = false

    private let api: FavoritesListApi
    private let store: FavoriteStore
    /// `changeSeq` when the pages on screen were asked for: a later change moved the cursors.
    private var pagesSeq: Int
    /// Bounds the walk from the top (24 cards a page).
    static let maxPagesPerWalk = 100

    init(api: FavoritesListApi, store: FavoriteStore) {
        self.api = api
        self.store = store
        pagesSeq = store.changeSeq
    }

    func fetch(cursor: String?) async throws(ApiError) -> Page<ListingSummary> {
        #if DEBUG
        if let page = try debugPage(cursor: cursor) { return page }
        #endif
        let seq = store.changeSeq
        guard let cursor else {
            pagesSeq = seq
            return try await api.listFavorites(cursor: nil, automatic: isAutomatic)
        }
        guard seq != pagesSeq else {
            return try await api.listFavorites(cursor: cursor, automatic: isAutomatic)
        }
        // The cursor no longer points after the cards on screen: from the top, to the first page with a
        // card the screen does not have.
        let known = Set(list?.items.map(\.id) ?? [])
        var next: String?
        for _ in 0..<Self.maxPagesPerWalk {
            let page = try await api.listFavorites(cursor: next, automatic: isAutomatic)
            if page.nextCursor == nil || page.items.contains(where: { !known.contains($0.id) }) {
                pagesSeq = seq
                return page
            }
            next = page.nextCursor
        }
        return try await api.listFavorites(cursor: next, automatic: isAutomatic)
    }

    #if DEBUG
    private var failedOnce = false

    /// `-TaleedDebugFavorites offline` fails the first request (then works); `empty` answers no favorites.
    private func debugPage(cursor: String?) throws(ApiError) -> Page<ListingSummary>? {
        switch UserDefaults.standard.string(forKey: "TaleedDebugFavorites") {
        case "offline" where !failedOnce:
            failedOnce = true
            throw .network
        case "empty":
            return Page(items: [], nextCursor: nil, total: 0)
        default:
            return nil
        }
    }
    #endif
}
