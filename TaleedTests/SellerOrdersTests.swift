import Foundation
@testable import Taleed
import Testing

// The seller's side of an order (screens.md §2 G13 and §7 G12/G13): shipping, the label, answering a
// dispute.

// MARK: - Rules

struct SellerOrderRulesTests {
    @Test func sellerButtonsComeOnlyFromActionsInTheWebsitesOrder() {
        #expect(OrderRules.sellerActions(OrderActionFlags()).isEmpty)
        #expect(OrderRules.sellerActions(OrderActionFlags(canShip: true)) == [.ship])
        #expect(OrderRules.sellerActions(OrderActionFlags(canPrintLabel: true)) == [.printLabel])
        #expect(OrderRules.sellerActions(OrderActionFlags(canReplaceTestLabel: true, canPrintLabel: true))
            == [.printLabel, .replaceTestLabel])
        #expect(OrderRules.sellerActions(OrderActionFlags(canRespondToDispute: true)) == [.acceptClaim, .contestClaim])
        #expect(OrderRules.sellerActions(OrderActionFlags(canPrintLabel: true, canReview: true)) == [.printLabel, .review])
    }

    @Test func buyerFlagsNeverMakeSellerButtons() {
        let buyerFlags = OrderActionFlags(canPay: true, canCancel: true, canConfirmReceipt: true, awaitingArrival: true,
                                          canOpenDispute: true)
        #expect(OrderRules.sellerActions(buyerFlags).isEmpty)
        // The seller never cancels, even if the flag ever came.
        #expect(OrderRules.memberActions(OrderActionFlags(canCancel: true, canShip: true), side: .seller) == [.ship])
        // And seller flags never reach the buyer.
        #expect(OrderRules.memberActions(OrderActionFlags(canShip: true, canRespondToDispute: true), side: .buyer).isEmpty)
    }

    @Test func theSellerSeesWhatTheyReceive() {
        let money = OrderMoney(itemPrice: 2500, protectionFee: 175, shippingFee: 600, promoDiscount: 300, voucherDiscount: 0, total: 2975,
                               walletApplied: 1000, amountDue: 1975, sellerEarns: 2500)
        let amounts = OrderRules.amounts(for: orderDetail(side: .seller, money: money))
        #expect(amounts.total == .sellerEarns)
        #expect(amounts.totalAmount == 2500)
        #expect(amounts.lines.map(\.0) == [.itemPrice(bundleCount: nil), .protectionFee, .shippingFee, .discount, .total])
    }

    @Test func theSellersNoticesFollowTheDeadlines() {
        let date = Date(timeIntervalSince1970: 1000)
        #expect(OrderRules.notices(for: orderDetail(side: .seller, status: .paid, shipDeadline: date)) == [.shipBy(date)])
        #expect(OrderRules.notices(for: orderDetail(side: .seller, status: .prepared, shipDeadline: date)) == [.dropOffBy(date)])
        #expect(OrderRules.notices(for: orderDetail(side: .seller, status: .shipped, stopdesk: "Agence Oran", pickupReady: true))
            == [.pickupReady(place: "Agence Oran")])
    }
}

// MARK: - Order screen

@MainActor
struct SellerOrderDetailViewModelTests {
    private func loadedModel(_ api: FakeOrdersApi) async -> OrderDetailViewModel {
        let model = OrderDetailViewModel(orderId: "o1", api: api)
        await model.loadIfNeeded()
        return model
    }

    @Test func shippingShowsThePreparedOrderAndOpensItsLabel() async {
        let api = FakeOrdersApi()
        api.defaultOrder = orderDetail(side: .seller, status: .paid, actions: OrderActionFlags(canShip: true))
        let model = await loadedModel(api)
        #expect(model.memberActions == [.ship])

        let url = await model.ship()
        #expect(api.ships == 1)
        #expect(url?.absoluteString == "http://localhost:3000/orders/o1/label?exp=1&sig=a")
        #expect(model.order?.status == .prepared)
        #expect(model.memberActions == [.printLabel])
        #expect(model.notice == .success(.ordersLabelReady))
        #expect(model.busy == nil)
    }

    @Test func aParcelWithoutALabelYetSaysItComesLater() async {
        let api = FakeOrdersApi()
        api.defaultOrder = orderDetail(side: .seller, status: .paid, actions: OrderActionFlags(canShip: true))
        api.shipResult = .success(ShipmentResult(order: orderDetail(side: .seller, status: .prepared), label: nil))
        let model = await loadedModel(api)
        let url = await model.ship()
        #expect(url == nil)
        #expect(model.order?.status == .prepared)
        #expect(model.notice == .info(.appOrderLabelPending))
    }

    @Test func theTestLabelCanBeReplaced() async {
        let api = FakeOrdersApi()
        api.defaultOrder = orderDetail(side: .seller, status: .prepared, actions: OrderActionFlags(canReplaceTestLabel: true))
        let model = await loadedModel(api)
        #expect(model.memberActions == [.replaceTestLabel])
        #expect(await model.ship() != nil)
        #expect(api.ships == 1)
    }

