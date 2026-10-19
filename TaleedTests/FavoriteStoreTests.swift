import Foundation
@testable import Taleed
import Testing

/// A `FavoritesApi` whose answers the test releases one at a time.
@MainActor
final class FakeFavoritesApi: FavoritesApi {
    /// Answers in order; a missing answer echoes the request with `count`.
    var results: [Result<Taleed.FavoriteState, Taleed.ApiError>] = []
    var count = 10
    private(set) var sent: [(id: String, favorited: Bool)] = []
    /// When set, each call waits until `release()`.
    var holds = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func setFavorite(listingId: String, favorited: Bool) async throws(Taleed.ApiError) -> Taleed.FavoriteState {
        sent.append((listingId, favorited))
        if holds { await withCheckedContinuation { waiting.append($0) } }
        if !results.isEmpty { return try results.removeFirst().get() }
        return Taleed.FavoriteState(isFavorited: favorited, count: count)
    }

    func release() {
        let next = waiting
        waiting = []
        next.forEach { $0.resume() }
    }

    var isWaiting: Bool { !waiting.isEmpty }
}

private func notFound() -> Taleed.ApiError {
    .from(status: 404, body: Data(#"{"error":{"code":"not_found","message":"x"}}"#.utf8))
}

/// Lets other tasks run until `condition` holds (or a while has passed).
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() { await Task.yield() }
}

// MARK: - Favorites

@MainActor
struct FavoriteStoreTests {
    private let api = FakeFavoritesApi()

    @Test func aTapFillsTheHeartAtOnceThenTakesTheApisCount() async {
        let store = FavoriteStore(api: api)
        let listing = ListingSummary.fixture(favoritesCount: 3)
        api.holds = true
        let task = store.toggle(listing)
        #expect(store.state(for: listing) == Taleed.FavoriteState(isFavorited: true, count: 4))
        await waitUntil { api.isWaiting }
        api.count = 7
        api.release()
        await task?.value
        #expect(store.state(for: listing) == Taleed.FavoriteState(isFavorited: true, count: 7))
        #expect(api.sent.map(\.favorited) == [true])
    }

    @Test func aFailurePutsTheHeartBackAndReportsIt() async {
        let store = FavoriteStore(api: api)
        var failures: [Taleed.ApiError] = []
        store.onFailure = { failures.append($0) }
        let listing = ListingSummary.fixture(isFavorited: true, favoritesCount: 5)
        api.results = [.failure(.network)]
        await store.toggle(listing)?.value
        #expect(store.state(for: listing) == Taleed.FavoriteState(isFavorited: true, count: 5))
        #expect(failures == [.network])
        #expect(store.removedIds.isEmpty)
    }

    @Test func aRemovedListingLeavesTheLists() async {
        let store = FavoriteStore(api: api)
        var removed: [String] = []
        store.onRemoved = { removed.append($0) }
        api.results = [.failure(notFound())]
        await store.toggle(.fixture(id: "gone"))?.value
        #expect(store.removedIds == ["gone"])
        #expect(removed == ["gone"])
    }

    @Test func tapsDuringARequestSendTheLastWish() async {
        let store = FavoriteStore(api: api)
        let listing = ListingSummary.fixture(favoritesCount: 3)
        api.holds = true
        let task = store.toggle(listing)
        await waitUntil { api.isWaiting }
        // Two more taps while the first request runs: back to not favorited, then favorited again.
        #expect(store.toggle(listing) == nil)
        #expect(store.toggle(listing) == nil)
        #expect(store.state(for: listing).isFavorited)
        api.holds = false
        api.release()
        await task?.value
        // The API already says favorited, which is the last wish: nothing more to send.
        #expect(api.sent.map(\.favorited) == [true])
        #expect(store.state(for: listing).isFavorited)
    }

    @Test func anUndoDuringARequestIsSentAfterIt() async {
        let store = FavoriteStore(api: api)
        let listing = ListingSummary.fixture(favoritesCount: 3)
        api.holds = true
        let task = store.toggle(listing)
        await waitUntil { api.isWaiting }
        store.toggle(listing)
        #expect(!store.state(for: listing).isFavorited)
        api.holds = false
        api.release()
        await task?.value
        #expect(api.sent.map(\.favorited) == [true, false])
        #expect(!store.state(for: listing).isFavorited)
    }

    @Test func afterSigningInTheHeartAddsEvenWhenAlreadyShownSaved() async {
        let store = FavoriteStore(api: api)
        let listing = ListingSummary.fixture(isFavorited: true, favoritesCount: 4)
        await store.setFavorite(listing, to: true)?.value
        #expect(api.sent.map(\.favorited) == [true])
    }

    @Test func aCardAskedForAfterTheAnswerShowsTheServersState() async {
        var clock = ContinuousClock.now
        let store = FavoriteStore(api: api, now: { clock })
        let before = ListingSummary.fixture(favoritesCount: 3, asOf: clock)
        // The answer arrives a second after the list.
        clock = clock.advanced(by: .seconds(1))
        api.count = 4
        await store.toggle(before)?.value
        // The cards asked for before the answer keep the member's change.
        #expect(store.state(for: before) == Taleed.FavoriteState(isFavorited: true, count: 4))
        // Pull-to-refresh after it: the server's state wins (another member's heart, or the website's).
        clock = clock.advanced(by: .seconds(1))
        let fresh = ListingSummary.fixture(isFavorited: false, favoritesCount: 9, asOf: clock)
        #expect(store.state(for: fresh) == Taleed.FavoriteState(isFavorited: false, count: 9))
        // A tap on the fresh card starts from the server's state.
        clock = clock.advanced(by: .seconds(1))
        api.count = 10
        await store.toggle(fresh)?.value
        #expect(api.sent.map(\.favorited) == [true, true])
        #expect(store.state(for: fresh) == Taleed.FavoriteState(isFavorited: true, count: 10))
    }

    @Test func aRunningRequestWinsOverEveryCard() async {
        let store = FavoriteStore(api: api)
        api.holds = true
        let task = store.toggle(.fixture(favoritesCount: 3))
        await waitUntil { api.isWaiting }
        // A list loaded while the request runs may not have the change yet.
        let during = ListingSummary.fixture(favoritesCount: 3, asOf: .now)
        #expect(store.state(for: during) == Taleed.FavoriteState(isFavorited: true, count: 4))
        api.release()
        await task?.value
    }

    @Test func aFailureAfterARefreshGoesBackToTheServersState() async {
        let store = FavoriteStore(api: api)
        api.results = [.success(Taleed.FavoriteState(isFavorited: true, count: 4))]
        await store.toggle(.fixture(favoritesCount: 3))?.value
        // The website removed it meanwhile: the refreshed card says so; a failed tap goes back to that.
        let fresh = ListingSummary.fixture(isFavorited: false, favoritesCount: 7, asOf: .now)
        api.results = [.failure(.network)]
        await store.toggle(fresh)?.value
        #expect(store.state(for: fresh) == Taleed.FavoriteState(isFavorited: false, count: 7))
    }

    @Test func anotherMemberStartsFromTheListsAgain() async {
        let store = FavoriteStore(api: api)
        let listing = ListingSummary.fixture()
        await store.toggle(listing)?.value
        #expect(store.state(for: listing).isFavorited)
        store.sessionDidChange()
        #expect(!store.state(for: listing).isFavorited)
    }
}
