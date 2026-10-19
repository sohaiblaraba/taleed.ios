import Foundation

/// What the order screen shows, from the server's data (screens.md §7 G12/G13 "Notices", website
/// `orders/[id]/page.tsx`). Buttons come only from `actions`; the notices follow the website's
/// conditions on the deadlines the server sets (at most one at a time).
enum OrderRules {
    /// A notice above the order, in the website's order.
    enum Notice: Equatable, Sendable {
        /// Buyer, awaiting payment: "Payez avant {date}, sinon la commande sera annulée."
        case payDeadline(Date)
        /// Seller, awaiting payment: "En attente du paiement — l'acheteur a jusqu'au {date}…"
        case awaitingPayment(Date)
        /// Buyer, paid or prepared: the seller ships before then, or the buyer is refunded.
        case sellerShipsBy(Date)
        /// Seller, paid: "À expédier avant le {date}".
        case shipBy(Date)
        /// Seller, prepared: "Bordereau prêt — déposez le colis en agence avant le {date}".
        case dropOffBy(Date)
        /// Cash on delivery while the parcel is on its way: what the carrier collects.
        case cashOnDelivery(CashCollection)
        /// The parcel waits at the pick-up point.
        case pickupReady(place: String)
        /// Delivered: "Fonds libérés automatiquement le {date}".
        case autoRelease(Date)
    }

    static func notices(for order: OrderDetailInfo) -> [Notice] {
        var notices = [payNotice(order), shipNotice(order)].compactMap { $0 }
        if let cash = order.cashOnDelivery, cash.total > 0, [.paid, .prepared, .shipped].contains(order.status) {
            notices.append(.cashOnDelivery(cash))
        }
        if order.pickupReady {
            notices.append(.pickupReady(place: order.delivery.pickupPlace))
        }
        if let date = order.autoCompleteAt {
            notices.append(.autoRelease(date))
        }
        return notices
    }

    private static func payNotice(_ order: OrderDetailInfo) -> Notice? {
        guard order.status == .pendingPayment, let deadline = order.payDeadlineAt else { return nil }
        switch order.side {
        case .buyer: return .payDeadline(deadline)
        case .seller: return .awaitingPayment(deadline)
        case .unknown: return nil
        }
    }

    private static func shipNotice(_ order: OrderDetailInfo) -> Notice? {
        guard let deadline = order.shipDeadlineAt else { return nil }
        switch (order.side, order.status) {
        case (.buyer, .paid), (.buyer, .prepared): return .sellerShipsBy(deadline)
        case (.seller, .paid): return .shipBy(deadline)
        case (.seller, .prepared): return .dropOffBy(deadline)
        default: return nil
        }
    }

    /// A button of the buyer, in the order the screen shows them.
    enum BuyerAction: Equatable, Sendable {
        /// "Payer maintenant".
        case pay
        /// "Confirmer la réception", after a confirmation.
        case confirmReceipt
        /// "Confirmer la réception" disabled, with "Disponible dès que le colis est arrivé…".
        case awaitingArrival
        /// "Laisser une évaluation".
        case review
        /// "Signaler un problème": the dispute form.
        case openDispute
        /// "Annuler la commande", after a confirmation.
        case cancel
    }

    /// The buyer's buttons, from `actions` only (slice D, Actions: never from `status`).
    static func buyerActions(_ actions: OrderActionFlags) -> [BuyerAction] {
        var result: [BuyerAction] = []
        if actions.canPay { result.append(.pay) }
        if actions.canConfirmReceipt {
            result.append(.confirmReceipt)
        } else if actions.awaitingArrival {
            result.append(.awaitingArrival)
        }
        if actions.canReview { result.append(.review) }
        if actions.canOpenDispute { result.append(.openDispute) }
        if actions.canCancel { result.append(.cancel) }
        return result
    }

    /// A line of the order's amounts.
    enum AmountLine: Equatable, Sendable {
        /// "Prix de l'article", or "Prix du lot (n articles)" for a bundle.
        case itemPrice(bundleCount: Int?)
        case protectionFee
        case shippingFee
        /// "Réduction (code promo)", as a negative amount.
        case discount
        /// "Total", as a line when the wallet paid part of it.
        case total
        /// "Payé avec le portefeuille", as a negative amount.
        case walletPaid
    }

    /// The bottom line of the amounts.
    enum AmountTotal: Equatable, Sendable {
        /// "Total".
        case total
        /// "Reste à payer": what the wallet did not pay.
        case remainderDue
        /// The seller's "Vous recevrez".
        case sellerEarns
    }

    struct Amounts: Equatable, Sendable {
        let lines: [(AmountLine, Int)]
        let total: AmountTotal
        let totalAmount: Int

        static func == (lhs: Amounts, rhs: Amounts) -> Bool {
            lhs.lines.map(\.0) == rhs.lines.map(\.0) && lhs.lines.map(\.1) == rhs.lines.map(\.1)
                && lhs.total == rhs.total && lhs.totalAmount == rhs.totalAmount
        }
    }

    /// The order's amounts as the server keeps them (the website's ledger; never added up in the app).
    static func amounts(for order: OrderDetailInfo) -> Amounts {
        let money = order.amounts
        var lines: [(AmountLine, Int)] = [
            (.itemPrice(bundleCount: order.isBundle ? order.items.count : nil), money.itemPrice),
            (.protectionFee, money.protectionFee),
            (.shippingFee, money.shippingFee),
        ]
        if money.discount > 0 { lines.append((.discount, -money.discount)) }
        if order.side == .seller {
            lines.append((.total, money.total))
            return Amounts(lines: lines, total: .sellerEarns, totalAmount: money.sellerEarns)
        }
        if money.walletApplied > 0 {
            lines.append((.total, money.total))
            lines.append((.walletPaid, -money.walletApplied))
            return Amounts(lines: lines, total: .remainderDue, totalAmount: money.amountDue)
        }
        return Amounts(lines: lines, total: .total, totalAmount: money.total)
    }

    /// The amount next to the order's goods: the total for the buyer, what the seller receives.
    static func headlineAmount(for order: OrderDetailInfo) -> Int {
        order.side == .seller ? order.amounts.sellerEarns : order.amounts.total
    }
}

/// Dates of the orders screens, as the website prints them (`formatDate`, `formatDateTime`): Arabic
/// with Latin digits.
enum OrderText {
    static func date(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func dateTime(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
