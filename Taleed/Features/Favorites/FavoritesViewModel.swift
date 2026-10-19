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
    /// A refresh the member asked for failed while the cards stay on screen: the screen's toast.
    private(set) var refreshFailure: RefreshFailure?

    @ObservationIgnored private let store: FavoriteStore
    @ObservationIgnored private let pager: FavoritesPager
    /// The store's changes up to this one are in `list`.
    @ObservationIgnored private var appliedSeq: Int
    /// When the app went to the background; nil while in the foreground.
    @ObservationIgnored private var backgroundSince: ContinuousClock.Instant?
    /// The app came back after `foregroundReloadAfter`: reload quietly once the member is at the top.
    @ObservationIgnored private var needsQuietReload = false
    /// The top of the list (the count, or the empty state) is on screen.
    @ObservationIgnored private var isShowingTop = false

    /// A shorter absence keeps the cards as they are (as Home and search).
    static let foregroundReloadAfter: Duration = .seconds(60)

    init(api: FavoritesListApi, store: FavoriteStore) {
        self.store = store
        let pager = FavoritesPager(api: api)
        self.pager = pager
        list = PagedList { cursor throws(ApiError) in try await pager.fetch(cursor: cursor) }
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

    /// Loaded, no card to show and none left to load: the empty state. While later pages remain (every
    /// card on screen un-hearted), the count and the footer stay, and the footer loads the next page.
    var isEmpty: Bool {
        list.hasLoaded && cards.isEmpty && !list.hasMore
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

    /// Pull-to-refresh: the first page again, the cards staying on screen until it arrives. A failure
    /// keeps them and shows a toast.
    func refresh() async {
        await refresh(reportingFailure: true)
    }

    private func refresh(reportingFailure: Bool) async {
        let base = store.changeSeq
        if await list.refresh() {
            didLoadFirstPage(base: base)
            needsQuietReload = false
        } else if reportingFailure, let error = list.refreshError {
            refreshFailure = RefreshFailure(error: error)
        }
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

    /// Back from the background (screens.md §0.6, as Home): after `foregroundReloadAfter`, the cards
    /// reload quietly (favorites added on the website or another device) when the member is at the top
    /// of the list, or later, when they scroll back to it or come back to this screen. Deeper in the list
    /// the loaded pages and the scroll stay (the reload would replace them with the first page). A
    /// failure keeps the cards on screen and shows no toast, since the member did not ask.
    func returnedToForeground(at instant: ContinuousClock.Instant = .now) async {
        guard let since = backgroundSince else { return }
        backgroundSince = nil
        guard instant - since >= Self.foregroundReloadAfter else { return }
        needsQuietReload = true
        await reloadQuietlyIfAtTop()
    }

    /// The top of the list scrolled into view, or the screen showed again.
    func topAppeared() async {
        isShowingTop = true
        await reloadQuietlyIfAtTop()
    }

    /// The member scrolled down past the top of the list, or another screen covers this one.
    func topDisappeared() {
        isShowingTop = false
    }

    private func reloadQuietlyIfAtTop() async {
        guard needsQuietReload, isShowingTop, list.hasLoaded else { return }
        needsQuietReload = false
        // A load already running brings fresh cards.
        guard !list.isRefreshing, !list.isLoadingFirstPage else { return }
        pager.isAutomatic = true
        defer { pager.isAutomatic = false }
        await refresh(reportingFailure: false)
    }
}

/// The pages of `GET /me/favorites`. Since API 1.5.5 its cursors point after the last card sent
/// (newest first, by when it was favorited), so a heart or un-heart made while the member scrolls moves
/// no page: the next page goes on from the cursor as received, and the cards hearted meanwhile are
/// added at the top by the screen.
@MainActor
final class FavoritesPager {
    /// Marks the requests of a quiet reload, which pause while the API asks to wait (`429`).
    var isAutomatic = false

    private let api: FavoritesListApi

    init(api: FavoritesListApi) {
        self.api = api
    }

    func fetch(cursor: String?) async throws(ApiError) -> Page<ListingSummary> {
        #if DEBUG
        if let page = try debugPage(cursor: cursor) { return page }
        #endif
        return try await api.listFavorites(cursor: cursor, automatic: isAutomatic)
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
