import Foundation
@testable import Taleed
import Testing

// MARK: - View models

@MainActor
struct CheckoutViewModelTests {
    let api = FakeCheckoutApi()
    let listings = FakeListingDetailApi()
    let bundles = FakeBundlesApi()

    func model(_ target: CheckoutTarget = CheckoutTarget(listingId: "l1")) -> CheckoutViewModel {
        CheckoutViewModel(target: target, dependencies: CheckoutDependencies(checkout: api, listings: listings, bundles: bundles))
    }

    @Test func itPrefillsFromTheProfileAndQuotes() async {
        let model = model()
        await model.loadIfNeeded()
        #expect(model.phase == .form)
        #expect(model.form.recipientName == "Karim Haddad")
        #expect(model.form.wilayaId == 31)
        #expect(api.quoteRequests.count == 1)
        #expect(model.communes.count == 1)
        #expect(model.action == .pending) // no commune nor street yet
    }

    @Test func theDefaultSavedAddressComesFirst() async {
        api.addresses = [SavedAddress(id: "a1", recipientName: "Lina K", phone: "0661000000", wilaya: CatalogWilaya(id: 16, name: "Alger"),
                                      communeId: 16001, commune: "Alger", addressLine: "Rue 1", isDefault: true)]
        let model = model()
        await model.loadIfNeeded()
        #expect(model.selectedAddressId == "a1")
        #expect(model.form.wilayaId == 16)
        #expect(model.form.communeId == 16001)
        #expect(model.action == .pay(amount: 3800))
    }

    @Test func withoutAWilayaTheGoodsShowWithoutAQuote() async {
        api.profile = .success(CheckoutProfile(name: "K H", phone: nil, wilayaId: nil))
        let model = model()
        await model.loadIfNeeded()
        #expect(model.phase == .form)
        #expect(api.quoteRequests.isEmpty)
        #expect(model.preview?.itemPrice == 2500)
        #expect(model.preview?.protectionFee == 175)
        await model.selectWilaya(31)
        #expect(api.quoteRequests.count == 1)
        #expect(model.pricing != nil)
    }

    @Test func theMembersOwnPendingOrderOpensInstead() async {
        api.quote = .failure(.failed(ApiFailure(status: 409, code: .listingUnavailable, orderId: "o7")))
        let model = model()
        await model.loadIfNeeded()
        #expect(model.phase == .heldByOrder(orderId: "o7"))
    }

    @Test func refusalsReplaceTheForm() async {
        for (error, phase) in [(apiFailure(.listingUnavailable), CheckoutViewModel.Phase.unavailable),
                               (apiFailure(.forbidden, status: 403), .forbidden), (apiFailure(.blocked, status: 403), .blocked),
                               (apiFailure(.notFound, status: 404), .notFound), (Taleed.ApiError.network, .failed(.network))] {
            api.quote = .failure(error)
            let model = model()
            await model.loadIfNeeded()
            #expect(model.phase == phase)
        }
    }

    @Test func aRefusedPromoCodeKeepsTheQuoteAndShowsTheReason() async {
        let model = model()
        await model.loadIfNeeded()
        api.quote = .success(fixturePricing(promoError: "Ce code promo n’est pas valide."))
        model.form.promoInput = "NOPE"
        await model.applyPromo()
        #expect(api.quoteRequests.last?.promoCode == "NOPE")
        #expect(model.promoError == .server("Ce code promo n’est pas valide."))
        #expect(model.form.appliedPromoCode == nil)
        #expect(model.form.promoInput == "NOPE")
        #expect(model.pricing?.amounts.total == 3800)
        #expect(!model.isStale)
    }

    @Test func anAcceptedPromoCodeIsKeptForTheNextQuotes() async {
        let model = model()
        await model.loadIfNeeded()
        api.quote = .success(fixturePricing(promoDiscount: 380, promo: CheckoutPromo(code: "WELCOME", kind: .percent, value: 10)))
        model.form.promoInput = "welcome"
        await model.applyPromo()
        #expect(model.form.appliedPromoCode == "WELCOME")
        #expect(model.form.promoInput.isEmpty)
        await model.selectKind(.stopdesk)
        #expect(api.quoteRequests.last?.promoCode == "WELCOME")
        #expect(api.quoteRequests.last?.delivery.kind == .stopdesk)
    }

    @Test func aTypedStreetDoesNotQuoteAgain() async {
        api.addresses = [SavedAddress(id: "a1", recipientName: "Lina K", phone: "0661000000", wilaya: CatalogWilaya(id: 16, name: "Alger"),
                                      communeId: 16001, commune: "Alger", addressLine: "Rue 1", isDefault: true)]
        let model = model()
        await model.loadIfNeeded()
        model.form.addressLine = "Rue 2, bâtiment B"
        #expect(!model.isStale)
        #expect(model.canPlaceOrder)
    }

    @Test func anOrderIsPlacedWithTheQuotedTotalAndOneClientIdPerTap() async throws {
        api.addresses = [SavedAddress(id: "a1", recipientName: "Lina K", phone: "0661000000", wilaya: CatalogWilaya(id: 16, name: "Alger"),
                                      communeId: 16001, commune: "Alger", addressLine: "Rue 1", isDefault: true)]
        api.orders = [.failure(.network)]
        let model = model()
        await model.loadIfNeeded()
        #expect(await model.placeOrder() == .stay)
        #expect(model.notice == .error(.network))
        let outcome = await model.placeOrder()
        #expect(outcome == .payOnline(url: try #require(URL(string: "https://pay.example/1")), orderId: "o1", address: nil))
        #expect(api.orderRequests.count == 2)
        #expect(api.orderRequests[0].clientId == api.orderRequests[1].clientId)
        #expect(api.orderRequests[0].expectedTotal == 3800)
        #expect(api.orderRequests[0].paymentMethod == "mock")
        #expect(api.orderRequests[0].recipientName == "Lina K")
    }

