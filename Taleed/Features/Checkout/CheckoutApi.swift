import SwiftUI
import TaleedAPI

/// The calls of checkout and the payment return (screens.md §2 G11, slice D).
@MainActor
protocol CheckoutApi: AnyObject {
    /// `GET /me`: the recipient's name, phone and wilaya to start from.
    func checkoutProfile() async throws(ApiError) -> CheckoutProfile
    /// `GET /me/addresses`: the default first, then the most recent.
    func savedAddresses() async throws(ApiError) -> [SavedAddress]
    /// `GET /wilayas/{id}/communes`.
    func communes(wilayaId: Int) async throws(ApiError) -> [CommuneOption]
    /// `GET /wilayas/{id}/stopdesks`; may be empty.
    func stopdesks(wilayaId: Int) async throws(ApiError) -> [StopdeskOption]
    /// `POST /checkout/quote`: nothing is reserved. Repeated freely.
    func quote(_ request: CheckoutRequest) async throws(ApiError) -> CheckoutPricing
    /// `POST /orders`. A retry with the same `clientId` returns the first order (`replayed`).
    func placeOrder(_ order: OrderRequest) async throws(ApiError) -> PlacedOrder
    /// `POST /orders/{id}/payment/sync`: asks the gateway and confirms a paid order. Repeated freely.
    func syncPayment(orderId: String) async throws(ApiError) -> OrderPaymentInfo
    /// `POST /orders/{id}/payment`: a new payment page for an order that waits for payment.
    func payOrder(orderId: String) async throws(ApiError) -> URL?
    /// `POST /me/addresses`. Not idempotent: never repeated on its own.
    func saveAddress(_ address: AddressDraft) async throws(ApiError) -> SavedAddress
}

extension GeneratedTaleedApi: CheckoutApi {
    func checkoutProfile() async throws(ApiError) -> CheckoutProfile {
        let me = try await caller.call(.read) { try await AccountAPI.getMe(apiConfiguration: $0) }
        return CheckoutProfile(name: me.name, phone: me.phone, wilayaId: me.wilaya?.id)
    }

    func savedAddresses() async throws(ApiError) -> [SavedAddress] {
        let list = try await caller.call(.read) { try await AddressesAPI.listAddresses(apiConfiguration: $0) }
        return list.items.map(SavedAddress.init)
    }

    func communes(wilayaId: Int) async throws(ApiError) -> [CommuneOption] {
        let list = try await caller.call(.read) { try await ReferenceAPI.listCommunes(id: wilayaId, apiConfiguration: $0) }
        return list.items.map { CommuneOption(id: $0.id, name: $0.name) }
    }

    func stopdesks(wilayaId: Int) async throws(ApiError) -> [StopdeskOption] {
        let list = try await caller.call(.read) { try await ReferenceAPI.listStopdesks(id: wilayaId, apiConfiguration: $0) }
        return list.items.map { StopdeskOption(id: $0.id, name: $0.name, address: $0.address, communeId: $0.communeId) }
    }

    func quote(_ request: CheckoutRequest) async throws(ApiError) -> CheckoutPricing {
        let body = CheckoutQuoteRequest(request)
        // A quote reserves nothing: repeated freely (slice D, Retrying), so it retries like a read.
        let quote = try await caller.call(.read) {
            try await CheckoutAPI.quoteCheckout(checkoutQuoteRequest: body, apiConfiguration: $0)
        }
        return CheckoutPricing(quote)
    }

    func placeOrder(_ order: OrderRequest) async throws(ApiError) -> PlacedOrder {
        let body = OrderCreate(order)
        // The member's tap: never repeated on its own; the member's own retry sends the same `clientId`.
        let placed = try await caller.call(.write) { try await CheckoutAPI.placeOrder(orderCreate: body, apiConfiguration: $0) }
        return PlacedOrder(order: OrderPaymentInfo(placed.order), paymentURL: URL(apiString: placed.paymentUrl),
                           replayed: placed.replayed)
    }

