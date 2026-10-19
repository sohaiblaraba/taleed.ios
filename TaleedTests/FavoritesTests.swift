import Foundation
@testable import Taleed
import Testing

/// A server holding one member's favorites (most recent first), with the API's position cursors.
@MainActor
final class FakeFavoritesServer: FavoritesApi, FavoritesListApi {
    var ids: [String]
    var pageSize: Int
    /// The cursors asked for, in order (nil: the first page).
    private(set) var listCursors: [String?] = []
    private(set) var automaticRequests = 0
    /// Answers of `setFavorite` in order; when empty the server applies the request.
    var setResults: [Result<Taleed.FavoriteState, Taleed.ApiError>] = []
    /// Fails the next list request.
    var listFailure: Taleed.ApiError?
    /// When set, `setFavorite` waits until `release()`.
    var holds = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(ids: [String], pageSize: Int = 3) {
        self.ids = ids
        self.pageSize = pageSize
    }

    func listFavorites(cursor: String?, automatic: Bool) async throws(Taleed.ApiError) -> Page<ListingSummary> {
        listCursors.append(cursor)
        if automatic { automaticRequests += 1 }
        if let failure = listFailure {
            listFailure = nil
            throw failure
        }
        let offset = cursor.flatMap(Int.init) ?? 0
        let slice = ids.dropFirst(offset).prefix(pageSize)
        let next = offset + pageSize < ids.count ? String(offset + pageSize) : nil
        return Page(items: slice.map { ListingSummary.fixture(id: $0, isFavorited: true, asOf: .now) },
                    nextCursor: next, total: ids.count)
    }

