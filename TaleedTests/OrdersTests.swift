import Foundation
@testable import Taleed
import Testing

// MARK: - Rules

struct OrderRulesTests {
    @Test func buyerButtonsComeOnlyFromActions() {
        #expect(OrderRules.buyerActions(OrderActionFlags()).isEmpty)
        #expect(OrderRules.buyerActions(OrderActionFlags(canPay: true, canCancel: true)) == [.pay, .cancel])
        #expect(OrderRules.buyerActions(OrderActionFlags(awaitingArrival: true, canOpenDispute: true)) == [.awaitingArrival, .openDispute])
        // Confirming wins over the disabled state if both ever came.
        #expect(OrderRules.buyerActions(OrderActionFlags(canConfirmReceipt: true, awaitingArrival: true)) == [.confirmReceipt])
        #expect(OrderRules.buyerActions(OrderActionFlags(canConfirmReceipt: true, canOpenDispute: true, canReview: true))
            == [.confirmReceipt, .review, .openDispute])
        // Seller-only flags never make buyer buttons.
        #expect(OrderRules.buyerActions(OrderActionFlags(canShip: true, canPrintLabel: true, canRespondToDispute: true)).isEmpty)
    }

    @Test func thePayDeadlineReadsByRole() {
        let date = Date(timeIntervalSince1970: 100)
        #expect(OrderRules.notices(for: orderDetail(status: .pendingPayment, payDeadline: date)) == [.payDeadline(date)])
        #expect(OrderRules.notices(for: orderDetail(side: .seller, status: .pendingPayment, payDeadline: date))
            == [.awaitingPayment(date)])
        // A stale deadline on another status says nothing.
        #expect(OrderRules.notices(for: orderDetail(status: .cancelled, payDeadline: date)).isEmpty)
    }

    @Test func theShipDeadlineReadsByRoleAndStatus() {
        let date = Date(timeIntervalSince1970: 100)
        #expect(OrderRules.notices(for: orderDetail(status: .paid, shipDeadline: date)) == [.sellerShipsBy(date, cashOnDelivery: false)])
        let cash = CashCollection(total: 2550, deliveryFee: 0)
        #expect(OrderRules.notices(for: orderDetail(status: .paid, cash: cash, shipDeadline: date))
            == [.sellerShipsBy(date, cashOnDelivery: true), .cashOnDelivery(cash)])
        #expect(OrderRules.notices(for: orderDetail(side: .seller, status: .paid, shipDeadline: date)) == [.shipBy(date)])
        #expect(OrderRules.notices(for: orderDetail(side: .seller, status: .prepared, shipDeadline: date)) == [.dropOffBy(date)])
        #expect(OrderRules.notices(for: orderDetail(status: .shipped, shipDeadline: date)).isEmpty)
    }

    @Test func cashOnDeliveryShowsWhileTheParcelIsOnItsWay() {
        let cash = CashCollection(total: 1822, deliveryFee: 400)
        for status in [OrderState.paid, .prepared, .shipped] {
            #expect(OrderRules.notices(for: orderDetail(status: status, cash: cash)) == [.cashOnDelivery(cash)])
        }
        #expect(OrderRules.notices(for: orderDetail(status: .delivered, cash: cash)).isEmpty)
        #expect(OrderRules.notices(for: orderDetail(status: .paid, cash: CashCollection(total: 0, deliveryFee: 0))).isEmpty)
    }

    @Test func pickupAndAutoRelease() {
        #expect(OrderRules.notices(for: orderDetail(status: .shipped, stopdesk: "Agence Oran", pickupReady: true))
            == [.pickupReady(place: "Agence Oran")])
        // Without a desk name: "commune, wilaya", as the website.
        #expect(OrderRules.notices(for: orderDetail(status: .shipped, pickupReady: true)) == [.pickupReady(place: "Hydra, Alger")])
        let date = Date(timeIntervalSince1970: 5)
        #expect(OrderRules.notices(for: orderDetail(status: .delivered, autoComplete: date)) == [.autoRelease(date)])
    }

    @Test func amountsAreTheServersLines() {
        let plain = OrderRules.amounts(for: orderDetail())
        #expect(plain.lines.map(\.0) == [.itemPrice(bundleCount: nil), .protectionFee, .shippingFee])
        #expect(plain.total == .total)
        #expect(plain.totalAmount == 2550)

        let discounted = OrderMoney(itemPrice: 2500, protectionFee: 175, shippingFee: 600, promoDiscount: 328,
                                    voucherDiscount: 0, total: 2947,
                                    walletApplied: 1405, amountDue: 1542, sellerEarns: 2500)
        let wallet = OrderRules.amounts(for: orderDetail(items: 2, money: discounted))
        #expect(wallet.lines.map(\.0) == [.itemPrice(bundleCount: 2), .protectionFee, .shippingFee, .discount, .total, .walletPaid])
        #expect(wallet.lines.map(\.1) == [2500, 175, 600, -328, 2947, -1405])
        #expect(wallet.total == .remainderDue)
        #expect(wallet.totalAmount == 1542)

        // A referral voucher is its own row, never the promo code's (G11/G12).
        let split = OrderMoney(itemPrice: 2500, protectionFee: 175, shippingFee: 600, promoDiscount: 250, voucherDiscount: 500,
                               total: 2525, walletApplied: 0, amountDue: 2525, sellerEarns: 2500)
        let both = OrderRules.amounts(for: orderDetail(money: split))
        #expect(both.lines.map(\.0) == [.itemPrice(bundleCount: nil), .protectionFee, .shippingFee, .discount, .voucher])
        #expect(both.lines.map(\.1) == [2500, 175, 600, -250, -500])
        let voucherOnly = OrderMoney(itemPrice: 2500, protectionFee: 175, shippingFee: 600, promoDiscount: 0, voucherDiscount: 500,
                                     total: 2775, walletApplied: 0, amountDue: 2775, sellerEarns: 2500)
        #expect(OrderRules.amounts(for: orderDetail(money: voucherOnly)).lines.map(\.0)
            == [.itemPrice(bundleCount: nil), .protectionFee, .shippingFee, .voucher])

        let seller = OrderRules.amounts(for: orderDetail(side: .seller, money: discounted))
        #expect(seller.total == .sellerEarns)
        #expect(seller.totalAmount == 2500)
        #expect(!seller.lines.map(\.0).contains(.walletPaid))
        #expect(OrderRules.headlineAmount(for: orderDetail(side: .seller, money: discounted)) == 2500)
        #expect(OrderRules.headlineAmount(for: orderDetail(money: discounted)) == 2947)
    }

    /// The cash-on-delivery notice as a short title and the amounts under it, in every language.
    @Test func codNoticeSplitsIntoTitleAndBody() {
        let french = OrderText.titled("Paiement à la livraison — le transporteur encaisse 2 255 DA auprès du destinataire.")
        #expect(french.title == "Paiement à la livraison")
        #expect(french.body == "Le transporteur encaisse 2 255 DA auprès du destinataire.")
        let arabic = OrderText.titled("الدفع عند الاستلام — يحصّل الناقل 2.255 د.ج من المستلم.")
        #expect(arabic.title == "الدفع عند الاستلام")
        #expect(arabic.body == "يحصّل الناقل 2.255 د.ج من المستلم.")
        let plain = OrderText.titled("Colis disponible")
        #expect(plain.title == "Colis disponible")
        #expect(plain.body == nil)
    }

    @Test func datesUseLatinDigitsInArabic() {
        let date = Date(timeIntervalSince1970: 1_792_000_000)
        let text = OrderText.date(date, locale: AppLanguage.ar.formattingLocale)
        #expect(text.contains("2026"))
        #expect(!text.unicodeScalars.contains { (0x0660...0x0669).contains($0.value) })
    }

    /// The website's `formatDateTime`: a comma between the date and the time, not "à" / "at".
    @Test func dateTimesAreTheWebsites() {
        let date = Date(timeIntervalSince1970: 1_792_000_000)
        let french = OrderText.dateTime(date, locale: AppLanguage.fr.formattingLocale)
        let english = OrderText.dateTime(date, locale: AppLanguage.en.formattingLocale)
        let arabic = OrderText.dateTime(date, locale: AppLanguage.ar.formattingLocale)
        #expect(french.wholeMatch(of: #/\d{1,2}\u{00A0}[a-zéû.]+\u{00A0}2026, \d{2}:\d{2}/#) != nil, "\(french)")
        #expect(english.wholeMatch(of: #/\d{1,2}\u{00A0}[A-Z][a-z]+\u{00A0}2026, \d{2}:\d{2}/#) != nil, "\(english)")
        #expect(arabic.contains("\u{060C} "))
        #expect(!arabic.unicodeScalars.contains { (0x0660...0x0669).contains($0.value) })
        let englishDate = OrderText.date(date, locale: AppLanguage.en.formattingLocale)
        #expect(englishDate.wholeMatch(of: #/\d{1,2}\u{00A0}[A-Z][a-z]+\u{00A0}2026/#) != nil)
        // A date never breaks inside: no plain space in it.
        #expect(!OrderText.date(date, locale: AppLanguage.fr.formattingLocale).contains(" "))
    }

    @Test func statusTones() {
        #expect(OrderState.pendingPayment.badgeTone == .warning)
        #expect(OrderState.disputed.badgeTone == .warning)
        #expect(OrderState.shipped.badgeTone == .brand)
        #expect(OrderState.completed.badgeTone == .success)
        #expect(OrderState.unknown.badgeTone == .neutral)
    }

    @MainActor @Test func disputeRouteOpensOverTheOrders() {
        let (tab, stack) = AppRouter.canonicalStack(for: .dispute(id: "d1"))
        #expect(tab == .profile)
        #expect(stack == [.orders, .dispute(id: "d1")])
        #expect(AppRoute.dispute(id: "d1").requiresSignIn)
        #expect(AppRoute.dispute(id: "d1").hidesShellTabBar)
        // The payment result follows checkout without a tab bar.
        #expect(AppRoute.orderPayment(OrderPaymentTarget(orderId: "o1")).hidesShellTabBar)
        #expect(!AppRoute.order(id: "o1").hidesShellTabBar)
    }
}

