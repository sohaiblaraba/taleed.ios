import SwiftUI
import TaleedAPI

/// The calls of the orders screens, both sides (screens.md §2 G12 and G13, slice D "Orders", "Shipping:
/// the seller", "Disputes", "Reviews").
@MainActor
protocol OrdersApi: AnyObject {
    /// `GET /orders?role=`: newest first, 20 a page, with the tab counters. `automatic`: a refresh the
    /// member did not ask for (back in the foreground).
    func orders(side: OrderSide, cursor: String?, automatic: Bool) async throws(ApiError) -> OrdersPage
    /// `GET /orders/{id}`.
    func order(id: String, automatic: Bool) async throws(ApiError) -> OrderDetailInfo
    /// `POST /orders/{id}/payment/sync`: asks the gateway, then the order. Repeated freely.
    func syncPayment(orderId: String) async throws(ApiError) -> OrderDetailInfo
    /// `POST /orders/{id}/payment`: a new payment page for an order that waits for payment.
    func paymentPage(orderId: String) async throws(ApiError) -> URL?
    /// `POST /orders/{id}/cancel`. Once done, a repeat answers the cancelled order.
    func cancel(orderId: String) async throws(ApiError) -> OrderDetailInfo
    /// `POST /orders/{id}/confirm-receipt`. Once done, a repeat answers the completed order.
    func confirmReceipt(orderId: String) async throws(ApiError) -> OrderDetailInfo
    /// `POST /orders/{id}/dispute`. After a lost answer, `dispute_exists` means it went through.
    func openDispute(orderId: String, reason: String, description: String, photoKeys: [String]) async throws(ApiError)
        -> DisputeInfo
    /// `GET /disputes/{id}`: the whole thread, oldest first.
    func dispute(id: String, automatic: Bool) async throws(ApiError) -> DisputeInfo
    /// `POST /disputes/{id}/messages`: not idempotent, a retry posts again.
    func postDisputeMessage(disputeId: String, body: String?, photoKeys: [String]) async throws(ApiError) -> DisputeInfo
    /// `POST /orders/{id}/review`. After a lost answer, `already_reviewed` means it went through.
    func review(orderId: String, rating: Int, comment: String?) async throws(ApiError) -> OrderDetailInfo
    /// `POST /orders/{id}/ship`: the carrier creates the parcel and its label, which can take several
    /// seconds. Idempotent: a repeat answers the same parcel. `502 carrier_error` carries the carrier's
    /// `detail`.
    func ship(orderId: String) async throws(ApiError) -> ShipmentResult
    /// `GET /orders/{id}/label`: a fresh link to the label, on each print. The seller only.
    func shippingLabel(orderId: String) async throws(ApiError) -> ShippingLabelInfo
    /// `POST /disputes/{id}/respond`: the seller accepts or contests the claim. The same answer again
    /// changes nothing; another one once the dispute moved on is `invalid_state`.
    func respondToDispute(disputeId: String, answer: DisputeAnswerChoice) async throws(ApiError) -> DisputeInfo
}

extension OrdersApi {
    func order(id: String) async throws(ApiError) -> OrderDetailInfo { try await order(id: id, automatic: false) }
}

extension GeneratedTaleedApi: OrdersApi {
    func orders(side: OrderSide, cursor: String?, automatic: Bool) async throws(ApiError) -> OrdersPage {
        let role: OrderRole? = switch side {
        case .buyer: .buyer
        case .seller: .seller
        case .unknown: nil
        }
        let page = try await caller.call(.read, automatic: automatic) {
            try await OrdersAPI.listOrders(role: role, cursor: cursor, apiConfiguration: $0)
        }
        return OrdersPage(page: Page(items: page.items.map(OrderRow.init), nextCursor: page.nextCursor, total: page.total),
                          counts: OrderTabCounts(purchases: page.counts.purchases, sales: page.counts.sales))
    }

    func order(id: String, automatic: Bool) async throws(ApiError) -> OrderDetailInfo {
        OrderDetailInfo(try await caller.call(.read, automatic: automatic) { try await OrdersAPI.getOrder(id: id, apiConfiguration: $0) })
    }

    func syncPayment(orderId: String) async throws(ApiError) -> OrderDetailInfo {
        // Repeated freely (slice D, Retrying).
        OrderDetailInfo(try await caller.call(.read) { try await OrdersAPI.syncOrderPayment(id: orderId, apiConfiguration: $0) })
    }

    func paymentPage(orderId: String) async throws(ApiError) -> URL? {
        // Each call opens a new payment page: the member's tap only.
        let payment = try await caller.call(.write) { try await OrdersAPI.payOrder(id: orderId, apiConfiguration: $0) }
        return URL(apiString: payment.paymentUrl)
    }

    func cancel(orderId: String) async throws(ApiError) -> OrderDetailInfo {
        // Retried freely by the server's design, but only ever on the member's tap here.
        OrderDetailInfo(try await caller.call(.write) { try await OrdersAPI.cancelOrder(id: orderId, apiConfiguration: $0) })
    }

