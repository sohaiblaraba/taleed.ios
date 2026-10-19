import Foundation
@testable import Taleed
import Testing

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
