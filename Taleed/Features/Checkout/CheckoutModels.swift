import Foundation

// The app models of checkout and the payment return (screens.md §2 G11, slice D "Checkout" and
// "Paying online"). Every amount, fee and permission comes from the server (screens.md §0.1): the app
// shows `amounts` as they come and never adds anything up.

/// How the parcel travels: to the door (`HOME`) or to a carrier's desk (`STOPDESK`).
enum DeliveryKind: String, CaseIterable, Hashable, Sendable {
    case home = "HOME"
    case stopdesk = "STOPDESK"
}

/// The delivery as the member filled it in so far. A quote takes it unfinished; an order needs it whole.
struct CheckoutDeliveryInput: Equatable, Hashable, Sendable {
    var kind: DeliveryKind
    var wilayaId: Int
    var communeId: Int?
    /// `HOME` only, 200 characters at most.
    var addressLine: String?
    /// `STOPDESK` only.
    var stopdeskId: Int?
}

/// `POST /checkout/quote`: what is bought and how. `listingId` or `bundleId`, never both.
struct CheckoutRequest: Equatable, Hashable, Sendable {
    var listingId: String?
    var bundleId: String?
    var offerId: String?
    var delivery: CheckoutDeliveryInput
    var promoCode: String?
    var useWallet: Bool
    /// The member's pick; nil lets the server take the first method offered.
    var paymentMethod: String?
}

/// `POST /orders`: the quote's body plus who receives the parcel, the total the member agreed to and
/// the id of the tap (`clientId`), sent again as it is on a retry of the same tap.
struct OrderRequest: Equatable, Sendable {
    let request: CheckoutRequest
    let paymentMethod: String?
    let recipientName: String
    let phone: String
    let expectedTotal: Int
    let clientId: String
}

/// One item of the goods (`OrderItem`).
struct CheckoutLine: Identifiable, Equatable, Sendable {
    let listingId: String
    let title: String
    let price: Int
    let imageURL: URL?

    var id: String { listingId }
}

/// What is bought (`goods`): one listing, or a bundle's items still for sale.
struct CheckoutGoodsInfo: Equatable, Sendable {
    let listingId: String
    let bundleId: String?
    /// "Veste en jean", or "Lot · 2 articles" for a bundle.
    let title: String
    let items: [CheckoutLine]
    let listedPrice: Int
    /// The accepted offer the price comes from.
    let offer: AcceptedOfferRef?
    let itemPrice: Int
}

/// The fees of both delivery kinds, side by side. `exact` is false until a commune is picked: they are
/// then the wilaya's highest.
struct DeliveryFees: Equatable, Sendable {
    let home: Int
    let stopdesk: Int
    let exact: Bool

    func fee(for kind: DeliveryKind) -> Int {
        kind == .home ? home : stopdesk
    }
}

/// `amounts` of a quote, line by line.
struct CheckoutAmountsInfo: Equatable, Sendable {
    let itemPrice: Int
    let protectionFee: Int
    let shippingFee: Int
    let subtotal: Int
    let promoDiscount: Int
    let voucherDiscount: Int
    let discount: Int
    let total: Int
    let walletApplied: Int
    let amountDue: Int
    let freeDelivery: Bool
}

/// The kinds of promo codes (`PromoKind`); a kind added after this build is `unknown` (a plain discount).
enum PromoKindValue: Equatable, Sendable {
    case percent, fixed, freeFees, freeDelivery, unknown
}

struct CheckoutPromo: Equatable, Sendable {
    let code: String
    let kind: PromoKindValue
    let value: Int
}

/// A payment method offered right now, labelled by the server.
struct PaymentChoice: Identifiable, Equatable, Sendable {
    /// `chargily`, `slickpay`, `cod`, `mock`.
    let value: String
    let label: String
    let hint: String

    var id: String { value }
    var isCashOnDelivery: Bool { value == PaymentChoice.cashOnDelivery }

    static let cashOnDelivery = "cod"
}

/// What the carrier collects on a cash-on-delivery order.
struct CashCollection: Equatable, Sendable {
    let total: Int
    let deliveryFee: Int
}

