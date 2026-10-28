import Foundation
@testable import Taleed
import Testing

// MARK: - Fixtures

func fixturePricing(
    itemPrice: Int = 3000, fee: Int = 200, shipping: Int = 600, promoDiscount: Int = 0, voucherDiscount: Int = 0,
    exact: Bool = true, promo: CheckoutPromo? = nil,
    promoError: String? = nil, methods: [String] = ["mock", "cod"], method: String? = "mock",
    cash: CashCollection? = nil, bundleId: String? = nil, items: Int = 1
) -> CheckoutPricing {
    let total = max(0, itemPrice + fee + shipping - promoDiscount - voucherDiscount)
    return CheckoutPricing(
        goods: CheckoutGoodsInfo(
            listingId: "l1", bundleId: bundleId, title: "Veste",
            items: (0..<items).map { CheckoutLine(listingId: "l\($0 + 1)", title: "Item \($0)", price: 1000, imageURL: nil) },
            listedPrice: itemPrice, offer: nil, itemPrice: itemPrice
        ),
        deliveryKind: .home, wilaya: CatalogWilaya(id: 31, name: "Oran"),
        fees: DeliveryFees(home: 600, stopdesk: 400, exact: exact),
        amounts: CheckoutAmountsInfo(
            itemPrice: itemPrice, protectionFee: fee, shippingFee: shipping, subtotal: itemPrice + fee + shipping,
            promoDiscount: promoDiscount, voucherDiscount: voucherDiscount, discount: promoDiscount + voucherDiscount,
            total: total, amountDue: total, freeDelivery: false
        ),
        promo: promo, promoErrorMessage: promoError,
        paymentMethods: methods.map { PaymentChoice(value: $0, label: $0, hint: "") },
        paymentMethod: method, cashOnDelivery: cash
    )
}

func fixtureOrder(status: OrderState = .paid, cash: CashCollection? = nil, total: Int = 3800, walletApplied: Int = 0,
                  canPay: Bool = false) -> OrderPaymentInfo {
    OrderPaymentInfo(
        id: "o1", number: "T-000104", status: status, statusLabel: "Payée", title: "Veste", imageURL: nil,
        items: [CheckoutLine(listingId: "l1", title: "Veste", price: 3000, imageURL: nil)],
        amounts: OrderAmountsInfo(itemPrice: 3000, protectionFee: 200, shippingFee: 600, promoDiscount: 0, voucherDiscount: 0,
                                  total: total,
                                  walletApplied: walletApplied, amountDue: total - walletApplied),
        cashOnDelivery: cash, payDeadlineAt: nil, shipDeadlineAt: nil, canPay: canPay
    )
}

func completeForm() -> CheckoutFormState {
    var form = CheckoutFormState()
    form.recipientName = "Karim Haddad"
    form.phone = "0550 12 34 56"
    form.wilayaId = 31
    form.communeId = 31001
    form.addressLine = "12 rue des Oliviers"
    return form
}

@MainActor
final class FakeCheckoutApi: CheckoutApi {
    var profile: Result<CheckoutProfile, Taleed.ApiError> = .success(CheckoutProfile(name: "Karim Haddad", phone: "0550123456",
                                                                                     wilayaId: 31))
    var addresses: [SavedAddress] = []
    var communeList: [CommuneOption] = [CommuneOption(id: 31001, name: "Oran")]
    var deskList: [StopdeskOption] = []
    var quotes: [Result<CheckoutPricing, Taleed.ApiError>] = []
    var quote: Result<CheckoutPricing, Taleed.ApiError> = .success(fixturePricing())
    var orders: [Result<PlacedOrder, Taleed.ApiError>] = []
    var sync: Result<OrderPaymentInfo, Taleed.ApiError> = .success(fixtureOrder())
    var syncs: [Result<OrderPaymentInfo, Taleed.ApiError>] = []
    var payment: Result<URL?, Taleed.ApiError> = .success(URL(string: "https://pay.example/1"))
    var save: Result<SavedAddress, Taleed.ApiError>?
    var ownOrderAwaitsPayment: Result<Bool, Taleed.ApiError> = .success(true)
    /// Per wilaya, a call waits here until the test resumes it (out-of-order answers).
    var communeGates: [Int: CheckedContinuation<Void, Never>] = [:]
    var gatedWilayas: Set<Int> = []
    private(set) var communeCalls: [Int] = []
    private(set) var deskCalls: [Int] = []
    private(set) var quoteRequests: [CheckoutRequest] = []
    private(set) var orderRequests: [OrderRequest] = []
    private(set) var saved: [AddressDraft] = []
    private(set) var syncCalls = 0

