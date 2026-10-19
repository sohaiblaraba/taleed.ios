import Foundation
@testable import Taleed
import Testing

// MARK: - Bundle review

struct BundleReviewRulesTests {
    @Test func theContentFollowsTheStatus() {
        #expect(BundleReviewContent.of(fixtureBundle()) == .items)
        #expect(BundleReviewContent.of(fixtureBundle(items: [])) == .empty)
        #expect(BundleReviewContent.of(fixtureBundle(status: .ordered, orderId: "ord1")) == .ordered(orderId: "ord1"))
        #expect(BundleReviewContent.of(fixtureBundle(status: .cancelled)) == .closed)
        #expect(BundleReviewContent.of(fixtureBundle(status: .unknown)) == .closed)
    }

    @Test func thePrimaryItemIsTheFirstStillForSale() {
        #expect(fixtureBundle(items: [fixtureLine("a", available: false), fixtureLine("b")]).primaryListingId == "b")
        #expect(fixtureBundle(items: [fixtureLine("a", available: false)]).primaryListingId == "a")
        #expect(fixtureBundle(items: []).primaryListingId == nil)
    }
}

@MainActor
struct BundleReviewViewModelTests {
    let api = FakeBundlesApi()

    @Test func buyingUsesTheBundleAndItsAcceptedOffer() async {
        api.review = .success(fixtureBundle(items: [fixtureLine("a", available: false), fixtureLine("b")],
                                            acceptedOffer: AcceptedOfferRef(id: "o7", amount: 3000)))
        let model = BundleReviewViewModel(bundleId: "b1", api: api)
        await model.loadIfNeeded()
        #expect(model.checkout == CheckoutTarget(listingId: "b", offerId: "o7", bundleId: "b1"))
    }

    @Test func noCheckoutWhenTheServerSaysNo() async {
        api.review = .success(fixtureBundle(canBuy: false))
        let model = BundleReviewViewModel(bundleId: "b1", api: api)
        await model.loadIfNeeded()
        #expect(model.checkout == nil)
    }

    @Test func aMissingBundleIsNoLongerAvailable() async {
        api.review = .failure(apiFailure(.notFound, status: 404))
        let model = BundleReviewViewModel(bundleId: "b1", api: api)
        await model.loadIfNeeded()
        #expect(model.loadError?.isNotFound == true)
        #expect(model.bundle == nil)
    }

    @Test func removingSendsTheRestOfTheSelection() async {
        api.review = .success(fixtureBundle(items: [fixtureLine("a"), fixtureLine("b"), fixtureLine("c")]))
        let model = BundleReviewViewModel(bundleId: "b1", api: api)
        await model.loadIfNeeded()
        await model.remove("b")
        #expect(api.saved == [["a", "c"]])
        #expect(model.bundle?.listingIds == ["a", "c"])
        #expect(model.work == nil)
    }

    @Test func anOfferOpensItsConversation() async {
        let model = BundleReviewViewModel(bundleId: "b1", api: api)
        await model.loadIfNeeded()
        #expect(await model.makeOffer(amount: 3000) == .sent(conversationId: "c9"))
    }

    @Test func anOfferAlreadyWaitingOpensTheConversationOfTheFirstItem() async {
        api.offerResult = .failure(apiFailure(.offerPending))
        api.review = .success(fixtureBundle(items: [fixtureLine("a", available: false), fixtureLine("b")]))
        let model = BundleReviewViewModel(bundleId: "b1", api: api)
        await model.loadIfNeeded()
        #expect(await model.makeOffer(amount: 3000) == .pending(conversationId: "c-b"))
        #expect(api.openedFor == ["b"])
    }

    @Test func anOfferOutOfRangeReloadsTheBounds() async {
        api.offerResult = .failure(apiFailure(.offerOutOfRange, status: 400))
        let model = BundleReviewViewModel(bundleId: "b1", api: api)
        await model.loadIfNeeded()
        api.review = .success(fixtureBundle(offerRange: AmountRange(min: 900, max: 3000)))
        #expect(await model.makeOffer(amount: 5000) == .outOfRange(AmountRange(min: 900, max: 3000)))
    }

    @Test func askingAnswersTheConversation() async {
        let model = BundleReviewViewModel(bundleId: "b1", api: api)
        await model.loadIfNeeded()
        #expect(await model.askSeller() == "c9")
        api.askResult = .failure(apiFailure(.blocked, status: 403))
        #expect(await model.askSeller() == nil)
        #expect(model.notice == .error(apiFailure(.blocked, status: 403)))
    }
}

// MARK: - Bundle builder

