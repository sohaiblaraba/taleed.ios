import Foundation
@testable import Taleed
import Testing

// MARK: - Fakes

func myCard(_ id: String, status: Taleed.ListingStatus = .active, price: Int = 2500) -> ListingSummary {
    ListingSummary(id: id, title: "Article \(id)", price: price, size: nil, brandName: nil, condition: "VERY_GOOD",
                   status: status, imageURL: nil, favoritesCount: 0, isFavorited: false, isBoosted: false, shipsFrom: nil,
                   sellerRating: nil)
}

/// `GET /me/listings` from canned rows by status, with fixed counts.
@MainActor
final class FakeMyListingsApi: MyListingsApi {
    var rows: [Taleed.ListingStatus: [ListingSummary]] = [:]
    var counts = MyListingCounts(active: 2, hidden: 1, reserved: 0, sold: 1)
    var failures: [Taleed.ApiError] = []
    private(set) var calls: [Taleed.ListingStatus] = []

    func myListings(status: Taleed.ListingStatus, cursor: String?, automatic: Bool) async throws(Taleed.ApiError) -> MyListingsPage {
        calls.append(status)
        if !failures.isEmpty { throw failures.removeFirst() }
        let items = rows[status] ?? []
        return MyListingsPage(page: Page(items: items, nextCursor: nil, total: items.count), counts: counts)
    }
}

/// Hide, resume and delete from canned results.
@MainActor
final class FakeOwnerApi: ListingOwnerApi {
    var visibility: Result<Taleed.ListingDetail, Taleed.ApiError>?
    var deletion: Result<Void, Taleed.ApiError> = .success(())
    private(set) var hidden: [(String, Bool)] = []
    private(set) var deleted: [String] = []

    func setListingHidden(id: String, hidden: Bool) async throws(Taleed.ApiError) -> Taleed.ListingDetail {
        self.hidden.append((id, hidden))
        return try (visibility ?? .success(editableListing(id: id, status: hidden ? .hidden : .active))).get()
    }

    func deleteListing(id: String) async throws(Taleed.ApiError) {
        deleted.append(id)
        try deletion.get()
    }
}

// MARK: - Tests

@MainActor
struct MyListingsTests {
    private let api = FakeMyListingsApi()
    private let owner = FakeOwnerApi()
    private let center = ListingChangeCenter()

    init() {
        api.rows = [.active: [myCard("a1"), myCard("a2")], .hidden: [myCard("h1", status: .hidden)],
                    .sold: [myCard("s1", status: .sold)]]
    }

    private func model() -> MyListingsViewModel {
        MyListingsViewModel(api: api, owner: owner, changesSeq: center.seq)
    }

    @Test func theActiveTabLoadsFirstWithTheCountsOfEveryTab() async {
        let model = model()
        await model.load()
        #expect(model.selectedTab == .active)
        #expect(model.list.items.map(\.id) == ["a1", "a2"])
        #expect(model.counts == MyListingCounts(active: 2, hidden: 1, reserved: 0, sold: 1))
        #expect(api.calls == [.active])
    }

    @Test func eachTabLoadsWhenFirstShownThenKeepsItsRows() async {
        let model = model()
        await model.load()
        await model.select(.hidden)
        #expect(model.list.items.map(\.id) == ["h1"])
        await model.select(.active)
        await model.select(.hidden)
        #expect(api.calls == [.active, .hidden])
        await model.select(.reserved)
        #expect(model.list.isEmpty)
    }

    @Test func rowActionsFollowTheStatusTable() {
        let model = model()
        #expect(model.actions(for: myCard("a")) == .init(canEdit: true, visibility: .hide, canDelete: true))
        #expect(model.actions(for: myCard("h", status: .hidden)) == .init(canEdit: true, visibility: .resume, canDelete: true))
        #expect(model.actions(for: myCard("r", status: .reserved)) == .init(canEdit: false, visibility: nil, canDelete: false))
        #expect(model.actions(for: myCard("s", status: .sold)) == .init(canEdit: false, visibility: nil, canDelete: true))
    }

    @Test func hidingMovesTheRowToTheHiddenTabAndTellsTheOtherScreens() async {
        let model = model()
        await model.load()
        await model.select(.hidden)
        await model.select(.active)
        let outcome = await model.setHidden(myCard("a1"), hidden: true, changes: center)
        #expect(outcome == .visibilityChanged(.hide))
        #expect(owner.hidden.map(\.0) == ["a1"])
        #expect(model.list.items.map(\.id) == ["a2"])
        #expect(model.counts == MyListingCounts(active: 1, hidden: 2, reserved: 0, sold: 1))
        #expect(center.changes(after: 0)?.map(\.listingId) == ["a1"])
        // The Hidden tab loads again to show it where the server puts it.
        api.rows[.hidden] = [myCard("a1", status: .hidden), myCard("h1", status: .hidden)]
        await model.select(.hidden)
        #expect(model.list.items.map(\.id) == ["a1", "h1"])
    }

    @Test func deletingRemovesTheRowAndCountsIt() async {
        let model = model()
        await model.load()
        #expect(await model.delete(myCard("a2"), changes: center) == .deleted)
        #expect(model.list.items.map(\.id) == ["a1"])
        #expect(model.counts?.active == 1)
        #expect(center.changes(after: 0)?.first?.kind == .deleted)
    }