// MARK: - Orders list

@MainActor
struct OrdersListViewModelTests {
    @Test func purchasesLoadFirstWithTheCounters() async {
        let api = FakeOrdersApi()
        let model = OrdersListViewModel(api: api)
        await model.load()
        #expect(model.list.items.map(\.id) == ["1", "2"])
        #expect(model.count(.purchases) == 2)
        #expect(model.count(.sales) == 1)
        #expect(api.listCalls.map(\.0) == [.buyer])
    }

    @Test func salesLoadWhenTheTabIsShown() async {
        let api = FakeOrdersApi()
        let model = OrdersListViewModel(api: api)
        await model.load()
        await model.select(.sales)
        #expect(model.list.items.map(\.id) == ["3"])
        await model.select(.purchases)
        // Already loaded: not asked again.
        #expect(api.listCalls.map(\.0) == [.buyer, .seller])
    }

    @Test func anOrderChangedOnItsScreenShowsItsNewStatus() async {
        let api = FakeOrdersApi()
        let model = OrdersListViewModel(api: api)
        await model.load()
        let changes = OrderChangeCenter()
        let cancelled = orderDetail(id: "2", status: .cancelled, label: "Annulée")
        changes.post(cancelled)
        model.apply(changes)
        #expect(model.list.items.first { $0.id == "2" }?.status == .cancelled)
        #expect(model.list.items.first { $0.id == "2" }?.statusLabel == "Annulée")
        #expect(model.list.items.first { $0.id == "1" }?.status == .paid)
    }