    func checkoutProfile() async throws(Taleed.ApiError) -> CheckoutProfile { try profile.get() }
    func savedAddresses() async throws(Taleed.ApiError) -> [SavedAddress] { addresses }
    func communes(wilayaId: Int) async throws(Taleed.ApiError) -> [CommuneOption] {
        communeCalls.append(wilayaId)
        if gatedWilayas.contains(wilayaId) {
            await withCheckedContinuation { communeGates[wilayaId] = $0 }
        }
        return communeList.filter { $0.id / 1000 == wilayaId }
    }

    func stopdesks(wilayaId: Int) async throws(Taleed.ApiError) -> [StopdeskOption] {
        deskCalls.append(wilayaId)
        return deskList.filter { ($0.communeId ?? wilayaId * 1000) / 1000 == wilayaId }
    }

    func isOwnOrderAwaitingPayment(orderId: String) async throws(Taleed.ApiError) -> Bool { try ownOrderAwaitsPayment.get() }

    func quote(_ request: CheckoutRequest) async throws(Taleed.ApiError) -> CheckoutPricing {
        quoteRequests.append(request)
        if !quotes.isEmpty { return try quotes.removeFirst().get() }
        return try quote.get()
    }

    func placeOrder(_ order: OrderRequest) async throws(Taleed.ApiError) -> PlacedOrder {
        orderRequests.append(order)
        if !orders.isEmpty { return try orders.removeFirst().get() }
        return PlacedOrder(order: fixtureOrder(status: .pendingPayment, canPay: true), paymentURL: URL(string: "https://pay.example/1"),
                           replayed: false)
    }

    func syncPayment(orderId: String) async throws(Taleed.ApiError) -> OrderPaymentInfo {
        syncCalls += 1
        if !syncs.isEmpty { return try syncs.removeFirst().get() }
        return try sync.get()
    }

    func payOrder(orderId: String) async throws(Taleed.ApiError) -> URL? { try payment.get() }

    func saveAddress(_ address: AddressDraft) async throws(Taleed.ApiError) -> SavedAddress {
        saved.append(address)
        if let save { return try save.get() }
        return SavedAddress(id: "a9", recipientName: address.recipientName, phone: address.phone,
                            wilaya: CatalogWilaya(id: address.wilayaId, name: "Oran"), communeId: address.communeId,
                            commune: "Oran", addressLine: address.addressLine, isDefault: false)
    }
}

// MARK: - Rules

struct CheckoutRulesTests {
    @Test func phoneIsZeroThenEightOrNineDigits() {
        #expect(CheckoutRules.isValidPhone("0550 12 34 56"))
        #expect(CheckoutRules.isValidPhone("0550123456"))
        #expect(CheckoutRules.isValidPhone("021.23.45.67"))
        #expect(CheckoutRules.isValidPhone(" 0550-12-34-56 "))
        #expect(!CheckoutRules.isValidPhone("123"))
        #expect(!CheckoutRules.isValidPhone("550123456"))
        #expect(!CheckoutRules.isValidPhone("05501234567"))
        #expect(!CheckoutRules.isValidPhone("+213550123456"))
        #expect(!CheckoutRules.isValidPhone("0550 12 34 5a"))
        #expect(!CheckoutRules.isValidPhone(""))
    }

    @Test func arabicDigitsBecomeLatin() {
        #expect(CheckoutRules.latinDigits("٠٥٥٠ ١٢ ٣٤ ٥٦") == "0550 12 34 56")
        #expect(CheckoutRules.latinDigits("۰۵۵۰") == "0550")
        #expect(CheckoutRules.isValidPhone(CheckoutRules.latinDigits("٠٥٥٠١٢٣٤٥٦")))
    }

    @Test func recipientNameIsTwoToEightyCharacters() {
        #expect(!CheckoutRules.isValidRecipientName(" K "))
        #expect(CheckoutRules.isValidRecipientName("Ka"))
        #expect(CheckoutRules.isValidRecipientName(String(repeating: "a", count: 80)))
        #expect(!CheckoutRules.isValidRecipientName(String(repeating: "a", count: 81)))
    }

    @Test func desksFollowTheCommuneAndKeepThoseWithoutOne() {
        let desks = [StopdeskOption(id: 1, name: "A", address: nil, communeId: 16001),
                     StopdeskOption(id: 2, name: "B", address: nil, communeId: 16002),
                     StopdeskOption(id: 3, name: "C", address: nil, communeId: nil)]
        #expect(CheckoutRules.desks(desks, communeId: nil).isEmpty)
        #expect(CheckoutRules.desks(desks, communeId: 16001).map(\.id) == [1, 3])
    }
}

struct CheckoutFormTests {
    @Test func aCompleteFormNeedsTheCommuneForBothKinds() {
        var form = completeForm()
        #expect(form.isComplete)
        form.communeId = nil
        #expect(!form.isComplete)
        form = completeForm()
        form.kind = .stopdesk
        #expect(!form.isComplete)
        form.stopdeskId = 7
        #expect(form.isComplete)
        form.addressLine = ""
        #expect(form.isComplete)
    }

