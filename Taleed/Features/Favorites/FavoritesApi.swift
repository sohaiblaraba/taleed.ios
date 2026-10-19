import SwiftUI
import TaleedAPI

/// `GET /me/favorites` (slice B, Favorites): the member's favorites as listing cards, most recently
/// favorited first, 24 a page. Reserved and sold items stay; items deleted, taken down or hidden by
/// their seller are left out by the API.
@MainActor
protocol FavoritesListApi: AnyObject {
    /// `automatic`: a refresh the member did not ask for (return to the foreground).
    func listFavorites(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<ListingSummary>
}

extension GeneratedTaleedApi: FavoritesListApi {
    func listFavorites(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<ListingSummary> {
        let asOf = ContinuousClock.now
        let page = try await caller.call(.read, automatic: automatic) {
            try await FavoritesAPI.listFavorites(cursor: cursor, apiConfiguration: $0)
        }
        return Page(items: page.items.map { ListingSummary($0, asOf: asOf) }, nextCursor: page.nextCursor, total: page.total)
    }
}

private struct FavoritesListApiKey: EnvironmentKey {
    static var defaultValue: (any FavoritesListApi)? { nil }
}

extension EnvironmentValues {
    /// Set once at the root (`AppRootView`).
    var favoritesListApi: (any FavoritesListApi)? {
        get { self[FavoritesListApiKey.self] }
        set { self[FavoritesListApiKey.self] = newValue }
    }
}