    @Test func theForegroundReloadsQuietlyAfterAWhile() async {
        let api = FakeOrdersApi()
        let model = OrdersListViewModel(api: api)
        await model.load()
        let start = ContinuousClock.now
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start + .seconds(10))
        #expect(api.listCalls.count == 1)
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start + .seconds(120))
        #expect(api.listCalls.count == 2)
        #expect(api.listCalls.last?.1 == true)
    }
}

// MARK: - Order screen

@MainActor
struct OrderDetailViewModelTests {
    @Test func itLoadsAndShowsTheBuyersButtons() async {
        let api = FakeOrdersApi()
        api.defaultOrder = orderDetail(status: .shipped, actions: OrderActionFlags(awaitingArrival: true, canOpenDispute: true))
        let model = OrderDetailViewModel(orderId: "o1", api: api)
        await model.loadIfNeeded()
        #expect(model.order?.status == .shipped)
        #expect(model.memberActions == [.awaitingArrival, .openDispute])
    }

    @Test func theSellerSeesNoBuyerButtons() async {
        let api = FakeOrdersApi()
        api.defaultOrder = orderDetail(side: .seller, actions: OrderActionFlags(canPay: true, canCancel: true))
        let model = OrderDetailViewModel(orderId: "o1", api: api)
        await model.loadIfNeeded()
        #expect(model.memberActions.isEmpty)
    }

    @Test func theSellerCanReviewACompletedSale() async {
        let api = FakeOrdersApi()
        api.defaultOrder = orderDetail(side: .seller, actions: OrderActionFlags(canCancel: true, canReview: true))
        let model = OrderDetailViewModel(orderId: "o1", api: api)
        await model.loadIfNeeded()
        #expect(model.memberActions == [.review])
        #expect(OrderRules.memberActions(OrderActionFlags(canReview: true), side: .unknown).isEmpty)
    }

    @Test func aMissingOrderIsNoLongerAvailable() async {
        let api = FakeOrdersApi()
        api.orderResults = [.failure(failure(404, .notFound))]
        let model = OrderDetailViewModel(orderId: "o1", api: api)
        await model.loadIfNeeded()
        #expect(model.order == nil)
        #expect(model.loadError?.isNotFound == true)
    }