/// `POST /checkout/quote`'s answer.
struct CheckoutPricing: Equatable, Sendable {
    let goods: CheckoutGoodsInfo
    let deliveryKind: DeliveryKind?
    let wilaya: CatalogWilaya
    let fees: DeliveryFees
    let amounts: CheckoutAmountsInfo
    let promo: CheckoutPromo?
    /// The code could not be used: the server's localized reason, shown under the field.
    let promoErrorMessage: String?
    let walletBalance: Int
    /// In display order; values this build does not know are left out (never offered).
    let paymentMethods: [PaymentChoice]
    /// The method the quote assumes; nil when the wallet pays it all.
    let paymentMethod: String?
    let cashOnDelivery: CashCollection?

    var isCashOnDelivery: Bool { paymentMethod == PaymentChoice.cashOnDelivery }
}

/// A commune of a wilaya (`GET /wilayas/{id}/communes`).
struct CommuneOption: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
}

/// A carrier's desk (`GET /wilayas/{id}/stopdesks`). `communeId` nil: shown for every commune.
struct StopdeskOption: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let address: String?
    let communeId: Int?
}

/// A saved delivery address (`GET /me/addresses`), the default first.
struct SavedAddress: Identifiable, Equatable, Sendable {
    let id: String
    let recipientName: String
    let phone: String
    let wilaya: CatalogWilaya
    /// Nil on an address saved before communes came from the carrier: ask for the commune again.
    let communeId: Int?
    let commune: String
    let addressLine: String
    let isDefault: Bool
}

/// `POST /me/addresses`: a home address to save after an order.
struct AddressDraft: Hashable, Sendable {
    let recipientName: String
    let phone: String
    let wilayaId: Int
    let communeId: Int
    let addressLine: String
}

/// What `GET /me` gives checkout to start from: the recipient, the phone and the wilaya.
struct CheckoutProfile: Equatable, Sendable {
    let name: String
    let phone: String?
    let wilayaId: Int?
}

/// What checkout shows before a wilaya is known (no quote is possible yet): the goods from the listing
/// or the bundle, and the fee when it applies to the price shown.
struct CheckoutPreview: Equatable, Sendable {
    let title: String
    let items: [CheckoutLine]
    let itemPrice: Int
    /// Nil when the server's fee is not for this price (an accepted offer): "—".
    let protectionFee: Int?
    let isBundle: Bool
    /// The listing or the bundle can no longer be bought (sold, own item, bundle already ordered).
    let canBuy: Bool
    /// The member's own order holds the goods: open it instead.
    let orderId: String?
}

// MARK: - Orders

/// An order's status (`OrderStatus`); a status added after this build is `unknown` (shown by its label).
enum OrderState: Equatable, Sendable {
    case pendingPayment, paid, prepared, shipped, delivered, completed, cancelled, refunded, disputed, unknown
}

/// An order's amounts (`OrderAmounts`).
struct OrderAmountsInfo: Equatable, Sendable {
    let itemPrice: Int
    let protectionFee: Int
    let shippingFee: Int
    /// The promo code's part of the discount.
    let promoDiscount: Int
    /// The referral voucher's part of the discount.
    let voucherDiscount: Int
    let total: Int
    let walletApplied: Int
    let amountDue: Int
}

/// An order as the payment screen shows it (`OrderDetail`, buyer side).
struct OrderPaymentInfo: Identifiable, Equatable, Sendable {
    let id: String
    /// `T-000104`.
    let number: String
    let status: OrderState
    /// "Payée — à expédier", from the server.
    let statusLabel: String
    let title: String
    let imageURL: URL?
    let items: [CheckoutLine]
    let amounts: OrderAmountsInfo
    let cashOnDelivery: CashCollection?
    let payDeadlineAt: Date?
    let shipDeadlineAt: Date?
    /// "Payer maintenant" (`actions.canPay`).
    let canPay: Bool

    /// The listing to go back to.
    var listingId: String? { items.first?.listingId }
}

/// `POST /orders`'s answer.
struct PlacedOrder: Equatable, Sendable {
    let order: OrderPaymentInfo
    /// The gateway's page; nil for cash on delivery, a wallet that paid it all, or a gateway that could
    /// not open a page (the order then waits with "Pay now").
    let paymentURL: URL?
    let replayed: Bool
}