    func setFavorite(listingId: String, favorited: Bool) async throws(Taleed.ApiError) -> Taleed.FavoriteState {
        if holds { await withCheckedContinuation { waiting.append($0) } }
        if !setResults.isEmpty { return try setResults.removeFirst().get() }
        ids.removeAll { $0 == listingId }
        if favorited { ids.insert(listingId, at: 0) }
        return Taleed.FavoriteState(isFavorited: favorited, count: favorited ? 1 : 0)
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

@MainActor
struct FavoritesViewModelTests {
    private struct Setup {
        let server: FakeFavoritesServer
        let store: FavoriteStore
        let model: FavoritesViewModel
    }

    private func make(_ ids: [String], pageSize: Int = 3) -> Setup {
        let server = FakeFavoritesServer(ids: ids, pageSize: pageSize)
        let store = FavoriteStore(api: server)
        return Setup(server: server, store: store, model: FavoritesViewModel(api: server, store: store))
    }

    private func ids(_ model: FavoritesViewModel) -> [String] { model.cards.map(\.id) }

    @Test func theFirstPageShowsTheMostRecentFavoritesAndTheApisCount() async {
        let setup = make(["a", "b", "c", "d", "e"])
        let model = setup.model
        await model.load()
        #expect(ids(model) == ["a", "b", "c"])
        #expect(model.resultCount == 5)
        #expect(!model.isEmpty)
    }

    @Test func noFavoritesShowsTheEmptyState() async {
        let setup = make([])
        let model = setup.model
        #expect(!model.isEmpty)  // Not before the answer: the skeleton shows.
        await model.load()
        #expect(model.isEmpty)
        #expect(model.resultCount < 1)
    }

    @Test func aFailedFirstPageShowsTheErrorThenRetryLoads() async {
        let setup = make(["a"])
        let server = setup.server
        let model = setup.model
        server.listFailure = .network
        await model.load()
        #expect(model.list.error == .network)
        #expect(!model.list.hasLoaded)
        await model.retry()
        #expect(model.list.error == nil)
        #expect(ids(model) == ["a"])
    }

    @Test func unHeartingACardRemovesItAtOnce() async {
        let setup = make(["a", "b", "c"])
        let server = setup.server
        let store = setup.store
        let model = setup.model
        await model.load()
        server.holds = true
        model.heartTapped(model.cards[1])
        // Before the API answers.
        #expect(ids(model) == ["a", "c"])
        #expect(model.resultCount == 2)
        await waitUntil { server.isWaiting }
        server.holds = false
        server.release()
        await waitUntil { store.changeSeq == 1 }
        model.syncWithStore()
        #expect(model.list.items.map(\.id) == ["a", "c"])
        #expect(model.resultCount == 2)
        #expect(server.ids == ["a", "c"])
    }

    @Test func removingTheLastCardShowsTheEmptyState() async {
        let setup = make(["a"])
        let store = setup.store
        let model = setup.model
        await model.load()
        model.heartTapped(model.cards[0])
        #expect(model.isEmpty)
        await waitUntil { store.changeSeq == 1 }
        model.syncWithStore()
        #expect(model.isEmpty)
        #expect(model.resultCount < 1)
    }

    @Test func aFailedRemovalPutsTheCardBack() async {
        let setup = make(["a", "b"])
        let server = setup.server
        let store = setup.store
        let model = setup.model
        var failures: [Taleed.ApiError] = []
        store.onFailure = { failures.append($0) }
        await model.load()
        server.setResults = [.failure(.network)]
        await store.setFavorite(model.cards[0], to: false)?.value
        model.syncWithStore()
        #expect(ids(model) == ["a", "b"])
        #expect(model.resultCount == 2)
        #expect(failures == [.network])
    }

    @Test func aListingGoneOnTheHeartLeavesTheList() async {
        let setup = make(["a", "b"])
        let server = setup.server
        let store = setup.store
        let model = setup.model
        await model.load()
        server.setResults = [.failure(notFound())]
        await store.setFavorite(model.cards[0], to: false)?.value
        model.syncWithStore()
        #expect(ids(model) == ["b"])
        #expect(model.resultCount == 1)
    }

    @Test func aListingFoundGoneElsewhereLeavesTheList() async {
        let setup = make(["a", "b"])
        let store = setup.store
        let model = setup.model
        await model.load()
        store.markRemoved("b")
        model.syncWithStore()
        #expect(ids(model) == ["a"])
        #expect(model.resultCount == 1)
    }

    @Test func aListingHeartedElsewhereJoinsAtTheTop() async {
        let setup = make(["a", "b"])
        let store = setup.store
        let model = setup.model
        await model.load()
        // Two hearts on Home: the last one is the most recent favorite.
        await store.toggle(.fixture(id: "x"))?.value
        await store.toggle(.fixture(id: "y"))?.value
        model.syncWithStore()
        #expect(ids(model) == ["y", "x", "a", "b"])
        #expect(model.resultCount == 4)
        // Un-hearted again on Home: it leaves.
        await store.toggle(model.cards[0])?.value
        model.syncWithStore()
        #expect(ids(model) == ["x", "a", "b"])
        #expect(model.resultCount == 3)
    }

    @Test func changesSettledBeforeTheFirstPageAreNotCountedTwice() async {
        let setup = make(["a", "b"])
        let store = setup.store
        let model = setup.model
        await store.toggle(.fixture(id: "x"))?.value
        await model.load()
        model.syncWithStore()
        #expect(ids(model) == ["x", "a", "b"])
        #expect(model.resultCount == 3)
    }

    @Test func undoAfterTheRemovalPutsTheCardBackAtTheTop() async {
        let setup = make(["a", "b", "c"])
        let server = setup.server
        let store = setup.store
        let model = setup.model
        await model.load()
        let card = model.cards[1]
        model.heartTapped(card)
        await waitUntil { store.changeSeq == 1 }
        model.syncWithStore()
        model.undoRemoval(of: card)
        await waitUntil { store.changeSeq == 2 }
        model.syncWithStore()
        // Where the API now has it: favorited again, so the most recent.
        #expect(ids(model) == ["b", "a", "c"])
        #expect(model.resultCount == 3)
        #expect(server.ids == ["b", "a", "c"])
    }

    @Test func undoBeforeTheRemovalWentThroughKeepsTheCardInPlace() async {
        let setup = make(["a", "b", "c"])
        let server = setup.server
        let store = setup.store
        let model = setup.model
        await model.load()
        let card = model.cards[1]
        server.holds = true
        model.heartTapped(card)
        await waitUntil { server.isWaiting }
        model.undoRemoval(of: card)
        #expect(ids(model) == ["a", "b", "c"])
        server.holds = false
        server.release()
        await waitUntil { store.changeSeq >= 1 }
        model.syncWithStore()
        #expect(ids(model).sorted() == ["a", "b", "c"])
        #expect(model.resultCount == 3)
    }

    @Test func withoutChangesTheNextPageUsesTheCursor() async {
        let setup = make(["a", "b", "c", "d", "e"])
        let server = setup.server
        let model = setup.model
        await model.load()
        await model.list.loadMore()
        #expect(server.listCursors == [nil, "3"])
        #expect(ids(model) == ["a", "b", "c", "d", "e"])
    }

    @Test func afterARemovalTheNextPageSkipsNoCard() async {
        let setup = make(["a", "b", "c", "d", "e", "f", "g"])
        let store = setup.store
        let model = setup.model
        await model.load()
        model.heartTapped(model.cards[0])
        await waitUntil { store.changeSeq == 1 }
        model.syncWithStore()
        // The API's position 3 is now "e": cursor "3" would skip "d".
        await model.list.loadMore()
        #expect(ids(model) == ["b", "c", "d"])
        await model.list.loadMore()
        await model.list.loadMore()
        #expect(ids(model) == ["b", "c", "d", "e", "f", "g"])
        #expect(Set(model.list.items.map(\.id)).count == model.list.items.count)
        #expect(model.resultCount == 6)
        #expect(!model.list.hasMore)
    }

    @Test func afterSeveralPagesARemovalWalksFromTheTopToTheMissingCards() async {
        let setup = make((1...10).map { "l\($0)" })
        let server = setup.server
        let store = setup.store
        let model = setup.model
        await model.load()
        await model.list.loadMore()
        #expect(model.list.items.count == 6)
        model.heartTapped(model.cards[0])
        model.heartTapped(model.cards[0])
        await waitUntil { store.changeSeq == 2 }
        model.syncWithStore()
        await model.list.loadMore()
        // From the top: the first page holds no new card, the next one does (l7, l8).
        #expect(server.listCursors == [nil, "3", nil, "3"])
        #expect(ids(model) == (3...8).map { "l\($0)" })
        // Then on from that page's cursor.
        await model.list.loadMore()
        #expect(server.listCursors.last == "6")
        #expect(ids(model) == (3...10).map { "l\($0)" })
        #expect(!model.list.hasMore)
        #expect(model.resultCount == 8)
    }

    @Test func pullToRefreshTakesTheServersList() async {
        let setup = make(["a", "b"])
        let server = setup.server
        let model = setup.model
        await model.load()
        server.ids = ["z", "a"]
        await model.refresh()
        #expect(ids(model) == ["z", "a"])
        #expect(model.resultCount == 2)
    }

    @Test func returningAfterAWhileReloadsQuietly() async {
        let setup = make(["a"])
        let server = setup.server
        let model = setup.model
        await model.load()
        let start = ContinuousClock.now
        server.ids = ["n", "a"]
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start.advanced(by: .seconds(30)))
        #expect(ids(model) == ["a"])
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start.advanced(by: .seconds(61)))
        #expect(ids(model) == ["n", "a"])
        #expect(server.automaticRequests == 1)
    }
}

