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
