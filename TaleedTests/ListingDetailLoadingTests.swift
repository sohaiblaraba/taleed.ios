import Foundation
@testable import Taleed
import Testing

/// When the listing screen loads `GET /listings/{id}`, and which load counts a view (API 1.5.3).
@MainActor
struct ListingDetailLoadingTests {
    private let api = FakeListingDetailApi()
    private let bundles = FakeBundlesApi()

    @Test func theFirstLoadHappensOnce() async {
        let model = ListingDetailViewModel(listingId: "l1", api: api, bundles: bundles)
        await model.loadIfNeeded()
        await model.loadIfNeeded()
        #expect(api.listingCalls == [.init(countView: true, automatic: false)])
    }

    @Test func onlyTheOpeningLoadCountsAView() async {
        api.listings = [.failure(.network), .success(.fixture())]
        let model = ListingDetailViewModel(listingId: "l1", api: api, bundles: bundles)
        await model.loadIfNeeded()
        // "Retry" after a failed first load still opens the screen: it counts.
        await model.retry()
        // Pull-to-refresh, after signing in, after an action error: never counted again.
        await model.reload()
        await model.memberDidChange(to: "amina")
        api.conversation = .failure(apiError(403, "blocked"))
        _ = await model.messageSeller()
        #expect(api.listingCalls.map(\.countView) == [true, true, false, false, false])
    }

    @Test func returningAfterAWhileReloadsQuietly() async {
        let model = ListingDetailViewModel(listingId: "l1", api: api, bundles: bundles)
        await model.loadIfNeeded()
        let start = ContinuousClock.now
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start + .seconds(10))
        #expect(api.listingCalls == [.init(countView: true, automatic: false)])
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start + .seconds(61))
        #expect(api.listingCalls == [.init(countView: true, automatic: false), .init(countView: false, automatic: true)])
    }
}

/// A listing opened by a website link that names it by its slug (`/listings/{slug}`).
@MainActor
struct ListingSlugRouteTests {
    private let api = FakeListingDetailApi()
    private let bundles = FakeBundlesApi()

    /// A website link names the listing by its slug: the first load reads it, then everything goes on with
    /// the listing's id (the API takes no slug in the bundle, report, checkout and order bodies).
    @Test func afterASlugLinkEverythingUsesTheLoadedId() async {
        api.listing = .success(.fixture(id: "l1", openBundleId: "b1"))
        bundles.review = .success(fixtureBundle(items: [fixtureLine("x"), fixtureLine("l1")]))
        let model = ListingDetailViewModel(listingId: "robe-fleurie-zara", api: api, bundles: bundles, memberId: "me")
        #expect(model.listingId == "robe-fleurie-zara")
        await model.loadIfNeeded()
        #expect(model.routeId == "robe-fleurie-zara")
        #expect(model.listingId == "l1")
        // The bundle state compares the loaded id: the item is in the bundle, so the toggle removes it.
        #expect(await model.toggleBundle() == .done)
        #expect(bundles.saved == [["x"]])
        #expect(model.listing?.inMyBundle == false)
        #expect(await model.toggleBundle() == .done)
        #expect(bundles.saved.last == ["x", "l1"])
        #expect(model.listing?.inMyBundle == true)
        // Calls, reloads and the hearts' key.
        _ = await model.makeOffer(amount: 2000)
        _ = await model.messageSeller()
        await model.reload()
        #expect(api.offerListingIds == ["l1"])
        #expect(api.conversationListingIds == ["l1"])
        #expect(api.listingIds == ["robe-fleurie-zara", "l1"])
        #expect(model.listing?.summary.id == "l1")
        // A later `404` keeps the id for the lists to drop its card.
        api.listing = .failure(apiError(404, "not_found"))
        await model.reload()
        #expect(model.listing == nil)
        #expect(model.listingId == "l1")
    }

    /// The report sheet gets `model.listingId`: the loaded id goes in the `POST /reports` body.
    @Test func aReportAfterASlugLinkNamesTheLoadedId() async throws {
        let model = ListingDetailViewModel(listingId: "فستان-صيفي", api: api, bundles: bundles)
        await model.loadIfNeeded()
        let report = ReportViewModel(target: .listing(id: model.listingId), api: api,
                                     upload: { _ throws(Taleed.ApiError) in UploadedPhoto(key: "k", url: nil, thumbURL: nil) })
        report.reason = "SCAM"
        #expect(await report.submit() == .sent)
        let sent = try #require(api.reports.first)
        #expect(sent.target == .listing(id: "l1"))
    }
}
