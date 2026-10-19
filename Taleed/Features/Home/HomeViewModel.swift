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
/// on pull-to-refresh, and when the app returns to the foreground.
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
    @ObservationIgnored private var context: FeedContext?

    static let heroDismissedKey = "home.heroDismissed"

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
            Logger(subsystem: "app.taleed", category: "home").notice(
                "feed page cursor=\(cursor ?? "-", privacy: .public) items=\(page.items.count) total=\(page.total)")
            #endif
            return page
        }
    }

    /// The screen appeared, or the member or the language changed: loads the feed once, and again for
    /// another member (signed in, the feed leaves out their own items) or language.
    func show(for context: FeedContext) async {
        guard let previous = self.context else {
            self.context = context
            await feed.loadIfNeeded()
            return
        }
        guard previous != context else {
            await feed.loadIfNeeded()
            return
        }
        self.context = context
        if feed.hasLoaded {
            await feed.refresh()
            reportRefreshFailure()
        } else {
            await feed.reload()
        }
    }

    /// Pull-to-refresh: the feed from its first page, and the catalog for the chips.
    func refresh() async {
        async let catalogRefresh: Void = catalog.refresh()
        if feed.hasLoaded {
            await feed.refresh()
            reportRefreshFailure()
        } else {
            await feed.reload()
        }
        await catalogRefresh
    }

    /// The error state's "Retry".
    func retry() async {
        if catalog.catalog == nil { Task { await catalog.refresh() } }
        await feed.retry()
    }

    /// Back from the background (api-guide.md, Reload): refreshes the feed quietly. A failure keeps the
    /// cards on screen and shows no toast, since the member did not ask.
    func returnedToForeground() async {
        guard feed.hasLoaded, !feed.isRefreshing, !feed.isLoadingFirstPage else { return }
        origin.isAutomatic = true
        defer { origin.isAutomatic = false }
        await feed.refresh()
    }

    private func reportRefreshFailure() {
        if let error = feed.refreshError { refreshFailure = RefreshFailure(error: error) }
    }

    func dismissHero() {
        isHeroDismissed = true
        defaults.set(true, forKey: Self.heroDismissedKey)
    }

    /// "Browse near you" (decision 3): the search filtered on the member's wilaya when known; nil to
    /// open Explore without a filter (signed out, or no wilaya on the profile).
    static func nearbyQuery(for user: User?) -> ExploreQuery? {
        guard let wilaya = user?.wilayaId, wilaya > 0 else { return nil }
        return ExploreQuery(wilaya: wilaya)
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
