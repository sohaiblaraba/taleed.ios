import Foundation

// The app models of the orders screens (screens.md §2 G12 and §7 G12/G13, slice D "Orders",
// "Disputes", "Reviews"). Labels (`statusLabel`, step labels, dispute and role labels) come from the
// server; values this build does not know decode as `.unknown` (api-guide.md, Compatibility); every
// button comes from the server's `actions`, never from `status`.

/// The signed-in member's side of an order.
enum OrderSide: Equatable, Sendable {
    case buyer, seller, unknown
}

/// The two tabs of the orders list (`GET /orders?role=`).
enum OrdersTab: Int, CaseIterable, Sendable {
    case purchases, sales

    var side: OrderSide { self == .purchases ? .buyer : .seller }
}

/// `counts` of `GET /orders`: the same whatever the filter, for the tab counters.
struct OrderTabCounts: Equatable, Sendable {
    let purchases: Int
    let sales: Int

    subscript(tab: OrdersTab) -> Int {
        tab == .purchases ? purchases : sales
    }
}

/// A row of the orders list (`OrderSummary`).
struct OrderRow: Identifiable, Equatable, Sendable {
    let id: String
    /// `T-000104`.
    let number: String
    let side: OrderSide
    var status: OrderState
    /// "Payée — à expédier", as the server words it.
    var statusLabel: String
    let title: String
    let imageURL: URL?
    /// Nil when the other member deleted their account ("Compte supprimé").
    let counterpart: MemberRef?
    let createdAt: Date
    /// Above 1 for a bundle ("×2").
    let itemCount: Int
    /// What the order is worth to the member: the total paid, or the item price earned.
    let amount: Int
}

/// A page of the orders list with the tab counters.
struct OrdersPage: Sendable {
    let page: Page<OrderRow>
    let counts: OrderTabCounts
}

/// An item of an order (one, or each item of a bundle) at the price it was bought at.
struct OrderLine: Identifiable, Equatable, Sendable {
    let listingId: String
    let title: String
    let price: Int
    let imageURL: URL?

    var id: String { listingId }
}

/// `amounts` of an order.
struct OrderMoney: Equatable, Sendable {
    let itemPrice: Int
    let protectionFee: Int
    let shippingFee: Int
    let discount: Int
    let total: Int
    let walletApplied: Int
    let amountDue: Int
    /// What the seller receives: discounts are paid by Taleed.
    let sellerEarns: Int
}

enum OrderDeliveryKind: Equatable, Sendable {
    case home, stopdesk, unknown
}

/// Where the parcel goes: a copy made when ordering.
struct OrderDeliveryInfo: Equatable, Sendable {
    let kind: OrderDeliveryKind
    let recipientName: String
    let phone: String
    let wilaya: String
    let commune: String
    let addressLine: String?
    let stopdeskName: String?
    /// Set once the parcel exists.
    let tracking: String?

    /// The pick-up point of a parcel waiting there: the desk, otherwise "commune, wilaya" (website).
    var pickupPlace: String {
        stopdeskName ?? "\(commune), \(wilaya)"
    }
}

/// A milestone of the timeline, with the server's label. A step the carrier skipped counts as done
/// once a later one is, without a date of its own.
struct OrderStepInfo: Identifiable, Equatable, Sendable {
    let id: Int
    let label: String
    let done: Bool
    let date: Date?
}

/// A scan the carrier reported, in its own words.
struct CarrierScan: Identifiable, Equatable, Sendable {
    let id: Int
    let status: String
    let place: String?
    let date: Date
}

/// The buttons the server offers on an order (`actions`).
struct OrderActionFlags: Equatable, Sendable {
    var canPay = false
    var canCancel = false
    var canShip = false
    var canReplaceTestLabel = false
    var canPrintLabel = false
    var canConfirmReceipt = false
    var awaitingArrival = false
    var canOpenDispute = false
    var canRespondToDispute = false
    var canReview = false
}

enum DisputeState: Equatable, Sendable {
    case open, underReview, resolvedRefund, resolvedRelease, unknown