@MainActor
struct FavoriteStoreChangeLogTests {
    @Test func confirmedChangesAreLoggedInOrder() async {
        let api = FakeFavoritesApi()
        let store = FavoriteStore(api: api)
        let listing = ListingSummary.fixture(id: "a")
        await store.toggle(listing)?.value
        await store.setFavorite(listing, to: false)?.value
        store.markRemoved("b")
        #expect(store.changeSeq == 3)
        #expect(store.changes.map(\.kind) == [.added(listing), .removed(id: "a"), .removed(id: "b")])
        #expect(store.changes(after: 1).map(\.seq) == [2, 3])
    }

    @Test func aFailureLogsNothing() async {
        let api = FakeFavoritesApi()
        api.results = [.failure(.network)]
        let store = FavoriteStore(api: api)
        await store.toggle(.fixture(id: "a"))?.value
        #expect(store.changeSeq == 0)
        #expect(store.changes.isEmpty)
    }

    @Test func tapsDuringARequestLogOnlyTheLastAnswer() async {
        let api = FakeFavoritesApi()
        let store = FavoriteStore(api: api)
        let listing = ListingSummary.fixture(id: "a")
        api.holds = true
        let task = store.toggle(listing)
        await waitUntil { api.isWaiting }
        store.toggle(listing)
        api.holds = false
        api.release()
        await task?.value
        #expect(store.changes.map(\.kind) == [.removed(id: "a")])
    }

    @Test func anotherMemberStartsAnEmptyLog() async {
        let api = FakeFavoritesApi()
        let store = FavoriteStore(api: api)
        await store.toggle(.fixture(id: "a"))?.value
        store.sessionDidChange()
        #expect(store.changes(after: 0).isEmpty)
        #expect(store.changeSeq == 1)
    }
}