    func confirmReceipt(orderId: String) async throws(ApiError) -> OrderDetailInfo {
        OrderDetailInfo(try await caller.call(.write) { try await OrdersAPI.confirmReceipt(id: orderId, apiConfiguration: $0) })
    }

    func openDispute(orderId: String, reason: String, description: String, photoKeys: [String]) async throws(ApiError)
        -> DisputeInfo {
        let body = DisputeCreate(reason: DisputeReason(rawValue: reason) ?? .unknownDefaultOpenApi, description: description,
                                 photoKeys: photoKeys.isEmpty ? nil : photoKeys)
        return DisputeInfo(try await caller.call(.write) {
            try await DisputesAPI.openDispute(id: orderId, disputeCreate: body, apiConfiguration: $0)
        })
    }

    func dispute(id: String, automatic: Bool) async throws(ApiError) -> DisputeInfo {
        DisputeInfo(try await caller.call(.read, automatic: automatic) { try await DisputesAPI.getDispute(id: id, apiConfiguration: $0) })
    }

    func postDisputeMessage(disputeId: String, body: String?, photoKeys: [String]) async throws(ApiError) -> DisputeInfo {
        let message = DisputeMessageCreate(body: body, photoKeys: photoKeys.isEmpty ? nil : photoKeys)
        return DisputeInfo(try await caller.call(.write) {
            try await DisputesAPI.postDisputeMessage(id: disputeId, disputeMessageCreate: message, apiConfiguration: $0)
        })
    }

    func review(orderId: String, rating: Int, comment: String?) async throws(ApiError) -> OrderDetailInfo {
        let body = ReviewCreate(rating: rating, comment: comment)
        return OrderDetailInfo(try await caller.call(.write) {
            try await ReviewsAPI.reviewOrder(id: orderId, reviewCreate: body, apiConfiguration: $0)
        })
    }

    func ship(orderId: String) async throws(ApiError) -> ShipmentResult {
        // Safe to repeat on the server's side (the same parcel comes back), but it only ever runs on the
        // seller's tap: a carrier refusal must not be sent again on its own.
        let prepared = try await caller.call(.write) { try await OrdersAPI.shipOrder(id: orderId, apiConfiguration: $0) }
        return ShipmentResult(order: OrderDetailInfo(prepared.order), label: prepared.label.flatMap(ShippingLabelInfo.init))
    }

    func shippingLabel(orderId: String) async throws(ApiError) -> ShippingLabelInfo {
        let label = try await caller.call(.read) { try await OrdersAPI.getShippingLabel(id: orderId, apiConfiguration: $0) }
        guard let info = ShippingLabelInfo(label) else {
            // A link the app cannot open: nothing to print.
            throw .failed(ApiFailure(status: 409, code: .invalidState))
        }
        return info
    }

    func respondToDispute(disputeId: String, answer: DisputeAnswerChoice) async throws(ApiError) -> DisputeInfo {
        let body = DisputeResponse(answer: DisputeAnswer(rawValue: answer.rawValue) ?? .unknownDefaultOpenApi)
        return DisputeInfo(try await caller.call(.write) {
            try await DisputesAPI.respondDispute(id: disputeId, disputeResponse: body, apiConfiguration: $0)
        })
    }
}

/// What the orders screens need. Set once at the root (`AppRootView`): the orders, the payment page
/// (G11's checkout calls) and the photo uploads of disputes.
struct OrdersDependencies {
    let orders: any OrdersApi
    let uploads: PhotoUploadService
}

private struct OrdersDependenciesKey: EnvironmentKey {
    static var defaultValue: OrdersDependencies? { nil }
}

extension EnvironmentValues {
    var ordersDependencies: OrdersDependencies? {
        get { self[OrdersDependenciesKey.self] }
        set { self[OrdersDependenciesKey.self] = newValue }
    }
}

// MARK: - Mapping

private extension OrderSide {
    init(_ role: OrderRole) {
        self = switch role {
        case .buyer: .buyer
        case .seller: .seller
        case .unknownDefaultOpenApi: .unknown
        }
    }
}

private extension OrderRow {
    init(_ order: TaleedAPI.OrderSummary) {
        self.init(id: order.id, number: order.number, side: OrderSide(order.role), status: OrderState(order.status),
                  statusLabel: order.statusLabel, title: order.title, imageURL: URL(apiString: order.imageUrl),
                  counterpart: order.counterpart.map(MemberRef.init), createdAt: order.createdAt, itemCount: order.itemCount,
                  amount: order.amount)
    }
}

