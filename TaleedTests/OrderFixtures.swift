import Foundation
@testable import Taleed
import Testing

// MARK: - Fixtures

func orderRow(_ id: String, status: OrderState = .paid, label: String = "Payée — à expédier", side: OrderSide = .buyer) -> OrderRow {
    OrderRow(id: id, number: "T-\(id)", side: side, status: status, statusLabel: label, title: "Article \(id)", imageURL: nil,
             counterpart: MemberRef(id: "m1", username: "lina_kh", displayName: "@lina_kh", avatarURL: nil, isVerified: true,
                                    isOfficial: false),
             createdAt: Date(timeIntervalSince1970: 0), itemCount: 1, amount: 2500)
}

func orderDetail(
    id: String = "o1",
    side: OrderSide = .buyer,
    status: OrderState = .paid,
    label: String = "label",
    items: Int = 1,
    money: OrderMoney = OrderMoney(itemPrice: 2000, protectionFee: 150, shippingFee: 400, discount: 0, total: 2550,
                                   walletApplied: 0, amountDue: 2550, sellerEarns: 2000),
    cash: CashCollection? = nil,
    stopdesk: String? = nil,
    payDeadline: Date? = nil,
    shipDeadline: Date? = nil,
    autoComplete: Date? = nil,
    pickupReady: Bool = false,
    actions: OrderActionFlags = OrderActionFlags()
) -> OrderDetailInfo {
    OrderDetailInfo(
        id: id, number: "T-000031", side: side, status: status, statusLabel: label, title: "Article", imageURL: nil,
        counterpart: nil, createdAt: Date(timeIntervalSince1970: 0),
        items: (0..<items).map { OrderLine(listingId: "l\($0)", title: "Item \($0)", price: 1000, imageURL: nil) },
        amounts: money, cashOnDelivery: cash,
        delivery: OrderDeliveryInfo(kind: stopdesk == nil ? .home : .stopdesk, recipientName: "Yasmine B", phone: "0550123456",
                                    wilaya: "Alger", commune: "Hydra", addressLine: nil, stopdeskName: stopdesk, tracking: nil),
        steps: [], carrierScans: [], payDeadlineAt: payDeadline, shipDeadlineAt: shipDeadline, autoCompleteAt: autoComplete,
        pickupReady: pickupReady, actions: actions, dispute: nil, myReview: nil, reviewReceived: nil, conversationId: "c1"
    )
}

func disputeInfo(id: String = "d1", canPost: Bool = true, messages: Int = 1) -> DisputeInfo {
    DisputeInfo(id: id, status: .open, statusLabel: "Ouvert", reasonLabel: "Article endommagé", sellerDeadlineAt: nil,
                resolution: nil, orderId: "o1", orderNumber: "T-000031", side: .buyer, canPost: canPost, canRespond: false,
                messages: (0..<messages).map {
                    DisputeMessageInfo(id: "m\($0)", role: .buyer, roleLabel: "Acheteur", authorName: "@yasmine_b", isMine: true,
                                       body: "Message \($0)", photoURLs: [], createdAt: Date(timeIntervalSince1970: 0))
                },
                createdAt: Date(timeIntervalSince1970: 0), resolvedAt: nil)
}

let disputeReasons = [
    DisputeReasonOption(value: "NOT_RECEIVED", label: "Colis non reçu", needsEvidence: false),
    DisputeReasonOption(value: "DAMAGED", label: "Article endommagé", needsEvidence: true),
]

func failure(_ status: Int, _ code: ApiErrorCode) -> Taleed.ApiError {
    .failed(ApiFailure(status: status, code: code))
}

/// The orders calls from canned results.
@MainActor
final class FakeOrdersApi: OrdersApi {
    var rows: [OrderSide: [OrderRow]] = [.buyer: [orderRow("1"), orderRow("2")], .seller: [orderRow("3", side: .seller)]]
    var counts = OrderTabCounts(purchases: 2, sales: 1)
    var orderResults: [Result<OrderDetailInfo, Taleed.ApiError>] = []
    var defaultOrder = orderDetail()
    var actionResult: Result<OrderDetailInfo, Taleed.ApiError>?
    var disputeResult: Result<DisputeInfo, Taleed.ApiError> = .success(disputeInfo())
    var postResult: Result<DisputeInfo, Taleed.ApiError> = .success(disputeInfo(messages: 2))
    var reviewResult: Result<OrderDetailInfo, Taleed.ApiError>?
    var paymentURL: Result<URL?, Taleed.ApiError> = .success(URL(string: "https://pay.example/1"))
    var syncResults: [OrderDetailInfo] = []
    private(set) var listCalls: [(OrderSide, Bool)] = []
    private(set) var orderCalls = 0
    private(set) var cancels = 0
    private(set) var confirms = 0
    struct OpenedDispute {
        let reason: String
        let description: String
        let keys: [String]
    }

    private(set) var openedDisputes: [OpenedDispute] = []
    private(set) var posts: [(body: String?, keys: [String])] = []
    private(set) var reviews: [(rating: Int, comment: String?)] = []
    private(set) var syncCalls = 0

    func orders(side: OrderSide, cursor: String?, automatic: Bool) async throws(Taleed.ApiError) -> OrdersPage {
        listCalls.append((side, automatic))
        let items = rows[side] ?? []
        return OrdersPage(page: Page(items: items, nextCursor: nil, total: items.count), counts: counts)
    }

    func order(id: String, automatic: Bool) async throws(Taleed.ApiError) -> OrderDetailInfo {
        orderCalls += 1
        if !orderResults.isEmpty { return try orderResults.removeFirst().get() }
        return defaultOrder
    }

    func syncPayment(orderId: String) async throws(Taleed.ApiError) -> OrderDetailInfo {
        syncCalls += 1
        return syncResults.isEmpty ? defaultOrder : syncResults.removeFirst()
    }

    func paymentPage(orderId: String) async throws(Taleed.ApiError) -> URL? { try paymentURL.get() }

    func cancel(orderId: String) async throws(Taleed.ApiError) -> OrderDetailInfo {
        cancels += 1
        return try (actionResult ?? .success(orderDetail(status: .cancelled))).get()
    }

    func confirmReceipt(orderId: String) async throws(Taleed.ApiError) -> OrderDetailInfo {
        confirms += 1
        return try (actionResult ?? .success(orderDetail(status: .completed, actions: OrderActionFlags(canReview: true)))).get()
    }

    func openDispute(orderId: String, reason: String, description: String, photoKeys: [String]) async throws(Taleed.ApiError)
        -> DisputeInfo {
        openedDisputes.append(OpenedDispute(reason: reason, description: description, keys: photoKeys))
        return try disputeResult.get()
    }

    func dispute(id: String, automatic: Bool) async throws(Taleed.ApiError) -> DisputeInfo { try disputeResult.get() }

    func postDisputeMessage(disputeId: String, body: String?, photoKeys: [String]) async throws(Taleed.ApiError) -> DisputeInfo {
        posts.append((body, photoKeys))
        return try postResult.get()
    }

    func review(orderId: String, rating: Int, comment: String?) async throws(Taleed.ApiError) -> OrderDetailInfo {
        reviews.append((rating, comment))
        return try (reviewResult ?? .success(orderDetail(status: .completed))).get()
    }
}

func uploadOK(_ data: Data) async throws(Taleed.ApiError) -> UploadedPhoto {
    UploadedPhoto(key: "disputes/2026/10/0123456789abcdef.webp", url: nil, thumbURL: nil)
}