    @Test func fieldChecks() {
        var form = completeForm()
        form.phone = "123"
        #expect(form.phoneError == .phoneInvalid)
        form.recipientName = "K"
        #expect(form.recipientNameError == .nameLength(min: 2, max: 80))
    }

    @Test func theQuoteSendsTheGoodsAndOnlyTheFieldsOfTheKind() throws {
        var form = completeForm()
        form.stopdeskId = 7
        let listing = try #require(form.request(for: CheckoutTarget(listingId: "l1", offerId: "o1")))
        #expect(listing.listingId == "l1")
        #expect(listing.bundleId == nil)
        #expect(listing.offerId == "o1")
        #expect(listing.delivery.addressLine == "12 rue des Oliviers")
        #expect(listing.delivery.stopdeskId == nil)

        form.kind = .stopdesk
        let bundle = try #require(form.request(for: CheckoutTarget(listingId: "l1", bundleId: "b1")))
        #expect(bundle.listingId == nil)
        #expect(bundle.bundleId == "b1")
        #expect(bundle.delivery.addressLine == nil)
        #expect(bundle.delivery.stopdeskId == 7)

        form.wilayaId = nil
        #expect(form.request(for: CheckoutTarget(listingId: "l1")) == nil)
    }

    @Test func aNewWilayaClearsTheCommuneAndTheDesk() {
        var form = completeForm()
        form.stopdeskId = 4
        form.selectWilaya(16)
        #expect(form.communeId == nil)
        #expect(form.stopdeskId == nil)
        form.communeId = 16001
        form.stopdeskId = 4
        form.selectCommune(16002)
        #expect(form.stopdeskId == nil)
    }

    @Test func onlyANewHomeAddressIsOfferedForSaving() {
        let form = completeForm()
        let draft = form.unsavedAddress(among: [])
        #expect(draft == AddressDraft(recipientName: "Karim Haddad", phone: "0550 12 34 56", wilayaId: 31, communeId: 31001,
                                      addressLine: "12 rue des Oliviers"))
        let saved = SavedAddress(id: "a1", recipientName: "Karim Haddad", phone: "0550123456", wilaya: CatalogWilaya(id: 31, name: "Oran"),
                                 communeId: 31001, commune: "Oran", addressLine: "12 rue des Oliviers", isDefault: true)
        #expect(form.unsavedAddress(among: [saved]) == nil)
        var stopdesk = form
        stopdesk.kind = .stopdesk
        stopdesk.stopdeskId = 3
        #expect(stopdesk.unsavedAddress(among: []) == nil)
    }

    @Test func aSavedAddressWithoutCommuneAsksForItAgain() {
        var form = CheckoutFormState()
        form.apply(SavedAddress(id: "a1", recipientName: "K H", phone: "0550123456", wilaya: CatalogWilaya(id: 16, name: "Alger"),
                                communeId: nil, commune: "", addressLine: "Rue 1", isDefault: true))
        #expect(form.wilayaId == 16)
        #expect(form.communeId == nil)
        #expect(!form.isComplete)
    }
}

// MARK: - Summary and button

struct CheckoutSummaryTests {
    @Test func linesFollowTheAmounts() {
        let plain = CheckoutSummary.rows(for: fixturePricing(exact: false))
        #expect(plain.map(\.kind) == [.item(bundleCount: nil), .protectionFee, .shipping(estimate: true)])

        let full = CheckoutSummary.rows(for: fixturePricing(promoDiscount: 380, voucherDiscount: 500,
                                                            promo: CheckoutPromo(code: "WELCOME", kind: .percent, value: 10),
                                                            bundleId: "b1", items: 2))
        // No stored balance (slice H): the voucher is the last line, the total is what is paid.
        #expect(full.map(\.kind) == [.item(bundleCount: 2), .protectionFee, .shipping(estimate: false),
                                     .promo(kind: .percent, code: "WELCOME"), .voucher])
        #expect(full.first { $0.kind == .voucher }?.amount == -500)
        #expect(fixturePricing(promoDiscount: 380, voucherDiscount: 500).amounts.amountDue == 2920)
    }

    @Test func thePaymentListShowsOnlyWithAChoiceAndSomethingToPay() {
        #expect(CheckoutSummary.showsPaymentMethods(fixturePricing()))
        #expect(!CheckoutSummary.showsPaymentMethods(fixturePricing(methods: ["mock"])))
        // Nothing to pay (a promo that covers it all): no list.
        #expect(!CheckoutSummary.showsPaymentMethods(fixturePricing(promoDiscount: 3800, method: nil)))
    }

    @Test func theButtonFollowsTheQuote() {
        #expect(CheckoutAction.of(nil) == .pending)
        #expect(CheckoutAction.of(fixturePricing()) == .pay(amount: 3800))
        #expect(CheckoutAction.of(fixturePricing(promoDiscount: 3800, method: nil)) == .confirm)
        #expect(CheckoutAction.of(fixturePricing(voucherDiscount: 500)) == .pay(amount: 3300))
        #expect(CheckoutAction.of(fixturePricing(method: "cod", cash: CashCollection(total: 3800, deliveryFee: 600)))
            == .cashOnDelivery(amount: 3800))
    }
}