    @Test func shippingIsRefusedWithoutTheFlag() async {
        let api = FakeOrdersApi()
        api.defaultOrder = orderDetail(side: .seller, status: .prepared, actions: OrderActionFlags(canPrintLabel: true))
        let model = await loadedModel(api)
        #expect(await model.ship() == nil)
        #expect(api.ships == 0)
    }

    @Test func aCarrierRefusalStaysOnScreenWithTheCarriersWords() async {
        let api = FakeOrdersApi()
        api.defaultOrder = orderDetail(side: .seller, status: .paid, actions: OrderActionFlags(canShip: true))
        let refusal = Taleed.ApiError.failed(ApiFailure(status: 502, code: .carrierError,
                                                        detail: "Yalidine parcel rejected: numéro de téléphone invalide"))
        api.shipResult = .failure(refusal)
        let model = await loadedModel(api)
        let calls = api.orderCalls

        #expect(await model.ship() == nil)
        #expect(model.carrierError == refusal)
        #expect(model.carrierError?.detail == "Yalidine parcel rejected: numéro de téléphone invalide")
        #expect(model.showsCarrierError)
        // Not a toast, and the order is not reloaded: nothing changed.
        #expect(model.notice == nil)
        #expect(api.orderCalls == calls)
        #expect(model.order?.status == .paid)

        // Trying again clears it; success hides it.
        api.shipResult = .success(ShipmentResult(order: orderDetail(side: .seller, status: .prepared,
                                                                    actions: OrderActionFlags(canPrintLabel: true)), label: nil))
        _ = await model.ship()
        #expect(model.carrierError == nil)
        #expect(!model.showsCarrierError)
    }

    @Test func theCarrierRefusalHidesOnceTheParcelCannotBeCreated() async {
        let api = FakeOrdersApi()
        api.orderResults = [
            .success(orderDetail(side: .seller, status: .paid, actions: OrderActionFlags(canShip: true))),
            .success(orderDetail(side: .seller, status: .cancelled)),
        ]
        api.shipResult = .failure(.failed(ApiFailure(status: 502, code: .carrierError, detail: "Refusé")))
        let model = await loadedModel(api)
        _ = await model.ship()
        #expect(model.showsCarrierError)
        await model.reload()
        #expect(!model.showsCarrierError)
    }

    @Test func aStaleShipReloadsTheOrder() async {
        let api = FakeOrdersApi()
        api.orderResults = [
            .success(orderDetail(side: .seller, status: .paid, actions: OrderActionFlags(canShip: true))),
            .success(orderDetail(side: .seller, status: .prepared, actions: OrderActionFlags(canPrintLabel: true))),
        ]
        api.shipResult = .failure(failure(409, .invalidState))
        let model = await loadedModel(api)
        #expect(await model.ship() == nil)
        #expect(model.order?.status == .prepared)
        #expect(model.notice == .error(failure(409, .invalidState)))
        #expect(model.carrierError == nil)
    }

    @Test func aLostShipAnswerReloadsTheOrder() async {
        let api = FakeOrdersApi()
        api.orderResults = [
            .success(orderDetail(side: .seller, status: .paid, actions: OrderActionFlags(canShip: true))),
            .success(orderDetail(side: .seller, status: .prepared, actions: OrderActionFlags(canPrintLabel: true))),
        ]
        api.shipResult = .failure(.network)
        let model = await loadedModel(api)
        _ = await model.ship()
        // The parcel may exist anyway: the order as it is now.
        #expect(model.order?.status == .prepared)
        #expect(model.memberActions == [.printLabel])
    }

    @Test func printingFetchesAFreshLinkOnEachTap() async {
        let api = FakeOrdersApi()
        api.defaultOrder = orderDetail(side: .seller, status: .prepared, actions: OrderActionFlags(canPrintLabel: true))
        let model = await loadedModel(api)
        let first = await model.labelURL()
        api.labelResult = .success(ShippingLabelInfo(url: URL(string: "http://localhost:3000/orders/o1/label?exp=3&sig=c")!,
                                                     expiresAt: nil))
        let second = await model.labelURL()
        #expect(api.labelCalls == 2)
        #expect(first?.absoluteString.contains("exp=2") == true)
        #expect(second?.absoluteString.contains("exp=3") == true)
        #expect(model.busy == nil)
    }

    @Test func aRefusedLabelReloadsAndSaysWhy() async {
        let api = FakeOrdersApi()
        api.orderResults = [
            .success(orderDetail(side: .seller, status: .prepared, actions: OrderActionFlags(canPrintLabel: true))),
            .success(orderDetail(side: .seller, status: .cancelled)),
        ]
        api.labelResult = .failure(failure(403, .forbidden))
        let model = await loadedModel(api)
        #expect(await model.labelURL() == nil)
        #expect(model.order?.status == .cancelled)
        #expect(model.notice == .error(failure(403, .forbidden)))
    }

