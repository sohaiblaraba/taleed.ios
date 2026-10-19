import Foundation
import Observation

/// The orders the member changed on the order screen (cancelled, confirmed, disputed, reviewed), so
/// that the list below shows the new status at once. Owned by `AppContainer`.
@MainActor
@Observable
final class OrderChangeCenter {
    struct Change: Equatable, Sendable {
        let status: OrderState
        let statusLabel: String
    }

    /// Moves with every change.
    private(set) var seq = 0
    /// Each changed order as its last change left it.
    private(set) var latest: [String: Change] = [:]

    func post(_ order: OrderDetailInfo) {
        seq += 1
        latest[order.id] = Change(status: order.status, statusLabel: order.statusLabel)
    }
}

/// The orders list (screens.md §2 G12 screen 1, slice D "The orders list"): Purchases and Sales
/// (`GET /orders?role=BUYER|SELLER`), each a paged list de-duplicated by id, loaded when first shown.
/// The tab counters come from `counts`, which ignore the filter.
@MainActor
@Observable
final class OrdersListViewModel {
    private(set) var selectedTab: OrdersTab
    /// Nil until a first page arrived.
    private(set) var counts: OrderTabCounts?
    let lists: [OrdersTab: PagedList<OrderRow>]

    @ObservationIgnored private let pager: OrdersPager
    @ObservationIgnored private var appliedSeq = 0
    @ObservationIgnored private var backgroundSince: ContinuousClock.Instant?
    @ObservationIgnored private var stale: Set<OrdersTab> = []

    /// A shorter absence keeps the rows as they are (as My listings).
    static let foregroundReloadAfter: Duration = .seconds(60)

    init(api: OrdersApi, initialTab: OrdersTab = .purchases) {
        selectedTab = initialTab
        let pager = OrdersPager(api: api)
        self.pager = pager
        var lists: [OrdersTab: PagedList<OrderRow>] = [:]
        for tab in OrdersTab.allCases {
            lists[tab] = PagedList { cursor throws(ApiError) in try await pager.fetch(tab, cursor: cursor) }
        }
        self.lists = lists
        pager.onCounts = { [weak self] counts in self?.counts = counts }
    }

    func list(_ tab: OrdersTab) -> PagedList<OrderRow> {
        // Every tab has its list (built in `init`).
        lists[tab] ?? PagedList { _ throws(ApiError) in Page(items: [], nextCursor: nil, total: 0) }
    }

    var list: PagedList<OrderRow> { list(selectedTab) }

    /// The tab's counter, once known.
    func count(_ tab: OrdersTab) -> Int? { counts?[tab] }

    // MARK: Loading

    func load() async {
        await show(selectedTab)
    }

    func select(_ tab: OrdersTab) async {
        selectedTab = tab
        await show(tab)
    }

    private func show(_ tab: OrdersTab) async {
        let list = list(tab)
        if stale.remove(tab) != nil, list.hasLoaded {
            await list.refresh()
        } else {
            await list.loadIfNeeded()
        }
    }

    /// Pull-to-refresh on the tab on screen.
    func refresh() async {
        stale.remove(selectedTab)
        await list.refresh()
    }

    func wentToBackground(at instant: ContinuousClock.Instant = .now) {
        backgroundSince = instant
    }

    /// Back after a while (screens.md §0.6): the tab on screen again, quietly; the other when shown.
    func returnedToForeground(at instant: ContinuousClock.Instant = .now) async {
        guard let since = backgroundSince else { return }
        backgroundSince = nil
        guard instant - since >= Self.foregroundReloadAfter else { return }
        stale = Set(OrdersTab.allCases).subtracting([selectedTab])
        guard list.hasLoaded, !list.isRefreshing, !list.isLoadingFirstPage else { return }
        pager.isAutomatic = true
        defer { pager.isAutomatic = false }
        await list.refresh()
    }

    // MARK: Changes from the order screen

    /// Shows the new status of the orders changed on their screen since the last call.
    func apply(_ changes: OrderChangeCenter) {
        guard changes.seq != appliedSeq else { return }
        appliedSeq = changes.seq
        for list in lists.values {
            for row in list.items {
                guard let change = changes.latest[row.id],
                      change.status != row.status || change.statusLabel != row.statusLabel else { continue }
                var updated = row
                updated.status = change.status
                updated.statusLabel = change.statusLabel
                list.update(updated)
            }
        }
    }
}

/// Fetches the pages of both tabs and hands over the counters each page carries.
@MainActor
private final class OrdersPager {
    let api: OrdersApi
    var onCounts: ((OrderTabCounts) -> Void)?
    /// True while a refresh the member did not ask for runs.
    var isAutomatic = false

    init(api: OrdersApi) {
        self.api = api
    }

    func fetch(_ tab: OrdersTab, cursor: String?) async throws(ApiError) -> Page<OrderRow> {
        #if DEBUG
        if let page = try debugPage() { return page }
        #endif
        let page = try await api.orders(side: tab.side, cursor: cursor, automatic: isAutomatic)
        onCounts?(page.counts)
        return page.page
    }
}

#if DEBUG
private extension OrdersPager {
    /// `-TaleedDebugOrders offline` fails the first page once; `empty` answers no orders (screenshots).
    func debugPage() throws(ApiError) -> Page<OrderRow>? {
        switch UserDefaults.standard.string(forKey: "TaleedDebugOrders") {
        case "offline" where !Self.debugFailed:
            Self.debugFailed = true
            throw .network
        case "empty":
            onCounts?(OrderTabCounts(purchases: 0, sales: 0))
            return Page(items: [], nextCursor: nil, total: 0)
        default:
            return nil
        }
    }

    static var debugFailed = false
}
#endif