// MARK: - Payment result

struct PaymentOutcomeTests {
    @Test func theStatusAndTheAttemptDecide() {
        #expect(PaymentOutcome.of(fixtureOrder(), attempt: .returnedSuccess) == .paid)
        #expect(PaymentOutcome.of(fixtureOrder(status: .pendingPayment), attempt: .returnedSuccess) == .awaitingConfirmation)
        #expect(PaymentOutcome.of(fixtureOrder(status: .pendingPayment), attempt: .returnedFailure) == .failed)
        #expect(PaymentOutcome.of(fixtureOrder(status: .pendingPayment), attempt: .closed) == .failed)
        #expect(PaymentOutcome.of(fixtureOrder(status: .pendingPayment), attempt: .none) == .awaitingPayment)
        #expect(PaymentOutcome.of(fixtureOrder(status: .cancelled), attempt: .closed) == .expired)
        #expect(PaymentOutcome.of(fixtureOrder(status: .unknown), attempt: .none) == .other)
        let cash = CashCollection(total: 1910, deliveryFee: 600)
        #expect(PaymentOutcome.of(fixtureOrder(cash: cash), attempt: .none) == .confirmed(cash: cash))
        // An order placed before slice H that the old stored balance paid in full.
        #expect(PaymentOutcome.of(fixtureOrder(walletApplied: 3800), attempt: .none) == .confirmed(cash: nil))
    }

    @Test func theReturnLinkSaysHowThePageEnded() {
        #expect(OrderPaymentViewModel.attempt(from: URL(string: "taleed://payment-return?kind=order&id=o1&result=success"))
            == .returnedSuccess)
        #expect(OrderPaymentViewModel.attempt(from: URL(string: "taleed://payment-return?kind=order&id=o1&result=failure"))
            == .returnedFailure)
        #expect(OrderPaymentViewModel.attempt(from: nil) == .closed)
    }

    @Test func daysToShipRoundToWholeDays() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(daysUntil(now.addingTimeInterval(5 * 86_400 - 60), from: now) == 5)
        #expect(daysUntil(now.addingTimeInterval(60), from: now) == 1)
        #expect(daysUntil(nil, from: now) == nil)
    }

    /// The saved address on one line never says the commune or the wilaya twice.
    @Test func savedAddressTitleLeavesOutRepeatedPlaces() {
        func address(_ line: String, commune: String, wilaya: String) -> SavedAddress {
            SavedAddress(id: "a", recipientName: "Lina K", phone: "0661000000", wilaya: CatalogWilaya(id: 25, name: wilaya),
                         communeId: 1, commune: commune, addressLine: line, isDefault: true)
        }
        #expect(CheckoutRules.addressTitle(address("7 rue des Martyrs, Constantine", commune: "Constantine", wilaya: "Constantine"))
            == "7 rue des Martyrs, Constantine")
        #expect(CheckoutRules.addressTitle(address("7 rue des Martyrs", commune: "Constantine", wilaya: "Constantine"))
            == "7 rue des Martyrs, Constantine")
        #expect(CheckoutRules.addressTitle(address("68 rue des Martyrs, Hydra", commune: "Hydra", wilaya: "Alger"))
            == "68 rue des Martyrs, Hydra, Alger")
        #expect(CheckoutRules.addressTitle(address("12 bd Zighout", commune: "El Khroub", wilaya: "Constantine"))
            == "12 bd Zighout, El Khroub, Constantine")
        #expect(CheckoutRules.addressTitle(address("5 rue Hasni, BEJAIA", commune: "Béjaïa", wilaya: "Béjaïa"))
            == "5 rue Hasni, BEJAIA, Béjaïa")
        #expect(CheckoutRules.addressTitle(address("5 rue Hasni, Bejaia", commune: "Bejaia", wilaya: "Béjaïa"))
            == "5 rue Hasni, Bejaia")
        // Only a whole name: "Ain Oulmene" does not end with the wilaya "Mene".
        #expect(CheckoutRules.addressTitle(address("2 cité 300", commune: "Ain Oulmene", wilaya: "Mene"))
            == "2 cité 300, Ain Oulmene, Mene")
    }
}
