import Foundation
@testable import Taleed
import Testing

private struct Row: Identifiable, Equatable, Sendable {
    let id: String
    var title = ""
}

/// A paged endpoint with canned answers per cursor.
@MainActor
private final class FakePages {
    var pages: [String?: Result<Page<Row>, ApiError>] = [:]
    private(set) var requested: [String?] = []

    func fetch(_ cursor: String?) async throws(ApiError) -> Page<Row> {
        requested.append(cursor)
        guard let result = pages[cursor] else { throw .network }
        return try result.get()
    }
}

private func page(_ ids: [String], next: String?, total: Int = 0) -> Result<Page<Row>, ApiError> {
    .success(Page(items: ids.map { Row(id: $0) }, nextCursor: next, total: total))
}

@MainActor
struct PagedListTests {
    private let api = FakePages()
    private var list: PagedList<Row> {
        PagedList { [api] cursor throws(ApiError) in try await api.fetch(cursor) }
    }

    @Test func pagesAppendWithoutDuplicates() async {
        api.pages = [nil: page(["a", "b", "c"], next: "p2", total: 5), "p2": page(["c", "d", "b", "e"], next: nil, total: 5)]
        let list = self.list
        await list.loadIfNeeded()
        #expect(list.items.map(\.id) == ["a", "b", "c"])
        #expect(list.hasMore)
        await list.loadMore()
        #expect(list.items.map(\.id) == ["a", "b", "c", "d", "e"])
        #expect(!list.hasMore)
        #expect(list.total == 5)
        // The last page asks for nothing more.
        await list.loadMore()
        #expect(api.requested == [nil, "p2"])
    }

    @Test func duplicatesWithinOnePageAreDropped() async {
        api.pages = [nil: page(["a", "a", "b"], next: nil)]
        let list = self.list
        await list.loadIfNeeded()
        #expect(list.items.map(\.id) == ["a", "b"])
    }

    @Test func refreshStartsAgainWithoutACursor() async {
        api.pages = [nil: page(["a", "b"], next: "p2"), "p2": page(["c"], next: nil)]
        let list = self.list
        await list.loadIfNeeded()
        await list.loadMore()
        api.pages[nil] = page(["z", "a"], next: "p2")
        await list.refresh()
        #expect(list.items.map(\.id) == ["z", "a"])
        #expect(list.hasMore)
        #expect(api.requested == [nil, "p2", nil])
    }

    @Test func firstPageFailureShowsTheErrorThenRetryLoads() async {
        let list = self.list
        await list.loadIfNeeded()
        #expect(list.error == .network)
        #expect(!list.hasLoaded)
        api.pages = [nil: page([], next: nil)]
        await list.retry()
        #expect(list.error == nil)
        #expect(list.isEmpty)
    }

    @Test func failedRefreshKeepsTheItems() async {
        api.pages = [nil: page(["a"], next: nil)]
        let list = self.list
        await list.loadIfNeeded()
        api.pages[nil] = .failure(.server(status: 503))
        await list.refresh()
        #expect(list.items.map(\.id) == ["a"])
        #expect(list.refreshError == .server(status: 503))
        #expect(list.error == nil)
    }

    @Test func failedNextPageOffersRetry() async {
        api.pages = [nil: page(["a"], next: "p2")]
        let list = self.list
        await list.loadIfNeeded()
        await list.loadMore()
        #expect(list.loadMoreError == .network)
        api.pages["p2"] = page(["b"], next: nil)
        await list.retry()
        #expect(list.loadMoreError == nil)
        #expect(list.items.map(\.id) == ["a", "b"])
    }

    @Test func expiredCursorStartsAgainFromTheTop() async {
        let invalidCursor = ApiError.failed(ApiFailure(status: 400, code: .invalidRequest,
                                                       issues: [ApiFieldIssue(path: "query.cursor", message: "Invalid cursor.")]))
        api.pages = [nil: page(["a"], next: "old"), "old": .failure(invalidCursor)]
        let list = self.list
        await list.loadIfNeeded()
        api.pages[nil] = page(["x", "a"], next: nil)
        await list.loadMore()
        #expect(list.items.map(\.id) == ["x", "a"])
        #expect(list.loadMoreError == nil)
        #expect(api.requested == [nil, "old", nil])
    }

    @Test func loadIfNeededLoadsOnce() async {
        api.pages = [nil: page(["a"], next: nil)]
        let list = self.list
        await list.loadIfNeeded()
        await list.loadIfNeeded()
        #expect(api.requested == [nil])
    }

    @Test func localChangesKeepIdsUnique() async {
        api.pages = [nil: page(["a", "b"], next: nil, total: 2)]
        let list = self.list
        await list.loadIfNeeded()
        list.prepend(Row(id: "c"))
        list.prepend(Row(id: "a"))
        #expect(list.items.map(\.id) == ["c", "a", "b"])
        #expect(list.total == 3)
        list.update(Row(id: "b", title: "edited"))
        #expect(list.items.last?.title == "edited")
        list.remove(id: "a")
        #expect(list.items.map(\.id) == ["c", "b"])
        #expect(list.total == 2)
    }

    @Test func loadMoreIfNeededWaitsForTheLastRows() async {
        api.pages = [nil: page((1...10).map(String.init), next: "p2"), "p2": page(["11"], next: nil)]
        let list = self.list
        await list.loadIfNeeded()
        await list.loadMoreIfNeeded(after: Row(id: "2"))
        #expect(api.requested == [nil])
        await list.loadMoreIfNeeded(after: Row(id: "8"))
        #expect(api.requested == [nil, "p2"])
    }
}

// MARK: - Pagination when the screen lets go

@MainActor
struct PagedListCancellationTests {
    @Test func aFirstPageLoadSaysWhetherFreshItemsArrived() async {
        var fails = false
        let list = PagedList<ListingSummary> { _ throws(Taleed.ApiError) in
            if fails { throw .network }
            return Page(items: [.fixture(id: "a")], nextCursor: nil, total: 1)
        }
        let loaded = await list.reload()
        #expect(loaded)
        fails = true
        let refreshed = await list.refresh()
        #expect(!refreshed)
        #expect(list.refreshError == .network)
    }

    @Test func aCancelledFirstPageIsNoErrorAndNoLoad() async {
        var started = false
        let list = PagedList<ListingSummary> { _ throws(Taleed.ApiError) in
            started = true
            try? await Task.sleep(for: .seconds(5))
            throw .network
        }
        let task = Task { await list.reload() }
        await waitUntil { started }
        task.cancel()
        let loaded = await task.value
        #expect(!loaded)
        #expect(list.error == nil && !list.isLoadingFirstPage && !list.hasLoaded)
    }

    @Test func aCancelledNextPageIsNoError() async {
        var slow = false
        let list = PagedList<ListingSummary> { cursor throws(Taleed.ApiError) in
            if cursor == nil {
                return Page(items: [.fixture(id: "a")], nextCursor: "p2", total: 2)
            }
            slow = true
            try? await Task.sleep(for: .seconds(5))
            throw .network
        }
        await list.loadIfNeeded()
        let task = Task { await list.loadMore() }
        await waitUntil { slow }
        task.cancel()
        await task.value
        #expect(list.loadMoreError == nil)
        #expect(!list.isLoadingMore)
        #expect(list.hasMore)
    }
}
