import Foundation
import Observation
#if DEBUG
import OSLog
#endif

/// Search results (screens.md §2 G3 screen 2): `GET /listings` with the query's keywords, filters and
/// sort, 24 cards a page, de-duplicated by id.
///
/// The screen owns it in `@State`, so going back to the results keeps the query, the cards and the
/// scroll position (design-system §5.5 rule 2). Every change of the query starts a new list from the
/// first page; the screen scrolls back to the top.
@MainActor
@Observable
final class SearchResultsViewModel {
    /// The keywords, filters and sort on screen.
    private(set) var query: ExploreQuery
    /// The search field, sent on "Search" (the filters stay).
    var searchText: String
    /// The results of `query`. A new list for each query, so its states (loading, error, empty) are
    /// the new query's.
    private(set) var results: PagedList<ListingSummary>

    @ObservationIgnored private let api: ListingsApi
    @ObservationIgnored private let origin = SearchRequestOrigin()
    /// When the app went to the background; nil while in the foreground.
    @ObservationIgnored private var backgroundSince: ContinuousClock.Instant?
    /// The top of the results (the count row) is on screen.
    @ObservationIgnored private var isShowingTop = true
    @ObservationIgnored private var needsQuietReload = false

    /// A shorter absence keeps the results as they are (as Home).
    static let foregroundReloadAfter: Duration = .seconds(60)

    init(query: ExploreQuery, api: ListingsApi) {
        self.query = query
        self.api = api
        searchText = query.text ?? ""
        results = Self.makeList(query: query, api: api, origin: origin)
    }

    // MARK: Changing the query

    /// Shows the results of `newQuery`. Nothing changes when the API would answer the same (the same
    /// parameters, the default sort spelled out or not).
    func apply(_ newQuery: ExploreQuery) {
        let changed = Self.request(newQuery) != Self.request(query)
        query = newQuery
        searchText = newQuery.text ?? ""
        guard changed else { return }
        needsQuietReload = false
        results = Self.makeList(query: newQuery, api: api, origin: origin)
    }

    /// "Search" on the keyboard: the typed keywords with the filters on screen.
    func submitSearch() {
        apply(query.searching(searchText))
    }

    /// The × of a filter chip.
    func remove(_ filter: ExploreFilter) {
        apply(query.removing(filter))
    }

    /// The empty state's "Clear filters": every filter and the sort go, the keywords stay (as the
    /// website's "Tout effacer").
    func clearFilters() {
        apply(query.clearingFilters)
    }

    /// Another member signed in or out: the results again from the first page, since a member's own
    /// items leave the recommended order and the hearts are theirs.
    func memberDidChange() {
        needsQuietReload = false
        results = Self.makeList(query: query, api: api, origin: origin)
    }

    // MARK: Foreground

    func wentToBackground(at instant: ContinuousClock.Instant = .now) {
        backgroundSince = instant
    }

    /// Back after a while (screens.md §0.6): the results reload quietly once the member is at the top,
    /// so that pages they scrolled through are not replaced under their thumb.
    func returnedToForeground(at instant: ContinuousClock.Instant = .now) async {
        guard let since = backgroundSince else { return }
        backgroundSince = nil
        guard instant - since >= Self.foregroundReloadAfter else { return }
        needsQuietReload = true
        await reloadQuietlyIfAtTop()
    }

    func topAppeared() async {
        isShowingTop = true
        await reloadQuietlyIfAtTop()
    }

    func topDisappeared() {
        isShowingTop = false
    }

    private func reloadQuietlyIfAtTop() async {
        guard needsQuietReload, isShowingTop, results.hasLoaded, !results.isRefreshing, !results.isLoadingFirstPage else { return }
        needsQuietReload = false
        origin.isAutomatic = true
        defer { origin.isAutomatic = false }
        await results.refresh()
    }

    // MARK: Loading

    private static func request(_ query: ExploreQuery) -> ListingSearchParameters {
        var parameters = ListingSearchParameters(query)
        parameters.sort = query.effectiveSort
        return parameters
    }

    private static func makeList(query: ExploreQuery, api: ListingsApi, origin: SearchRequestOrigin) -> PagedList<ListingSummary> {
        PagedList { [api, origin] cursor throws(ApiError) in
            #if DEBUG
            if let page = try origin.debugPage() { return page }
            #endif
            let page = try await api.searchListings(query, cursor: cursor, automatic: origin.isAutomatic)
            #if DEBUG
            Logger(subsystem: "app.taleed.mobile", category: "search").notice(
                "results page cursor=\(cursor ?? "-", privacy: .public) items=\(page.items.count) total=\(page.total)")
            #endif
            return page
        }
    }
}

/// Marks the requests of a quiet reload, which pause while the API asks to wait (`429`).
@MainActor
private final class SearchRequestOrigin {
    var isAutomatic = false

    #if DEBUG
    private var failedOnce = false

    /// `-TaleedDebugSearchResults offline` fails the first request (screenshots of the error state).
    func debugPage() throws(ApiError) -> Page<ListingSummary>? {
        if UserDefaults.standard.string(forKey: "TaleedDebugSearchResults") == "offline", !failedOnce {
            failedOnce = true
            throw .network
        }
        return nil
    }
    #endif
}