    @Test func aChangedPriceQuotesAgainAndTheNextTapIsANewOrder() async {
        api.addresses = [SavedAddress(id: "a1", recipientName: "Lina K", phone: "0661000000", wilaya: CatalogWilaya(id: 16, name: "Alger"),
                                      communeId: 16001, commune: "Alger", addressLine: "Rue 1", isDefault: true)]
        api.orders = [.failure(apiFailure(.priceChanged))]
        let model = model()
        await model.loadIfNeeded()
        api.quote = .success(fixturePricing(shipping: 700))
        #expect(await model.placeOrder() == .stay)
        #expect(api.quoteRequests.count == 2)
        #expect(model.action == .pay(amount: 3900))
        _ = await model.placeOrder()
        #expect(api.orderRequests[1].expectedTotal == 3900)
        #expect(api.orderRequests[0].clientId != api.orderRequests[1].clientId)
    }

    @Test func cashOnDeliveryAndTheWalletOpenThePaymentScreenAtOnce() async {
        api.addresses = [SavedAddress(id: "a1", recipientName: "Lina K", phone: "0661000000", wilaya: CatalogWilaya(id: 16, name: "Alger"),
                                      communeId: 16001, commune: "Alger", addressLine: "Rue 1", isDefault: true)]
        api.orders = [.success(PlacedOrder(order: fixtureOrder(), paymentURL: nil, replayed: false))]
        let model = model()
        await model.loadIfNeeded()
        #expect(await model.placeOrder() == .placed(orderId: "o1", address: nil))
    }

    @Test func aCommuneTheCarrierNoLongerServesIsPickedAgain() async {
        api.addresses = [SavedAddress(id: "a1", recipientName: "Lina K", phone: "0661000000", wilaya: CatalogWilaya(id: 16, name: "Alger"),
                                      communeId: 16001, commune: "Alger", addressLine: "Rue 1", isDefault: true)]
        api.quotes = [.failure(.failed(ApiFailure(status: 400, code: .invalidRequest,
                                                  issues: [ApiFieldIssue(path: "body.delivery.communeId", message: "x")])))]
        let model = model()
        await model.loadIfNeeded()
        #expect(model.form.communeId == nil)
        #expect(model.fieldErrors[.commune] == .pickAgain)
        #expect(model.phase == .form)
        #expect(api.quoteRequests.count == 2)
    }

    @Test func anUnavailableMethodFallsBackToTheServersChoice() async {
        let model = model()
        await model.loadIfNeeded()
        api.quotes = [.failure(apiFailure(.paymentMethodUnavailable))]
        await model.selectPaymentMethod("cod")
        #expect(model.form.paymentMethod == nil)
        #expect(model.notice == .info(.checkoutErrorMethodUnavailable))
        #expect(api.quoteRequests.last?.paymentMethod == nil)
    }
}

@MainActor
struct OrderPaymentViewModelTests {
    let api = FakeCheckoutApi()

    @Test func itSyncsWhenItOpens() async {
        let model = OrderPaymentViewModel(target: OrderPaymentTarget(orderId: "o1", attempt: .returnedSuccess), api: api)
        await model.loadIfNeeded()
        #expect(api.syncCalls == 1)
        #expect(model.outcome == .paid)
    }

    @Test func aPaymentNotSettledYetIsSyncedAgain() async {
        api.syncs = [.success(fixtureOrder(status: .pendingPayment, canPay: true)), .success(fixtureOrder())]
        let model = OrderPaymentViewModel(target: OrderPaymentTarget(orderId: "o1", attempt: .returnedSuccess), api: api,
                                          followUpDelay: .zero)
        await model.loadIfNeeded()
        #expect(api.syncCalls == 2)
        #expect(model.outcome == .paid)
    }

    @Test func payingAgainThenClosingThePageSyncs() async throws {
        api.sync = .success(fixtureOrder(status: .pendingPayment, canPay: true))
        let model = OrderPaymentViewModel(target: OrderPaymentTarget(orderId: "o1"), api: api)
        await model.loadIfNeeded()
        #expect(model.outcome == .awaitingPayment)
        #expect(try #require(await model.paymentPage()) == URL(string: "https://pay.example/1"))
        await model.paymentPageClosed(callback: nil)
        #expect(model.outcome == .failed)
        #expect(api.syncCalls == 2)
    }

    @Test func savingTheAddressOnce() async {
        let draft = AddressDraft(recipientName: "K H", phone: "0550123456", wilayaId: 31, communeId: 31001, addressLine: "Rue 1")
        let model = OrderPaymentViewModel(target: OrderPaymentTarget(orderId: "o1", addressToSave: draft), api: api)
        #expect(model.addressOffer == .offered)
        await model.saveAddress()
        await model.saveAddress()
        #expect(api.saved == [draft])
        #expect(model.addressOffer == .saved)
    }

    @Test func aFailedFirstSyncShowsTheError() async {
        api.sync = .failure(apiFailure(.notFound, status: 404))
        let model = OrderPaymentViewModel(target: OrderPaymentTarget(orderId: "o1"), api: api)
        await model.loadIfNeeded()
        #expect(model.loadError?.isNotFound == true)
        #expect(model.order == nil)
    }
}