    @Test func aDeletionRetriedAfterALostAnswerIsDone() async {
        let model = model()
        await model.load()
        owner.deletion = .failure(apiError(404, "not_found"))
        #expect(await model.delete(myCard("a1"), changes: center) == .deleted)
        #expect(model.list.items.map(\.id) == ["a2"])
    }

    @Test func aLockedListingShowsTheMessageAndReloads() async {
        let model = model()
        await model.load()
        owner.visibility = .failure(apiError(409, "listing_locked"))
        api.rows[.active] = [myCard("a2")]
        let outcome = await model.setHidden(myCard("a1"), hidden: true, changes: center)
        #expect(outcome == .failed(apiError(409, "listing_locked")))
        #expect(model.list.items.map(\.id) == ["a2"])
        #expect(api.calls == [.active, .active])
    }

    @Test func aSecondActionOnTheSameRowWaits() async {
        let model = model()
        await model.load()
        async let first = model.delete(myCard("a1"), changes: center)
        async let second = model.delete(myCard("a1"), changes: center)
        let outcomes = await [first, second]
        #expect(outcomes.contains(.busy) || owner.deleted.count == 2)
    }

    @Test func changesFromOtherScreensMoveRowsAndSkipItsOwn() async {
        let model = model()
        await model.load()
        // Edited on the edit form: the row shows the new price.
        center.post(.updated(editableListing(id: "a1", price: 2300)), listingId: "a1")
        await model.sync(with: center)
        #expect(model.list.items.first?.price == 2300)
        // Resumed on the listing screen: it leaves the Hidden tab.
        await model.select(.hidden)
        center.post(.updated(editableListing(id: "h1", status: .active)), listingId: "h1")
        await model.sync(with: center)
        #expect(model.list.items.isEmpty)
        #expect(model.counts?.hidden == 0)
        #expect(model.counts?.active == 3)
        // Its own changes are already applied.
        center.post(.deleted, listingId: "a2", source: model.changeSource)
        await model.sync(with: center)
        #expect(model.list(.active).items.map(\.id).contains("a2"))
    }

    @Test func aPublishedListingJoinsTheActiveTab() async {
        let model = model()
        await model.load()
        api.rows[.active] = [myCard("new"), myCard("a1"), myCard("a2")]
        center.post(.created, listingId: "new")
        await model.sync(with: center)
        #expect(model.list.items.map(\.id) == ["new", "a1", "a2"])
    }

    @Test func aFailedFirstPageShowsTheErrorThenRetryWorks() async {
        api.failures = [.network]
        let model = model()
        await model.load()
        #expect(model.list.error == .network)
        await model.list.reload()
        #expect(model.list.items.count == 2)
    }

    @Test func theListingsDeleteTitleAndBodyExistInEveryLanguage() {
        for language in AppLanguage.allCases {
            for key in [L10nKey.appListingDeleteTitle, .appListingDeleteBody, .appMyListingsTabCount] {
                #expect(DesignSystemStrings.string(key, language: language) != key.rawValue)
            }
            for tab in MyListingsTab.allCases {
                #expect(DesignSystemStrings.string(MyListingsText.tabKey(tab), language: language) != MyListingsText.tabKey(tab).rawValue)
                #expect(DesignSystemStrings.string(MyListingsText.emptyTitleKey(tab), language: language)
                    != MyListingsText.emptyTitleKey(tab).rawValue)
                #expect(DesignSystemStrings.string(MyListingsText.emptyBodyKey(tab), language: language)
                    != MyListingsText.emptyBodyKey(tab).rawValue)
            }
        }
        #expect(DesignSystemStrings.format(.appMyListingsTabCount, locale: Locale(identifier: "fr"), "En vente", 4)
            == "En vente (4)")
    }
}

// MARK: - Change center

@MainActor
struct ListingChangeCenterTests {
    @Test func screensCatchUpOnTheChangesAfterTheirs() {
        let center = ListingChangeCenter()
        center.post(.created, listingId: "a")
        center.post(.deleted, listingId: "b")
        #expect(center.changes(after: 0)?.map(\.listingId) == ["a", "b"])
        #expect(center.changes(after: 1)?.map(\.listingId) == ["b"])
        #expect(center.changes(after: 2) == [])
    }

    @Test func aScreenTooFarBehindReloads() {
        let center = ListingChangeCenter()
        for index in 0 ..< ListingChangeCenter.capacity + 5 { center.post(.stale, listingId: "l\(index)") }
        #expect(center.changes(after: 0) == nil)
        #expect(center.changes(after: center.seq - 1)?.count == 1)
    }

    @Test func theListingScreenShowsTheSavedListing() async {
        let center = ListingChangeCenter()
        let api = FakeListingDetailApi()
        api.listing = .success(editableListing())
        let model = ListingDetailViewModel(listingId: "l1", api: api)
        model.startFollowing(center)
        await model.loadIfNeeded()
        center.post(.updated(editableListing(price: 2300, condition: "GOOD")), listingId: "l1")
        await model.sync(with: center)
        #expect(model.listing?.price == 2300)
        #expect(api.listingCalls.count == 1)
        // Another listing's change is not this screen's.
        center.post(.deleted, listingId: "other")
        await model.sync(with: center)
        #expect(api.listingCalls.count == 1)
        // Deleted elsewhere: it loads again and finds it gone.
        api.listing = .failure(apiError(404, "not_found"))
        center.post(.deleted, listingId: "l1")
        await model.sync(with: center)
        #expect(model.loadError?.isNotFound == true)
    }
}