    @Test func confirmingReceiptCompletesTheOrder() async {
        let api = FakeOrdersApi()
        let model = OrderDetailViewModel(orderId: "o1", api: api)
        await model.loadIfNeeded()
        await model.confirmReceipt()
        #expect(api.confirms == 1)
        #expect(model.order?.status == .completed)
        #expect(model.memberActions == [.review])
        #expect(model.notice == .success(.ordersReceiptConfirmed))
        #expect(model.busy == nil)
    }

    @Test func cancellingShowsTheCancelledOrder() async {
        let api = FakeOrdersApi()
        let model = OrderDetailViewModel(orderId: "o1", api: api)
        await model.loadIfNeeded()
        await model.cancel()
        #expect(model.order?.status == .cancelled)
        #expect(model.notice == .success(.ordersCancelled))
    }

    @Test func anActionThatNoLongerAppliesReloadsTheOrder() async {
        let api = FakeOrdersApi()
        let model = OrderDetailViewModel(orderId: "o1", api: api)
        await model.loadIfNeeded()
        api.actionResult = .failure(failure(409, .invalidState))
        api.defaultOrder = orderDetail(status: .shipped)
        await model.cancel()
        #expect(api.orderCalls == 2)
        #expect(model.order?.status == .shipped)
        #expect(model.notice == .error(failure(409, .invalidState)))
    }

    @Test func reloadRules() {
        #expect(OrderDetailViewModel.reloadsAfter(.network))
        #expect(OrderDetailViewModel.reloadsAfter(.server(status: 500)))
        #expect(OrderDetailViewModel.reloadsAfter(failure(409, .alreadyReviewed)))
        #expect(OrderDetailViewModel.reloadsAfter(failure(409, .disputeExists)))
        #expect(!OrderDetailViewModel.reloadsAfter(.rateLimited(retryAfter: 30)))
        #expect(!OrderDetailViewModel.reloadsAfter(failure(400, .invalidRequest)))
    }

    @Test func thePaymentToastFollowsTheSyncedStatus() {
        #expect(OrderDetailViewModel.paymentNotice(status: .paid, attempt: .returnedSuccess)
            == .payment(.checkoutSuccessTitle, kind: .success))
        #expect(OrderDetailViewModel.paymentNotice(status: .pendingPayment, attempt: .returnedSuccess)
            == .payment(.appCheckoutPendingTitle, kind: .info))
        #expect(OrderDetailViewModel.paymentNotice(status: .pendingPayment, attempt: .closed)
            == .payment(.checkoutFailedTitle, kind: .error))
        #expect(OrderDetailViewModel.paymentNotice(status: .cancelled, attempt: .returnedFailure)
            == .payment(.appCheckoutPaymentExpired, kind: .error))
    }

    @Test func payingOpensThePageThenSyncs() async {
        let api = FakeOrdersApi()
        api.defaultOrder = orderDetail(status: .pendingPayment, actions: OrderActionFlags(canPay: true, canCancel: true))
        let model = OrderDetailViewModel(orderId: "o1", api: api, followUpDelay: .zero)
        await model.loadIfNeeded()
        let url = await model.paymentPage()
        #expect(url != nil)
        #expect(model.isInPaymentPage)
        api.syncResults = [orderDetail(status: .paid)]
        await model.paymentPageClosed(callback: URL(string: "taleed://payment-return?kind=order&id=o1&result=success"))
        #expect(!model.isInPaymentPage)
        #expect(model.order?.status == .paid)
        #expect(model.notice == .payment(.checkoutSuccessTitle, kind: .success))
    }

    @Test func aLateConfirmationIsSyncedAgain() async {
        let api = FakeOrdersApi()
        api.defaultOrder = orderDetail(status: .pendingPayment, actions: OrderActionFlags(canPay: true))
        let model = OrderDetailViewModel(orderId: "o1", api: api, followUpDelay: .zero)
        await model.loadIfNeeded()
        api.syncResults = [orderDetail(status: .pendingPayment), orderDetail(status: .paid)]
        await model.paymentPageClosed(callback: URL(string: "taleed://payment-return?kind=order&id=o1&result=success"))
        #expect(api.syncCalls == 2)
        #expect(model.order?.status == .paid)
    }

    @Test func noPayButtonNoPage() async {
        let api = FakeOrdersApi()
        let model = OrderDetailViewModel(orderId: "o1", api: api)
        await model.loadIfNeeded()
        #expect(await model.paymentPage() == nil)
    }
}