    @Test func noLabelWithoutTheFlag() async {
        let api = FakeOrdersApi()
        api.defaultOrder = orderDetail(side: .seller, status: .paid, actions: OrderActionFlags(canShip: true))
        let model = await loadedModel(api)
        #expect(await model.labelURL() == nil)
        #expect(api.labelCalls == 0)
    }

    private func disputedSale(_ actions: OrderActionFlags = OrderActionFlags(canRespondToDispute: true)) -> OrderDetailInfo {
        orderDetail(side: .seller, status: .disputed, actions: actions,
                    dispute: OrderDisputeSummary(id: "d9", status: .open, statusLabel: "Ouvert", reasonLabel: "Article endommagé",
                                                 sellerDeadlineAt: Date(timeIntervalSince1970: 0), resolution: nil))
    }

    @Test func acceptingTheClaimAnswersTheDisputeAndReloads() async {
        let api = FakeOrdersApi()
        api.orderResults = [.success(disputedSale()), .success(orderDetail(side: .seller, status: .refunded))]
        let model = await loadedModel(api)
        #expect(model.memberActions == [.acceptClaim, .contestClaim])

        await model.answerClaim(.accept)
        #expect(api.answers.map(\.disputeId) == ["d9"])
        #expect(api.answers.map(\.answer) == [.accept])
        #expect(model.order?.status == .refunded)
        #expect(model.notice == .success(.disputesAcceptDone))
        #expect(model.busy == nil)
    }

    @Test func contestingSaysTaleedMediates() async {
        let api = FakeOrdersApi()
        api.orderResults = [.success(disputedSale()), .success(disputedSale(OrderActionFlags()))]
        let model = await loadedModel(api)
        await model.answerClaim(.contest)
        #expect(api.answers.map(\.answer) == [.contest])
        #expect(model.notice == .success(.disputesContestDone))
        #expect(model.memberActions.isEmpty)
    }

    @Test func anAnswerThatNoLongerAppliesReloads() async {
        let api = FakeOrdersApi()
        api.orderResults = [.success(disputedSale()), .success(disputedSale(OrderActionFlags()))]
        api.answerResult = .failure(failure(409, .invalidState))
        let model = await loadedModel(api)
        await model.answerClaim(.contest)
        #expect(model.memberActions.isEmpty)
        #expect(model.notice == .error(failure(409, .invalidState)))
    }

    @Test func noAnswerWithoutTheFlagOrADispute() async {
        let api = FakeOrdersApi()
        api.defaultOrder = disputedSale(OrderActionFlags())
        let model = await loadedModel(api)
        await model.answerClaim(.accept)
        // The flag without a dispute to answer: nothing either.
        api.orderResults = [.success(orderDetail(side: .seller, status: .disputed,
                                                 actions: OrderActionFlags(canRespondToDispute: true)))]
        await model.reload()
        await model.answerClaim(.accept)
        #expect(api.answers.isEmpty)
    }
}

// MARK: - Dispute thread

@MainActor
struct SellerDisputeThreadTests {
    @Test func theSellerAnswersFromTheThread() async {
        let api = FakeOrdersApi()
        api.disputeResult = .success(disputeInfo(side: .seller, canRespond: true))
        let model = DisputeThreadViewModel(disputeId: "d1", api: api, upload: uploadOK)
        await model.loadIfNeeded()
        await model.answer(.contest)
        #expect(api.answers.map(\.answer) == [.contest])
        #expect(model.dispute?.status == .underReview)
        #expect(model.dispute?.canRespond == false)
        #expect(model.success == .disputesContestDone)
        #expect(model.answering == nil)
    }

    @Test func acceptingClosesTheThread() async {
        let api = FakeOrdersApi()
        api.disputeResult = .success(disputeInfo(side: .seller, canRespond: true))
        let model = DisputeThreadViewModel(disputeId: "d1", api: api, upload: uploadOK)
        await model.loadIfNeeded()
        await model.answer(.accept)
        #expect(model.dispute?.status == .resolvedRefund)
        #expect(model.dispute?.canPost == false)
        #expect(model.success == .disputesAcceptDone)
    }

    @Test func theBuyerCannotAnswer() async {
        let api = FakeOrdersApi()
        let model = DisputeThreadViewModel(disputeId: "d1", api: api, upload: uploadOK)
        await model.loadIfNeeded()
        await model.answer(.accept)
        #expect(api.answers.isEmpty)
    }

    @Test func aRefusedAnswerReloadsTheThread() async {
        let api = FakeOrdersApi()
        api.disputeResult = .success(disputeInfo(side: .seller, canRespond: true))
        api.answerResult = .failure(failure(409, .invalidState))
        let model = DisputeThreadViewModel(disputeId: "d1", api: api, upload: uploadOK)
        await model.loadIfNeeded()
        api.disputeResult = .success(disputeInfo(status: .underReview, side: .seller, canRespond: false))
        await model.answer(.accept)
        #expect(model.notice == failure(409, .invalidState))
        #expect(model.dispute?.status == .underReview)
        #expect(model.success == nil)
    }
}
