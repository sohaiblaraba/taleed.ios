import Foundation
import Observation

/// My listings (screens.md §2 G8 and §7 G8; slice B, The member's listings): a tab per status
/// (`GET /me/listings?status=`), each a paged list de-duplicated by id, loaded when first shown. The
/// tab badges come from `counts`, which ignore the filter. Hidden listings appear only here.
///
/// The seller's actions on a row follow the status table (`ListingDetailActions.OwnerActions`). Their
/// result, and the changes made on other screens (`ListingChangeCenter`: the listing screen, the edit
/// form, publishing), move the rows between tabs and update the counts at once; a tab whose content
/// the app cannot know (a listing that joined it) loads again when shown.
@MainActor
@Observable
final class MyListingsViewModel {
    /// The answer of a row action, for the screen's toast.
    enum Outcome: Equatable {
        /// Hidden (`.hide`) or put back on sale (`.resume`).
        case visibilityChanged(ListingDetailActions.Visibility)
        case deleted
        /// It failed: show the message. The rows were reloaded when the error says the listing changed.
        case failed(ApiError)
        /// An action already runs on this listing.
        case busy
    }

    private(set) var selectedTab: MyListingsTab = .active
    /// Nil until a first page arrived.
    private(set) var counts: MyListingCounts?
    /// The listings with an action running, to show a spinner in place of their menu.
    private(set) var running: Set<String> = []
    let lists: [MyListingsTab: PagedList<ListingSummary>]

    /// Marks the changes this screen made, so that it skips them when they come back from the center.
    let changeSource = UUID()

    @ObservationIgnored private let owner: ListingOwnerApi
    @ObservationIgnored private let pager: MyListingsPager
    @ObservationIgnored private var stale: Set<MyListingsTab> = []
    @ObservationIgnored private var appliedSeq: Int
    @ObservationIgnored private var backgroundSince: ContinuousClock.Instant?

    /// A shorter absence keeps the rows as they are (as Home and Favorites).
    static let foregroundReloadAfter: Duration = .seconds(60)

    init(api: MyListingsApi, owner: ListingOwnerApi, changesSeq: Int = 0) {
        self.owner = owner
        let pager = MyListingsPager(api: api)
        self.pager = pager
        var lists: [MyListingsTab: PagedList<ListingSummary>] = [:]
        for tab in MyListingsTab.allCases {
            lists[tab] = PagedList { cursor throws(ApiError) in try await pager.fetch(tab.status, cursor: cursor) }
        }
        self.lists = lists
        appliedSeq = changesSeq
        pager.onCounts = { [weak self] counts in self?.counts = counts }
    }

    // MARK: What the screen shows

    var list: PagedList<ListingSummary> { list(selectedTab) }

    func list(_ tab: MyListingsTab) -> PagedList<ListingSummary> {
        // Every tab has its list (built in `init`).
        lists[tab] ?? PagedList { _ throws(ApiError) in Page(items: [], nextCursor: nil, total: 0) }
    }

    /// The tab's badge, once known.
    func count(_ tab: MyListingsTab) -> Int? { counts?[tab] }

    /// The seller's actions for a row, from its status (slice B, What the seller can do).
    func actions(for listing: ListingSummary) -> ListingDetailActions.OwnerActions {
        ListingDetailActions.OwnerActions(status: listing.status)
    }

    func isRunning(_ listingId: String) -> Bool { running.contains(listingId) }

    // MARK: Loading

    /// The selected tab's first page, unless it is on screen or loading (the screen's `.task`).
    func load() async {
        await show(selectedTab)
    }

    /// A tab tapped: its first page when it never loaded, again when its rows may be out of date.
    func select(_ tab: MyListingsTab) async {
        selectedTab = tab
        await show(tab)
    }

    private func show(_ tab: MyListingsTab) async {
        let list = list(tab)
        if stale.remove(tab) != nil, list.hasLoaded {
            await list.refresh()
        } else {
            await list.loadIfNeeded()
        }
    }

    /// Pull-to-refresh on the tab on screen (a failure keeps the rows and shows a toast).
    func refresh() async {
        stale.remove(selectedTab)
        await list.refresh()
    }

    func wentToBackground(at instant: ContinuousClock.Instant = .now) {
        backgroundSince = instant
    }

    /// Back after a while (screens.md §0.6): the tab on screen again, quietly; the others when shown.
    func returnedToForeground(at instant: ContinuousClock.Instant = .now) async {
        guard let since = backgroundSince else { return }
        backgroundSince = nil
        guard instant - since >= Self.foregroundReloadAfter else { return }
        stale = Set(MyListingsTab.allCases).subtracting([selectedTab])
        guard list.hasLoaded, !list.isRefreshing, !list.isLoadingFirstPage else { return }
        pager.isAutomatic = true
        defer { pager.isAutomatic = false }
        await list.refresh()
    }

    // MARK: Row actions

    /// "Masquer" or "Remettre en vente", without confirmation (as on the listing screen).
    func setHidden(_ listing: ListingSummary, hidden: Bool, changes: ListingChangeCenter?) async -> Outcome {
        guard begin(listing.id) else { return .busy }
        defer { end(listing.id) }
        do {
            let updated = try await owner.setListingHidden(id: listing.id, hidden: hidden)
            apply(.updated(updated), listingId: listing.id)
            changes?.post(.updated(updated), listingId: listing.id, source: changeSource)
            return .visibilityChanged(hidden ? .hide : .resume)
        } catch {
            return await failure(error, listingId: listing.id, changes: changes)
        }
    }