extension OrderDetailInfo {
    init(_ order: OrderDetail) {
        let amounts = order.amounts
        self.init(
            id: order.id,
            number: order.number,
            side: OrderSide(order.role),
            status: OrderState(order.status),
            statusLabel: order.statusLabel,
            title: order.title,
            imageURL: URL(apiString: order.imageUrl),
            counterpart: order.counterpart.map(MemberRef.init),
            createdAt: order.createdAt,
            items: order.items.map {
                OrderLine(listingId: $0.listingId, title: $0.title, price: $0.price, imageURL: URL(apiString: $0.imageUrl))
            },
            amounts: OrderMoney(itemPrice: amounts.itemPrice, protectionFee: amounts.protectionFee, shippingFee: amounts.shippingFee,
                                discount: amounts.discount, total: amounts.total, walletApplied: amounts.walletApplied,
                                amountDue: amounts.amountDue, sellerEarns: amounts.sellerEarns),
            cashOnDelivery: order.cashOnDelivery.map { CashCollection(total: $0.total, deliveryFee: $0.deliveryFee) },
            delivery: OrderDeliveryInfo(order.delivery),
            // Every step of the server, in its order, with its label; an unknown step keeps its label.
            steps: order.steps.enumerated().map {
                OrderStepInfo(id: $0.offset, label: $0.element.label, done: $0.element.done, date: $0.element.at)
            },
            carrierScans: order.carrierEvents.enumerated().map {
                CarrierScan(id: $0.offset, status: $0.element.status, place: $0.element.place?.nilIfBlank, date: $0.element.at)
            },
            payDeadlineAt: order.payDeadlineAt,
            shipDeadlineAt: order.shipDeadlineAt,
            autoCompleteAt: order.autoCompleteAt,
            pickupReady: order.pickupReady,
            actions: OrderActionFlags(order.actions),
            dispute: order.dispute.map {
                OrderDisputeSummary(id: $0.id, status: DisputeState($0.status), statusLabel: $0.statusLabel,
                                    reasonLabel: $0.reasonLabel, sellerDeadlineAt: $0.sellerDeadlineAt,
                                    resolution: $0.resolution?.nilIfBlank)
            },
            myReview: order.myReview.map(OrderReviewInfo.init),
            reviewReceived: order.reviewReceived.map(OrderReviewInfo.init),
            conversationId: order.conversationId
        )
    }
}

private extension OrderDeliveryInfo {
    init(_ delivery: OrderDelivery) {
        self.init(kind: OrderDeliveryKind(delivery.type), recipientName: delivery.recipientName, phone: delivery.phone,
                  wilaya: delivery.wilaya.name, commune: delivery.commune, addressLine: delivery.addressLine?.nilIfBlank,
                  stopdeskName: delivery.stopdeskName?.nilIfBlank, tracking: delivery.tracking?.nilIfBlank)
    }
}

private extension OrderActionFlags {
    init(_ actions: OrderActions) {
        self.init(canPay: actions.canPay, canCancel: actions.canCancel, canShip: actions.canShip,
                  canReplaceTestLabel: actions.canReplaceTestLabel, canPrintLabel: actions.canPrintLabel,
                  canConfirmReceipt: actions.canConfirmReceipt, awaitingArrival: actions.awaitingArrival,
                  canOpenDispute: actions.canOpenDispute, canRespondToDispute: actions.canRespondToDispute,
                  canReview: actions.canReview)
    }
}

private extension OrderDeliveryKind {
    init(_ type: DeliveryType) {
        self = switch type {
        case .home: .home
        case .stopdesk: .stopdesk
        case .unknownDefaultOpenApi: .unknown
        }
    }
}

private extension DisputeAuthor {
    init(_ role: DisputeAuthorRole) {
        self = switch role {
        case .buyer: .buyer
        case .seller: .seller
        case .support: .support
        case .unknownDefaultOpenApi: .unknown
        }
    }
}

private extension ShippingLabelInfo {
    init?(_ label: ShippingLabel) {
        // The browser only opens web links (SFSafariViewController refuses any other scheme).
        guard let url = URL(apiString: label.url), ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        self.init(url: url, expiresAt: label.expiresAt)
    }
}

private extension OrderReviewInfo {
    init(_ review: OrderReview) {
        self.init(rating: review.rating, comment: review.comment?.nilIfBlank, createdAt: review.createdAt)
    }
}

private extension DisputeState {
    init(_ status: DisputeStatus) {
        self = switch status {
        case ._open: .open
        case .underReview: .underReview
        case .resolvedRefund: .resolvedRefund
        case .resolvedRelease: .resolvedRelease
        case .unknownDefaultOpenApi: .unknown
        }
    }
}

private extension DisputeInfo {
    init(_ dispute: Dispute) {
        self.init(
            id: dispute.id,
            status: DisputeState(dispute.status),
            statusLabel: dispute.statusLabel,
            reasonLabel: dispute.reasonLabel,
            sellerDeadlineAt: dispute.sellerDeadlineAt,
            resolution: dispute.resolution?.nilIfBlank,
            orderId: dispute.orderId,
            orderNumber: dispute.orderNumber,
            side: OrderSide(dispute.role),
            canPost: dispute.canPost,
            canRespond: dispute.canRespond,
            messages: dispute.messages.map { message in
                DisputeMessageInfo(
                    id: message.id,
                    role: DisputeAuthor(message.role),
                    roleLabel: message.roleLabel,
                    authorName: message.authorName?.nilIfBlank,
                    isMine: message.isMine,
                    body: message.body,
                    photoURLs: message.photoUrls.compactMap { URL(apiString: $0) },
                    createdAt: message.createdAt
                )
            },
            createdAt: dispute.createdAt,
            resolvedAt: dispute.resolvedAt
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
