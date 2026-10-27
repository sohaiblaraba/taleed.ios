import Foundation
import Observation
#if DEBUG
import OSLog
#endif

/// Home (screens.md §2 G2, Figma Home): the personalized feed of `GET /listings` without filters
/// (decision 5), the top-level categories of the catalog for the chips, and the hero banner.
///
/// It lives in `AppContainer`, so the feed and its scroll survive a language switch and the other tabs.
/// The feed reloads when the member or the language changes (personalized, labels in the language),
/// on pull-to-refresh, and when the app returns to the foreground after a while, as long as the member
/// is at the top of the feed (a reload replaces the pages they scrolled through).
@MainActor
@Observable
final class HomeViewModel {
    /// What the feed was loaded for: another member or language reloads it.
    struct FeedContext: Equatable, Sendable {
        var memberId: String?
        var language: AppLanguage
    }

    /// The feed: 24 cards a page, de-duplicated by id (the order can change between pages).
    let feed: PagedList<ListingSummary>
    /// The member closed the hero banner (kept on this device).
    private(set) var isHeroDismissed: Bool
    /// A refresh the member asked for failed while the cards stay on screen: the screen's toast.
    private(set) var refreshFailure: RefreshFailure?

    /// The top-level categories for the chips, in the app language; empty until the catalog arrived.
    var categories: [CatalogCategory] { catalog.catalog?.categories ?? [] }

    @ObservationIgnored private let catalog: CatalogStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let origin: RequestOrigin
    /// The member and language the screen shows now.
    @ObservationIgnored private var requestedContext: FeedContext?
    /// The member and language of the cards on screen: set only once a first page for them arrived, so
    /// that a load cancelled or failed for a new member is made again the next time Home shows.
    @ObservationIgnored private var loadedContext: FeedContext?
    /// When the app went to the background; nil while in the foreground.
    @ObservationIgnored private var backgroundSince: ContinuousClock.Instant?
    /// The app came back after `foregroundReloadAfter`: reload quietly once the member is at the top.
    @ObservationIgnored private var needsQuietReload = false
    /// The top of the feed (the search field) is on screen.
    @ObservationIgnored private var isShowingTop = false

    static let heroDismissedKey = "home.heroDismissed"
    /// A shorter absence (a glance at another app) keeps the feed as it is.
    static let foregroundReloadAfter: Duration = .seconds(60)

    init(api: ListingsApi, catalog: CatalogStore, defaults: UserDefaults = .standard) {
        self.catalog = catalog
        self.defaults = defaults
        isHeroDismissed = defaults.bool(forKey: Self.heroDismissedKey)
        let origin = RequestOrigin()
        self.origin = origin
        feed = PagedList { [api, origin] cursor throws(ApiError) in
            #if DEBUG
            if let page = try origin.debugPage() { return page }
            #endif
            let page = try await api.searchListings(ExploreQuery(), cursor: cursor, automatic: origin.isAutomatic)
            #if DEBUG
            Logger(subsystem: "app.taleed.mobile", category: "home").notice(
                "feed page cursor=\(cursor ?? "-", privacy: .public) items=\(page.items.count) total=\(page.total)")
            #endif
            return page
        }
    }

    /// The screen appeared, or the member or the language changed: loads the feed once, and again for
    /// another member (signed in, the cards mark their own items and hearts) or language.
    ///
    /// The cards count as loaded for a member only once their first page arrived: when the screen lets
    /// go of the request (a card tapped, the request cancelled) or it fails, the next call loads again.
    func show(for context: FeedContext) async {
        requestedContext = context
        guard loadedContext != context || !feed.hasLoaded else { return }
        await loadFeed(reportingFailure: true)
    }

    /// Pull-to-refresh: the feed from its first page, and the catalog for the chips.
    func refresh() async {
        async let catalogRefresh: Void = catalog.refresh()
        await loadFeed(reportingFailure: true)
        await catalogRefresh
    }

    /// The error state's "Retry".
    func retry() async {
        if catalog.catalog == nil { Task { await catalog.refresh() } }
        await loadFeed(reportingFailure: true)
    }

    // MARK: Foreground

    /// The app went to the background.
    func wentToBackground(at instant: ContinuousClock.Instant = .now) {
        backgroundSince = instant
    }

    /// Back from the background (screens.md §0.6, api-guide.md Reload): after `foregroundReloadAfter`,
    /// refreshes the feed quietly when the member is at the top of it, or later, when they scroll back
    /// to the top or come back to Home. Deeper in the feed the loaded pages and the scroll stay (the
    /// reload would replace them with the first page, in a new order). A failure keeps the cards on
    /// screen and shows no toast, since the member did not ask.
    func returnedToForeground(at instant: ContinuousClock.Instant = .now) async {
        guard let since = backgroundSince else { return }
        backgroundSince = nil
        guard instant - since >= Self.foregroundReloadAfter else { return }
        needsQuietReload = true
        await reloadQuietlyIfAtTop()
    }

    /// The top of the feed scrolled into view, or Home showed again.
    func topAppeared() async {
        isShowingTop = true
        await reloadQuietlyIfAtTop()
    }

    /// The member scrolled down past the top of the feed, or another screen covers Home.
    func topDisappeared() {
        isShowingTop = false
    }

    private func reloadQuietlyIfAtTop() async {
        guard needsQuietReload, isShowingTop, feed.hasLoaded else { return }
        needsQuietReload = false
        // A load already running brings fresh cards.
        guard !feed.isRefreshing, !feed.isLoadingFirstPage else { return }
        origin.isAutomatic = true
        defer { origin.isAutomatic = false }
        await loadFeed(reportingFailure: false)
    }

    // MARK: Loading

    /// The feed from its first page, for the member and language the screen shows now: keeps the cards
    /// on screen meanwhile when there are some.
    private func loadFeed(reportingFailure: Bool) async {
        let context = requestedContext
        let loaded = feed.hasLoaded ? await feed.refresh() : await feed.reload()
        if loaded {
            // Fresh cards for that member and language (a newer member's load, if any, runs on).
            if context == requestedContext { loadedContext = context }
            needsQuietReload = false
        } else if reportingFailure, let error = feed.refreshError {
            refreshFailure = RefreshFailure(error: error)
        }
    }

    func dismissHero() {
        isHeroDismissed = true
        defaults.set(true, forKey: Self.heroDismissedKey)
    }
}

/// A failed refresh, once per failure (the screen shows a toast when it changes).
struct RefreshFailure: Equatable, Sendable {
    let id = UUID()
    let error: ApiError
}

/// Marks the requests of an automatic refresh, which pause while the API asks to wait (`429`).
@MainActor
private final class RequestOrigin {
    var isAutomatic = false

    #if DEBUG
    private var failedOnce = false

    /// `-TaleedDebugHomeFeed` (screenshots of the feed's states).
    func debugPage() throws(ApiError) -> Page<ListingSummary>? {
        switch DebugLaunchOptions.homeFeed {
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