    /// "Supprimer" after the confirmation. A `404` means it is already gone: done (slice B, Deleting).
    func delete(_ listing: ListingSummary, changes: ListingChangeCenter?) async -> Outcome {
        guard begin(listing.id) else { return .busy }
        defer { end(listing.id) }
        do {
            try await owner.deleteListing(id: listing.id)
        } catch {
            guard error.isNotFound else { return await failure(error, listingId: listing.id, changes: changes) }
        }
        apply(.deleted, listingId: listing.id)
        changes?.post(.deleted, listingId: listing.id, source: changeSource)
        return .deleted
    }

    /// `listing_locked` (it just sold, an order is on its way): the message, and the rows again
    /// (screens.md §2 G8). `404`: the listing is gone (deleted elsewhere, taken down).
    private func failure(_ error: ApiError, listingId: String, changes: ListingChangeCenter?) async -> Outcome {
        switch error.code {
        case .notFound:
            apply(.deleted, listingId: listingId)
            changes?.post(.deleted, listingId: listingId, source: changeSource)
        case .listingLocked, .forbidden:
            changes?.post(.stale, listingId: listingId, source: changeSource)
            markEverythingStale()
            await list.refresh()
        default:
            break
        }
        return .failed(error)
    }

    private func begin(_ id: String) -> Bool {
        running.insert(id).inserted
    }

    private func end(_ id: String) {
        running.remove(id)
    }

    // MARK: Following the changes

    /// Applies the changes other screens made since the last call (call it when the center's `seq` moves).
    func sync(with center: ListingChangeCenter) async {
        guard let changes = center.changes(after: appliedSeq) else {
            appliedSeq = center.seq
            markEverythingStale()
            await refreshSelectedIfStale()
            return
        }
        appliedSeq = center.seq
        for change in changes where change.source != changeSource {
            apply(change.kind, listingId: change.listingId)
        }
        await refreshSelectedIfStale()
    }

    /// Moves a changed listing to its tab and updates the counts. A tab it joins is marked to load again
    /// (where it goes in the newest-first order is the server's to say).
    func apply(_ kind: ListingChangeCenter.Kind, listingId: String) {
        switch kind {
        case let .updated(detail):
            applyUpdate(detail.summary)
        case .deleted:
            applyDeletion(listingId)
        case .created:
            counts?.active += 1
            if list(.active).hasLoaded { stale.insert(.active) }
        case .stale:
            markEverythingStale()
        }
    }

    private func applyUpdate(_ summary: ListingSummary) {
        let previous = knownStatus(of: summary.id)
        let tab = MyListingsTab(status: summary.status)
        for candidate in MyListingsTab.allCases {
            let list = list(candidate)
            let isListed = list.items.contains { $0.id == summary.id }
            if candidate == tab {
                if isListed { list.update(summary) } else if list.hasLoaded { stale.insert(candidate) }
            } else if isListed {
                list.remove(id: summary.id)
            }
        }
        guard let previous else {
            // Not on screen: whether the counts change is unknown.
            markEverythingStale()
            return
        }
        if previous != summary.status { moveCount(from: previous, to: summary.status) }
    }

    private func applyDeletion(_ listingId: String) {
        let previous = knownStatus(of: listingId)
        for tab in MyListingsTab.allCases { list(tab).remove(id: listingId) }
        if let previous, let tab = MyListingsTab(status: previous) {
            counts?[tab] -= 1
        } else {
            markEverythingStale()
        }
    }

    /// The status of a listing shown in one of the tabs.
    private func knownStatus(of listingId: String) -> ListingStatus? {
        for tab in MyListingsTab.allCases {
            if let listing = list(tab).items.first(where: { $0.id == listingId }) { return listing.status }
        }
        return nil
    }

    private func moveCount(from old: ListingStatus, to new: ListingStatus) {
        if let tab = MyListingsTab(status: old) { counts?[tab] -= 1 }
        if let tab = MyListingsTab(status: new) { counts?[tab] += 1 }
    }

    private func markEverythingStale() {
        stale = Set(MyListingsTab.allCases.filter { list($0).hasLoaded })
        // The counts come with the next page loaded.
    }

    private func refreshSelectedIfStale() async {
        guard stale.contains(selectedTab), list.hasLoaded else { return }
        stale.remove(selectedTab)
        await list.refresh()
    }
}

/// The pages of `GET /me/listings`, one status at a time; hands the counts of every page to the screen.
/// Since API 1.5.5 its cursors point after the last row sent, so hiding or deleting a listing while the
/// member scrolls moves no page.
@MainActor
final class MyListingsPager {
    /// Marks the requests of a quiet reload, which pause while the API asks to wait (`429`).
    var isAutomatic = false
    var onCounts: ((MyListingCounts) -> Void)?

    private let api: MyListingsApi

    init(api: MyListingsApi) {
        self.api = api
    }

    func fetch(_ status: ListingStatus, cursor: String?) async throws(ApiError) -> Page<ListingSummary> {
        #if DEBUG
        try debugFailure()
        #endif
        let result = try await api.myListings(status: status, cursor: cursor, automatic: isAutomatic)
        onCounts?(result.counts)
        return result.page
    }

    #if DEBUG
    private var failedOnce = false

    /// `-TaleedDebugMyListings offline` fails the first request (then works).
    private func debugFailure() throws(ApiError) {
        guard UserDefaults.standard.string(forKey: "TaleedDebugMyListings") == "offline", !failedOnce else { return }
        failedOnce = true
        throw .network
    }
    #endif
}
