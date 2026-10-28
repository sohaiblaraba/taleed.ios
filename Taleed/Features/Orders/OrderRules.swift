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
        /// Buyer, paid or prepared: the seller ships before then, or the buyer is refunded; on cash on
        /// delivery (nothing paid yet), or the order is cancelled.
        case sellerShipsBy(Date, cashOnDelivery: Bool)
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
        case (.buyer, .paid), (.buyer, .prepared): return .sellerShipsBy(deadline, cashOnDelivery: order.cashOnDelivery != nil)
        case (.seller, .paid): return .shipBy(deadline)
        case (.seller, .prepared): return .dropOffBy(deadline)
        default: return nil
        }
    }

    /// A button of the order screen, in the order the screen shows them.
    enum MemberAction: Equatable, Sendable {
        // Buyer
        /// "Payer maintenant".
        case pay
        /// "Confirmer la réception", after a confirmation.
        case confirmReceipt
        /// "Confirmer la réception" disabled, with "Disponible dès que le colis est arrivé…".
        case awaitingArrival
        /// "Signaler un problème": the dispute form.
        case openDispute
        /// "Annuler la commande", after a confirmation.
        case cancel
        // Seller
        /// "Bordereau d'expédition", after a confirmation: the carrier creates the parcel and its label.
        case ship
        /// "Imprimer le bordereau": a fresh link to the label, opened in the browser.
        case printLabel
        /// "Générer le vrai bordereau" (test servers only), after a confirmation: a real parcel replaces
        /// the demo carrier's one.
        case replaceTestLabel
        /// "Accepter la réclamation", after a confirmation: the buyer is refunded at once.
        case acceptClaim
        /// "Contester": Taleed mediates.
        case contestClaim
        // Both
        /// "Laisser une évaluation".
        case review
    }

    /// The buyer's buttons, from `actions` only (slice D, Actions: never from `status`).
    static func buyerActions(_ actions: OrderActionFlags) -> [MemberAction] {
        var result: [MemberAction] = []
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

    /// The seller's buttons, from `actions` only, in the website's order (`order-actions.tsx`): ship,
    /// print, replace the demo label, answer the claim, review. The seller never cancels.
    static func sellerActions(_ actions: OrderActionFlags) -> [MemberAction] {
        var result: [MemberAction] = []
        if actions.canShip { result.append(.ship) }
        if actions.canPrintLabel { result.append(.printLabel) }
        if actions.canReplaceTestLabel { result.append(.replaceTestLabel) }
        if actions.canRespondToDispute { result.append(contentsOf: [.acceptClaim, .contestClaim]) }
        if actions.canReview { result.append(.review) }
        return result
    }

    /// The member's buttons on the order, by side (screens.md §7 G12/G13 abilities).
    static func memberActions(_ actions: OrderActionFlags, side: OrderSide) -> [MemberAction] {
        switch side {
        case .buyer: buyerActions(actions)
        case .seller: sellerActions(actions)
        case .unknown: []
        }
    }

    /// A line of the order's amounts.
    enum AmountLine: Equatable, Sendable {
        /// "Prix de l'article", or "Prix du lot (n articles)" for a bundle.
        case itemPrice(bundleCount: Int?)
        case protectionFee
        case shippingFee
        /// "Réduction (code promo)", as a negative amount.
        case discount
        /// "Bon de parrainage", as a negative amount.
        case voucher
        /// "Total", as a line when the wallet paid part of it.
        case total
        /// "Déjà réglé sur Taleed" (orders placed before slice H), as a negative amount.
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
        // One row per part of the discount (website): the promo code, then the referral voucher.
        if money.promoDiscount > 0 { lines.append((.discount, -money.promoDiscount)) }
        if money.voucherDiscount > 0 { lines.append((.voucher, -money.voucherDiscount)) }
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

    /// The refund block (slice H; the website's refund notice): what is refunded, how and where it stands.
    /// How a refund being sent travels, for its hint.
    enum RefundHint: Equatable, Sendable {
        /// "The Taleed team sends it back to the card you paid with…"
        case card
        /// "The Taleed team sends it by bank transfer to your payout details."
        case bank
    }

    struct RefundBlock: Equatable, Sendable {
        /// Green once sent, blue while being sent.
        let isSent: Bool
        let amount: Int
        /// "To your card — Being sent", the server's labels.
        let summary: String
        /// Sent: "Sent on {date}".
        let sentAt: Date?
        /// Sent: "Reference: {reference}".
        let reference: String?
        /// While being sent: how it travels. None for a method this build does not know.
        let hint: RefundHint?
        /// "Add your payout details to receive this refund" and "Add payout details" (opens Earnings).
        let asksPayoutDetails: Bool
    }

    /// Buyer only (the API gives the seller no refund); nil when nothing is to be refunded.
    static func refundBlock(for order: OrderDetailInfo) -> RefundBlock? {
        guard order.side == .buyer, let refund = order.refund else { return nil }
        let isSent = refund.status == .sent
        let hint: RefundHint? = switch refund.method {
        case .card: .card
        case .bank: .bank
        case .unknown: nil
        }
        return RefundBlock(
            isSent: isSent,
            amount: refund.amount,
            summary: "\(refund.methodLabel) — \(refund.statusLabel)",
            sentAt: isSent ? refund.sentAt : nil,
            reference: isSent ? refund.reference : nil,
            hint: isSent ? nil : hint,
            // The server decides (a bank refund to send, no payout details yet); never once sent.
            asksPayoutDetails: refund.needsPayoutAccount && !isSent
        )
    }
}

/// The app's one date format and one time format, used on every screen (and by the API's own texts,
/// decision E-1). The date is the website's medium date (`formatDate` in `src/lib/i18n-helpers.ts`:
/// fr-FR, en-GB and ar-DZ), Arabic with Latin digits. The time is 24-hour in French and Arabic, and
/// follows the device's 12- or 24-hour setting in English:
/// - French: "20 oct. 2026", "14:05", "20 oct. 2026, 14:05";
/// - English: "20 Oct 2026", "2:05 PM" or "14:05", "20 Oct 2026, 2:05 PM";
/// - Arabic: "20‏/10‏/2026", "14:05", "20‏/10‏/2026، 14:05".
enum OrderText {
    static func date(_ date: Date, locale: Locale) -> String {
        let language = AppLanguage(locale: locale)
        let formatter = DateFormatter()
        formatter.locale = webLocale(language)
        formatter.dateFormat = datePattern(language)
        return formatter.string(from: date)
    }

    /// The time alone ("14:05", "2:05 PM").
    static func time(_ date: Date, locale: Locale, uses12HourClock: Bool = deviceUses12HourClock) -> String {
        let language = AppLanguage(locale: locale)
        let formatter = timeFormatter(language)
        formatter.dateFormat = timePattern(language, uses12HourClock: uses12HourClock)
        return formatter.string(from: date)
    }

    static func dateTime(_ date: Date, locale: Locale, uses12HourClock: Bool = deviceUses12HourClock) -> String {
        let language = AppLanguage(locale: locale)
        let formatter = timeFormatter(language)
        // The date keeps together; the line may break after the comma, before the time.
        let separator = language == .ar ? "\u{060C} " : ", "
        formatter.dateFormat = datePattern(language) + "'\(separator)'"
            + timePattern(language, uses12HourClock: uses12HourClock)
        return formatter.string(from: date)
    }

    /// Whether the device writes times on a 12-hour clock (its region, or the 24-hour switch in Settings).
    static var deviceUses12HourClock: Bool {
        let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent) ?? ""
        return pattern.contains("a") || pattern.contains("h") || pattern.contains("K")
    }

    /// No break inside a date ("21 / oct. 2026"): it wraps as one unit in a line of text.
    private static func datePattern(_ language: AppLanguage) -> String {
        switch language {
        case .fr, .en: "d\u{00A0}MMM\u{00A0}y"
        case .ar: "dd\u{200F}/MM\u{200F}/y"
        }
    }

    private static func timePattern(_ language: AppLanguage, uses12HourClock: Bool) -> String {
        language == .en && uses12HourClock ? "h:mm\u{00A0}a" : "HH:mm"
    }

    private static func timeFormatter(_ language: AppLanguage) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = webLocale(language)
        // en-GB writes "pm"; English times read "2:05 PM".
        formatter.amSymbol = language == .en ? "AM" : formatter.amSymbol
        formatter.pmSymbol = language == .en ? "PM" : formatter.pmSymbol
        return formatter
    }

    private static let noBreakSpace = "\u{00A0}"

    /// The website's "Paiement à la livraison — le transporteur encaisse …" as a title and a body
    /// ("Paiement à la livraison" / "Le transporteur encaisse …"); a text without " — " is all title.
    static func titled(_ text: String) -> (title: String, body: String?) {
        guard let range = text.range(of: " — ") else { return (text, nil) }
        let title = String(text[..<range.lowerBound])
        let body = String(text[range.upperBound...])
        guard !title.isEmpty, let first = body.first else { return (text, nil) }
        return (title, first.uppercased() + body.dropFirst())
    }

    /// The website's `Intl` locale for the language.
    static func webLocale(_ language: AppLanguage) -> Locale {
        switch language {
        case .fr: Locale(identifier: "fr_FR")
        case .en: Locale(identifier: "en_GB")
        case .ar: Locale(identifier: "ar_DZ@numbers=latn")
        }
    }
}