    func syncPayment(orderId: String) async throws(ApiError) -> OrderPaymentInfo {
        // Repeated freely (slice D, Retrying).
        let order = try await caller.call(.read) { try await OrdersAPI.syncOrderPayment(id: orderId, apiConfiguration: $0) }
        return OrderPaymentInfo(order)
    }

    func payOrder(orderId: String) async throws(ApiError) -> URL? {
        // Each call opens a new payment page: the member's tap only.
        let payment = try await caller.call(.write) { try await OrdersAPI.payOrder(id: orderId, apiConfiguration: $0) }
        return URL(apiString: payment.paymentUrl)
    }

    func saveAddress(_ address: AddressDraft) async throws(ApiError) -> SavedAddress {
        let body = AddressCreate(recipientName: address.recipientName, phone: address.phone, wilayaId: address.wilayaId,
                                 communeId: address.communeId, addressLine: address.addressLine)
        let saved = try await caller.call(.write) { try await AddressesAPI.createAddress(addressCreate: body, apiConfiguration: $0) }
        return SavedAddress(saved)
    }
}

/// What checkout and the payment screen need. Set once at the root (`AppRootView`). The listing and
/// the bundle give the goods before a wilaya is known.
struct CheckoutDependencies {
    let checkout: any CheckoutApi
    let listings: any ListingDetailApi
    let bundles: any BundlesApi
}

private struct CheckoutDependenciesKey: EnvironmentKey {
    static var defaultValue: CheckoutDependencies? { nil }
}

extension EnvironmentValues {
    var checkoutDependencies: CheckoutDependencies? {
        get { self[CheckoutDependenciesKey.self] }
        set { self[CheckoutDependenciesKey.self] = newValue }
    }
}

// MARK: - Mapping

private extension CheckoutQuoteRequest {
    init(_ request: CheckoutRequest) {
        self.init(
            listingId: request.listingId,
            bundleId: request.bundleId,
            offerId: request.offerId,
            delivery: CheckoutDelivery(request.delivery),
            promoCode: request.promoCode,
            useWallet: request.useWallet,
            paymentMethod: request.paymentMethod.flatMap(PaymentMethod.init(rawValue:))
        )
    }
}

private extension OrderCreate {
    init(_ order: OrderRequest) {
        let request = order.request
        self.init(
            listingId: request.listingId,
            bundleId: request.bundleId,
            offerId: request.offerId,
            delivery: CheckoutDelivery(request.delivery),
            promoCode: request.promoCode,
            useWallet: request.useWallet,
            paymentMethod: order.paymentMethod.flatMap(PaymentMethod.init(rawValue:)),
            recipientName: order.recipientName,
            phone: order.phone,
            expectedTotal: order.expectedTotal,
            clientId: order.clientId
        )
    }
}

private extension CheckoutDelivery {
    init(_ delivery: CheckoutDeliveryInput) {
        self.init(
            type: delivery.kind == .home ? .home : .stopdesk,
            wilayaId: delivery.wilayaId,
            communeId: delivery.communeId,
            addressLine: delivery.kind == .home ? delivery.addressLine : nil,
            stopdeskId: delivery.kind == .stopdesk ? delivery.stopdeskId : nil
        )
    }
}