    var isResolved: Bool { self == .resolvedRefund || self == .resolvedRelease }
}

/// The dispute of an order as the order screen summarizes it.
struct OrderDisputeSummary: Equatable, Sendable {
    let id: String
    let status: DisputeState
    let statusLabel: String
    let reasonLabel: String
    /// While `OPEN`: the seller answers before then.
    let sellerDeadlineAt: Date?
    /// How it ended, in words.
    let resolution: String?
}

/// A review of the order: the member's own, or the one the other side left about them.
struct OrderReviewInfo: Equatable, Sendable {
    let rating: Int
    let comment: String?
    let createdAt: Date
}

/// The order screen (`OrderDetail`).
struct OrderDetailInfo: Identifiable, Equatable, Sendable {
    let id: String
    let number: String
    let side: OrderSide
    let status: OrderState
    let statusLabel: String
    let title: String
    let imageURL: URL?
    let counterpart: MemberRef?
    let createdAt: Date
    let items: [OrderLine]
    let amounts: OrderMoney
    let cashOnDelivery: CashCollection?
    let delivery: OrderDeliveryInfo
    let steps: [OrderStepInfo]
    /// Newest first.
    let carrierScans: [CarrierScan]
    let payDeadlineAt: Date?
    let shipDeadlineAt: Date?
    let autoCompleteAt: Date?
    let pickupReady: Bool
    let actions: OrderActionFlags
    let dispute: OrderDisputeSummary?
    let myReview: OrderReviewInfo?
    let reviewReceived: OrderReviewInfo?
    let conversationId: String?

    var isBundle: Bool { items.count > 1 }

    /// The row of the list this order now makes.
    func row(keeping row: OrderRow) -> OrderRow {
        var row = row
        row.status = status
        row.statusLabel = statusLabel
        return row
    }
}

/// Who wrote a message of the dispute thread.
enum DisputeAuthor: Equatable, Sendable {
    case buyer, seller, support, unknown
}

/// A message of the dispute thread.
struct DisputeMessageInfo: Identifiable, Equatable, Sendable {
    let id: String
    let role: DisputeAuthor
    /// "Acheteur", "Vendeur", "Support Taleed", from the server.
    let roleLabel: String
    /// Nil when the author deleted their account.
    let authorName: String?
    let isMine: Bool
    /// Empty for a photo-only message.
    let body: String
    let photoURLs: [URL]
    let createdAt: Date
}

/// The dispute thread (`GET /disputes/{id}`).
struct DisputeInfo: Identifiable, Equatable, Sendable {
    let id: String
    let status: DisputeState
    let statusLabel: String
    let reasonLabel: String
    let sellerDeadlineAt: Date?
    let resolution: String?
    let orderId: String
    let orderNumber: String
    let side: OrderSide
    let canPost: Bool
    let canRespond: Bool
    /// Oldest first.
    let messages: [DisputeMessageInfo]
    let createdAt: Date
    let resolvedAt: Date?
}

/// The parcel's label (`ShippingLabel`): the carrier's document (usually a PDF) or the demo carrier's
/// printable page. Fetched again on each print, since the demo link stops working at `expiresAt`.
struct ShippingLabelInfo: Equatable, Sendable {
    let url: URL
    let expiresAt: Date?
}

/// What `POST /orders/{id}/ship` answers: the order, now `PREPARED` with its tracking number, and the
/// label, nil while the carrier has not given one yet.
struct ShipmentResult: Equatable, Sendable {
    let order: OrderDetailInfo
    let label: ShippingLabelInfo?
}

/// The seller's answer to the buyer's claim (`POST /disputes/{id}/respond`).
enum DisputeAnswerChoice: String, Equatable, Sendable {
    /// The buyer is refunded in full at once: `RESOLVED_REFUND`.
    case accept = "ACCEPT"
    /// Taleed mediates: `UNDER_REVIEW`.
    case contest = "CONTEST"
}

/// A reason of the dispute form, from `GET /catalog` `disputeReasons`.
typealias DisputeReasonOption = CatalogDisputeReason
