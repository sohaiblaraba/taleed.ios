import Foundation
import Observation

/// The notifications screen's list (screens.md §2 G15 and §7 G15, slice E "Notifications"): newest
/// first, 30 a page, de-duplicated by id.
///
/// Once a first page shows (the first load, pull-to-refresh, a quiet reload on return to the foreground
/// or when something new arrives), everything up to its first row is marked read
/// (`POST /notifications/read`) and the badges take the answer. The rows keep their unread bar until
/// the next load, as on the website, so the member sees what was new.
@MainActor
@Observable
final class NotificationsViewModel {
    let list: PagedList<NotificationRow>

    @ObservationIgnored private let api: NotificationsApi
    @ObservationIgnored private let pager: NotificationsPager
    /// The badges after a mark-read (`SessionManager.updateUnreadCounts`).
    @ObservationIgnored private let onCounts: (UnreadCounts) -> Void
    /// A `404` on mark-read reloads the list once; a second one in a row is left alone.
    @ObservationIgnored private var reloadedAfterNotFound = false

    init(api: NotificationsApi, onCounts: @escaping (UnreadCounts) -> Void) {
        self.api = api
        self.onCounts = onCounts
        let pager = NotificationsPager(api: api)
        self.pager = pager
        list = PagedList { cursor throws(ApiError) in try await pager.fetch(cursor: cursor) }
    }

    /// The first load (from `.task`).
    func loadIfNeeded() async {
        guard !list.hasLoaded, !list.isLoadingFirstPage else { return }
        if await list.reload() { await firstPageDidShow() }
    }

    /// The full-screen error's Retry.
    func retry() async {
        if await list.reload() { await firstPageDidShow() }
    }

    /// Pull-to-refresh: the first page again, then marked read again.
    func refresh() async {
        if await list.refresh() { await firstPageDidShow() }
    }

    /// Back in the foreground, or something new arrived while the screen is open: the first page again,
    /// keeping the rows on screen, as requests that pause while the API asks to wait (`429`).
    func reloadQuietly() async {
        guard list.hasLoaded, !list.isRefreshing, !list.isLoadingFirstPage else {
            await loadIfNeeded()
            return
        }
        pager.isAutomatic = true
        defer { pager.isAutomatic = false }
        if await list.refresh() { await firstPageDidShow() }
    }

    /// The first page is empty but more pages follow (every row of it could not be written): the next
    /// pages until a row shows, then marked read with the first row shown. Also the Retry of that state.
    func loadPastEmptyPages() async {
        while list.items.isEmpty, list.hasMore, !Task.isCancelled {
            await list.loadMore()
            if list.loadMoreError != nil || !list.hasLoaded { return }
        }
        await markRead()
    }

    /// The empty first page's footer state: more pages may still hold rows.
    var isLoadingPastEmptyPages: Bool { list.hasLoaded && list.items.isEmpty && list.hasMore }

    private func firstPageDidShow() async {
        if list.items.isEmpty, list.hasMore {
            await loadPastEmptyPages()
        } else {
            await markRead()
        }
    }

    /// `POST /notifications/read` with the first row shown. Quiet: without an answer the badge stays and
    /// the next load tries again.
    private func markRead() async {
        guard let newest = list.items.first else { return }
        // Its own task: the pull-to-refresh gesture cancels the refresh's task as soon as the first page
        // is on screen, and leaving the screen must not undo "opened = read" either.
        let api = api
        let result = await Task { () -> Result<UnreadCounts, ApiError> in
            do throws(ApiError) {
                return .success(try await api.markNotificationsRead(upTo: newest.id))
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case let .success(counts):
            reloadedAfterNotFound = false
            onCounts(counts)
        case let .failure(error):
            // The row is no longer the member's: load the list again (slice E), once.
            guard error.isNotFound, !reloadedAfterNotFound else { return }
            reloadedAfterNotFound = true
            if await list.refresh() { await firstPageDidShow() }
        }
    }
}

/// Fetches the pages for `PagedList`.
@MainActor
final class NotificationsPager {
    /// Marks the requests of a quiet reload, which pause while the API asks to wait (`429`).
    var isAutomatic = false
    private let api: NotificationsApi

    init(api: NotificationsApi) {
        self.api = api
    }

    func fetch(cursor: String?) async throws(ApiError) -> Page<NotificationRow> {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "TaleedDebugNotifications") {
        // `-TaleedDebugNotifications offline` fails the first request (then works).
        case "offline" where !failedOnce:
            failedOnce = true
            throw .network
        // `empty`: an empty list.
        case "empty":
            return Page(items: [], nextCursor: nil, total: 0)
        // `hidden`: a first page without rows that still has a next page (the real first page).
        case "hidden" where cursor == nil:
            return Page(items: [], nextCursor: Self.debugHiddenCursor, total: 0)
        case "hidden" where cursor == Self.debugHiddenCursor:
            return try await api.notifications(cursor: nil, automatic: isAutomatic)
        default:
            break
        }
        #endif
        return try await api.notifications(cursor: cursor, automatic: isAutomatic)
    }

    #if DEBUG
    private var failedOnce = false
    private static let debugHiddenCursor = "debug-hidden"
    #endif
}