extension CheckoutPricing {
    init(_ quote: CheckoutQuote) {
        let promo = quote.promo.map { CheckoutPromo(code: $0.code, kind: PromoKindValue($0.kind), value: $0.value) }
        let amounts = quote.amounts
        self.init(
            goods: CheckoutGoodsInfo(
                listingId: quote.goods.listingId,
                bundleId: quote.goods.bundleId,
                title: quote.goods.title,
                items: quote.goods.items.map(CheckoutLine.init),
                listedPrice: quote.goods.listedPrice,
                offer: quote.goods.offer.map { AcceptedOfferRef(id: $0.id, amount: $0.amount) },
                itemPrice: quote.goods.itemPrice
            ),
            deliveryKind: DeliveryKind(quote.delivery.type),
            wilaya: CatalogWilaya(id: quote.delivery.wilaya.id, name: quote.delivery.wilaya.name),
            fees: DeliveryFees(home: quote.fees.home, stopdesk: quote.fees.stopdesk, exact: quote.fees.exact),
            amounts: CheckoutAmountsInfo(
                itemPrice: amounts.itemPrice, protectionFee: amounts.protectionFee, shippingFee: amounts.shippingFee,
                subtotal: amounts.subtotal, promoDiscount: amounts.promoDiscount, voucherDiscount: amounts.voucherDiscount,
                discount: amounts.discount, total: amounts.total, walletApplied: amounts.walletApplied,
                amountDue: amounts.amountDue, freeDelivery: amounts.freeDelivery
            ),
            promo: promo,
            promoErrorMessage: quote.promoError?.message,
            walletBalance: quote.walletBalance,
            // An unknown method is never offered (api-guide.md, Compatibility).
            paymentMethods: quote.paymentMethods.compactMap {
                $0.value == .unknownDefaultOpenApi ? nil : PaymentChoice(value: $0.value.rawValue, label: $0.label, hint: $0.hint)
            },
            paymentMethod: quote.paymentMethod.flatMap { $0 == .unknownDefaultOpenApi ? nil : $0.rawValue },
            cashOnDelivery: quote.cashOnDelivery.map { CashCollection(total: $0.total, deliveryFee: $0.deliveryFee) }
        )
    }
}

private extension DeliveryKind {
    init?(_ type: DeliveryType) {
        switch type {
        case .home: self = .home
        case .stopdesk: self = .stopdesk
        case .unknownDefaultOpenApi: return nil
        }
    }
}

private extension PromoKindValue {
    init(_ kind: PromoKind) {
        self = switch kind {
        case .percent: .percent
        case .fixed: .fixed
        case .freeFees: .freeFees
        case .freeDelivery: .freeDelivery
        case .unknownDefaultOpenApi: .unknown
        }
    }
}

private extension CheckoutLine {
    init(_ item: OrderItem) {
        self.init(listingId: item.listingId, title: item.title, price: item.price, imageURL: URL(apiString: item.imageUrl))
    }
}

private extension SavedAddress {
    init(_ address: Address) {
        self.init(id: address.id, recipientName: address.recipientName, phone: address.phone,
                  wilaya: CatalogWilaya(id: address.wilaya.id, name: address.wilaya.name), communeId: address.communeId,
                  commune: address.commune, addressLine: address.addressLine, isDefault: address.isDefault)
    }
}

extension OrderPaymentInfo {
    init(_ order: OrderDetail) {
        self.init(
            id: order.id,
            number: order.number,
            status: OrderState(order.status),
            statusLabel: order.statusLabel,
            title: order.title,
            imageURL: URL(apiString: order.imageUrl),
            items: order.items.map(CheckoutLine.init),
            amounts: OrderAmountsInfo(
                itemPrice: order.amounts.itemPrice, protectionFee: order.amounts.protectionFee,
                shippingFee: order.amounts.shippingFee, discount: order.amounts.discount, total: order.amounts.total,
                walletApplied: order.amounts.walletApplied, amountDue: order.amounts.amountDue
            ),
            cashOnDelivery: order.cashOnDelivery.map { CashCollection(total: $0.total, deliveryFee: $0.deliveryFee) },
            payDeadlineAt: order.payDeadlineAt,
            shipDeadlineAt: order.shipDeadlineAt,
            canPay: order.actions.canPay
        )
    }
}

private extension OrderState {
    init(_ status: OrderStatus) {
        self = switch status {
        case .pendingPayment: .pendingPayment
        case .paid: .paid
        case .prepared: .prepared
        case .shipped: .shipped
        case .delivered: .delivered
        case .completed: .completed
        case .cancelled: .cancelled
        case .refunded: .refunded
        case .disputed: .disputed
        case .unknownDefaultOpenApi: .unknown
        }
    }
}