struct BundleBuilderRulesTests {
    @Test func onlyItemsForSaleCanBeAddedUpToTwenty() {
        #expect(BundleBuilderRules.canAdd(.fixture(id: "x"), selection: []))
        #expect(!BundleBuilderRules.canAdd(.fixture(id: "x", status: .sold), selection: []))
        #expect(!BundleBuilderRules.canAdd(.fixture(id: "x", status: .reserved), selection: []))
        #expect(!BundleBuilderRules.canAdd(.fixture(id: "x"), selection: ["x"]))
        let full = (1...20).map { "l\($0)" }
        #expect(!BundleBuilderRules.canAdd(.fixture(id: "x"), selection: full))
        #expect(BundleBuilderRules.canAdd(.fixture(id: "x"), selection: Array(full.dropLast())))
    }

    @Test func theServersFlagsDecideWhetherTheBuilderOpens() {
        #expect(BundleBuilderRules.canBuild(.fixture(canBundle: true)))
        #expect(!BundleBuilderRules.canBuild(.fixture(canBundle: false)))
        #expect(!BundleBuilderRules.canBuild(.fixture(isMe: true)))
        #expect(!BundleBuilderRules.canBuild(.fixture(isBlocked: true)))
    }

    @Test func changesMadeElsewhereApplyToTheSelection() {
        // "c" was added on the listing screen, "a" removed on the review; "d" is a pick not saved yet.
        let merged = BundleBuilderRules.merge(local: ["a", "b", "d"], previous: ["a", "b"], server: ["b", "c"])
        #expect(merged == ["b", "d", "c"])
        #expect(BundleBuilderRules.merge(local: [], previous: [], server: []) == [])
    }
}

@MainActor
struct BundleBuilderViewModelTests {
    let members = FakeMembersApi()
    let bundles = FakeBundlesApi()

    @Test func theOpenBundlePreselectsItsItemsForSale() async {
        members.profile = .success(fixtureProfile(openBundleId: "b1"))
        bundles.review = .success(fixtureBundle(items: [fixtureLine("a"), fixtureLine("z", available: false), fixtureLine("b")]))
        let model = BundleBuilderViewModel(username: "amina", members: members, bundles: bundles)
        await model.loadIfNeeded()
        #expect(model.canBuild)
        #expect(model.selection == ["a", "b"])
    }

    @Test func withoutAnOpenBundleNothingIsPicked() async {
        members.profile = .success(fixtureProfile(openBundleId: nil))
        let model = BundleBuilderViewModel(username: "amina", members: members, bundles: bundles)
        await model.loadIfNeeded()
        #expect(model.selection.isEmpty)
        #expect(bundles.reviewCalls == 0)
    }

    @Test func aSellerTheMemberCannotBundleWithShowsNoBuilder() async {
        members.profile = .success(fixtureProfile(openBundleId: nil, canBundle: false))
        let model = BundleBuilderViewModel(username: "amina", members: members, bundles: bundles)
        await model.loadIfNeeded()
        #expect(!model.canBuild)
    }

    @Test func pickingThenReviewingSavesTheSelectionInOrder() async {
        members.profile = .success(fixtureProfile(openBundleId: nil))
        let model = BundleBuilderViewModel(username: "amina", members: members, bundles: bundles)
        await model.loadIfNeeded()
        model.toggle(.fixture(id: "b"))
        model.toggle(.fixture(id: "a"))
        model.toggle(.fixture(id: "s", status: .sold))
        #expect(model.selection == ["b", "a"])
        model.toggle(.fixture(id: "b"))
        model.toggle(.fixture(id: "b"))
        #expect(model.selection == ["a", "b"])
        #expect(await model.review() == "b1")
        #expect(bundles.saved == [["a", "b"]])
    }

    @Test func aFailedSaveKeepsTheSelectionAndSaysWhy() async {
        members.profile = .success(fixtureProfile(openBundleId: nil))
        bundles.saveResult = .failure(.network)
        let model = BundleBuilderViewModel(username: "amina", members: members, bundles: bundles)
        await model.loadIfNeeded()
        model.toggle(.fixture(id: "a"))
        #expect(await model.review() == nil)
        #expect(model.selection == ["a"])
        #expect(model.notice == .network)
    }

    @Test func comingBackPicksUpChangesMadeElsewhere() async {
        members.profile = .success(fixtureProfile(openBundleId: "b1"))
        bundles.review = .success(fixtureBundle(items: [fixtureLine("a")]))
        let model = BundleBuilderViewModel(username: "amina", members: members, bundles: bundles)
        await model.loadIfNeeded()
        model.toggle(.fixture(id: "d"))
        bundles.review = .success(fixtureBundle(items: [fixtureLine("a"), fixtureLine("c")]))
        await model.resync()
        #expect(model.selection == ["a", "d", "c"])
    }
}
