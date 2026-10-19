import Foundation
@testable import Taleed
import Testing

/// A server holding one member's favorites (most recent first), with the API's keyset cursors (1.5.5):
/// a cursor points after the last card sent, by when it was favorited.
@MainActor
final class FakeFavoritesServer: FavoritesApi, FavoritesListApi {
    /// The favorites, most recent first. Setting it favorites them in that order, as of now.
    var ids: [String] {
        get { favoritedAt.sorted { $0.value > $1.value }.map(\.key) }
        set {
            clock += newValue.count
            favoritedAt = Dictionary(uniqueKeysWithValues: newValue.enumerated().map { ($1, clock - $0) })
        }
    }
    var pageSize: Int
    /// When each listing was favorited (a counter).
    private var favoritedAt: [String: Int] = [:]
    private var clock = 0
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
        self.pageSize = pageSize
        self.ids = ids
    }

    func listFavorites(cursor: String?, automatic: Bool) async throws(Taleed.ApiError) -> Page<ListingSummary> {
        listCursors.append(cursor)
        if automatic { automaticRequests += 1 }
        if let failure = listFailure {
            listFailure = nil
            throw failure
        }
        let all = ids
        let after = cursor.flatMap(Int.init) ?? .max
        let rest = all.filter { favoritedAt[$0, default: 0] < after }
        let slice = Array(rest.prefix(pageSize))
        let next: String? = rest.count > pageSize ? slice.last.flatMap { favoritedAt[$0] }.map { String($0) } : nil
        return Page(items: slice.map { ListingSummary.fixture(id: $0, isFavorited: true, asOf: .now) },
                    nextCursor: next, total: all.count)
    }

    func setFavorite(listingId: String, favorited: Bool) async throws(Taleed.ApiError) -> Taleed.FavoriteState {
        if holds { await withCheckedContinuation { waiting.append($0) } }
        if !setResults.isEmpty { return try setResults.removeFirst().get() }
        favoritedAt[listingId] = nil
        if favorited {
            clock += 1
            favoritedAt[listingId] = clock
        }
        return Taleed.FavoriteState(isFavorited: favorited, count: favorited ? 1 : 0)
    }

    func release() {
        let next = waiting
        waiting = []
        next.forEach { $0.resume() }
    }

    var isWaiting: Bool { !waiting.isEmpty }
}

/// The favorites screen's pages (keyset cursors, API 1.5.5), its refreshes and its quiet reload.
@MainActor
struct FavoritesPagingTests {
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

    @Test func theNextPageUsesTheCursorAsReceived() async {
        let setup = make(["a", "b", "c", "d", "e"])
        let server = setup.server
        let model = setup.model
        await model.load()
        await model.list.loadMore()
        #expect(server.listCursors.count == 2)
        #expect(server.listCursors.last.flatMap { $0 } != nil)
        #expect(ids(model) == ["a", "b", "c", "d", "e"])
    }

    @Test func afterARemovalTheNextPageGoesOnFromItsCursor() async {
        let setup = make(["a", "b", "c", "d", "e", "f", "g"])
        let server = setup.server
        let store = setup.store
        let model = setup.model
        await model.load()
        model.heartTapped(model.cards[0])
        await waitUntil { store.changeSeq == 1 }
        model.syncWithStore()
        await model.list.loadMore()
        // No walk from the top: the cursor still points after "c".
        #expect(server.listCursors.filter { $0 == nil }.count == 1)
        #expect(ids(model) == ["b", "c", "d", "e", "f"])
        await model.list.loadMore()
        #expect(ids(model) == ["b", "c", "d", "e", "f", "g"])
        #expect(Set(model.list.items.map(\.id)).count == model.list.items.count)
        #expect(model.resultCount == 6)
        #expect(!model.list.hasMore)
    }

    @Test func aHeartElsewhereKeepsTheNextPageInPlace() async {
        let setup = make(["a", "b", "c", "d", "e", "f"])
        let server = setup.server
        let store = setup.store
        let model = setup.model
        await model.load()
        await store.toggle(.fixture(id: "x"))?.value
        model.syncWithStore()
        await model.list.loadMore()
        #expect(server.listCursors.filter { $0 == nil }.count == 1)
        #expect(ids(model) == ["x", "a", "b", "c", "d", "e", "f"])
        #expect(model.resultCount == 7)
        #expect(!model.list.hasMore)
    }

    @Test func everyCardOfThePageUnheartedKeepsLoadingInsteadOfTheEmptyState() async {
        let setup = make(["a", "b", "c", "d", "e"])
        let store = setup.store
        let model = setup.model
        await model.load()
        for card in model.cards { model.heartTapped(card) }
        // Before the API answers, and after.
        #expect(model.cards.isEmpty)
        #expect(!model.isEmpty)
        await waitUntil { store.changeSeq == 3 }
        model.syncWithStore()
        #expect(!model.isEmpty)
        #expect(model.list.hasMore)
        #expect(model.resultCount == 2)
        await model.list.loadMore()
        #expect(ids(model) == ["d", "e"])
        #expect(model.resultCount == 2)
        for card in model.cards { model.heartTapped(card) }
        #expect(model.isEmpty)
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

    @Test func aFailedPullToRefreshReportsIt() async {
        let setup = make(["a"])
        let server = setup.server
        let model = setup.model
        await model.load()
        server.listFailure = .network
        await model.refresh()
        #expect(model.refreshFailure?.error == .network)
        #expect(ids(model) == ["a"])
    }

    @Test func returningAfterAWhileReloadsQuietly() async {
        let setup = make(["a"])
        let server = setup.server
        let model = setup.model
        await model.load()
        await model.topAppeared()
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

    @Test func aFailedQuietReloadShowsNoToast() async {
        let setup = make(["a"])
        let server = setup.server
        let model = setup.model
        await model.load()
        await model.topAppeared()
        let start = ContinuousClock.now
        server.listFailure = .network
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start.advanced(by: .seconds(61)))
        #expect(server.automaticRequests == 1)
        #expect(model.refreshFailure == nil)
        #expect(ids(model) == ["a"])
    }

    @Test func deepInTheListTheQuietReloadWaitsForTheTop() async {
        let setup = make((1...7).map { "l\($0)" })
        let server = setup.server
        let model = setup.model
        await model.load()
        await model.topAppeared()
        await model.list.loadMore()
        await model.list.loadMore()
        model.topDisappeared()
        #expect(model.cards.count == 7)
        let start = ContinuousClock.now
        server.ids = ["n"] + (1...7).map { "l\($0)" }
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start.advanced(by: .seconds(61)))
        // The pages and the scroll stay.
        #expect(server.automaticRequests == 0)
        #expect(model.cards.count == 7)
        // Back at the top: the first page, quietly, once.
        await model.topAppeared()
        #expect(server.automaticRequests == 1)
        #expect(ids(model) == ["n", "l1", "l2"])
        model.topDisappeared()
        await model.topAppeared()
        #expect(server.automaticRequests == 1)
    }
}
