import Foundation
import TaleedAPI

/// The limits of the checkout fields, from the contract (`OrderCreate`, `CheckoutDelivery`,
/// `CheckoutQuoteRequest`). On-device checks only give instant feedback: the API decides.
enum CheckoutLimits {
    static let recipientNameMin = OrderCreate.recipientNameRule.minLength ?? 2
    static let recipientNameMax = OrderCreate.recipientNameRule.maxLength ?? 80
    static let phoneMax = OrderCreate.phoneRule.maxLength ?? 30
    static let addressLineMax = CheckoutDelivery.addressLineRule.maxLength ?? 200
    static let promoCodeMax = CheckoutQuoteRequest.promoCodeRule.maxLength ?? 40
}

/// The checks of the website's checkout form (`checkout-form.tsx`) and the API (slice D, Placing the order).
enum CheckoutRules {
    /// A saved address on one line: the street, then the commune and the wilaya, each left out when the
    /// line already says it ("7 rue des Martyrs, Constantine" with Constantine / Constantine, not
    /// "…, Constantine, Constantine"; "68 rue des Martyrs, Hydra, Alger").
    static func addressTitle(_ address: SavedAddress) -> String {
        var parts = [address.addressLine.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
        // The commune is often part of the street already ("68 rue des Martyrs, Hydra").
        if !address.addressLine.localizedCaseInsensitiveContains(address.commune) {
            parts.append(address.commune)
        }
        let wilaya = address.wilaya.name
        if parts.last.map({ !endsWith($0, wilaya) }) ?? true { parts.append(wilaya) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// "…, Constantine" ends with "constantine", ignoring case and accents, as a whole word.
    private static func endsWith(_ text: String, _ name: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .anchored, .backwards]
        guard !name.isEmpty, let range = text.range(of: name, options: options) else { return false }
        guard range.lowerBound > text.startIndex else { return true }
        return !text[text.index(before: range.lowerBound)].isLetter
    }

    /// A number the carrier can call: 0, then 8 or 9 digits; spaces, dots and dashes are ignored
    /// (the contract's `^[\s.-]*0(?:[\s.-]*\d){8,9}[\s.-]*$`, read without its `pattern`).
    static func isValidPhone(_ phone: String) -> Bool {
        var digits = 0
        var first: Character?
        for character in phone {
            if character.isWhitespace || character == "." || character == "-" { continue }
            guard character.isASCII, character.isNumber else { return false }
            if first == nil { first = character }
            digits += 1
        }
        return first == "0" && (9...10).contains(digits)
    }

    /// Arabic-Indic and Persian digits typed on an Arabic keyboard become the Latin digits the API reads.
    static func latinDigits(_ text: String) -> String {
        String(text.map { character -> Character in
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return character }
            switch scalar.value {
            case 0x0660...0x0669: return Character(String(scalar.value - 0x0660))
            case 0x06F0...0x06F9: return Character(String(scalar.value - 0x06F0))
            default: return character
            }
        })
    }

    static func isValidRecipientName(_ name: String) -> Bool {
        let length = name.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
        return length >= CheckoutLimits.recipientNameMin && length <= CheckoutLimits.recipientNameMax
    }

    /// The desks of the chosen commune (the website narrows them on the device); a desk whose commune
    /// is unknown stays for every commune.
    static func desks(_ desks: [StopdeskOption], communeId: Int?) -> [StopdeskOption] {
        guard let communeId else { return [] }
        return desks.filter { $0.communeId == nil || $0.communeId == communeId }
    }
}

/// A field of the checkout form that can show an error, in screen order.
enum CheckoutField: Hashable, Sendable {
    case recipientName, phone, wilaya, commune, addressLine, stopdesk
}

/// Why a field is refused: on the device, or from the API's `issues`.
enum CheckoutFieldError: Equatable, Sendable {
    case nameLength(min: Int, max: Int)
    case phoneInvalid
    /// The carrier no longer serves the commune or the desk: pick again (slice D, The quote).
    case pickAgain
    /// Any other refusal of the field.
    case invalid
}

/// What the member filled in. The view model quotes again when a field the price depends on changes.
struct CheckoutFormState: Equatable, Sendable {
    var kind: DeliveryKind = .home
    var recipientName = ""
    var phone = ""
    var wilayaId: Int?
    var communeId: Int?
    var addressLine = ""
    var stopdeskId: Int?
    /// The promo field's text.
    var promoInput = ""
    /// The code the quotes carry, once "Appliquer" found it valid.
    var appliedPromoCode: String?
    /// On by default; the switch shows only when there is a balance (the website's default).
    var useWallet = true
    /// The member's pick in the payment list; nil: the server's first method.
    var paymentMethod: String?

    var trimmedRecipientName: String { recipientName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedAddressLine: String { addressLine.trimmingCharacters(in: .whitespacesAndNewlines) }

    var recipientNameError: CheckoutFieldError? {
        CheckoutRules.isValidRecipientName(recipientName)
            ? nil : .nameLength(min: CheckoutLimits.recipientNameMin, max: CheckoutLimits.recipientNameMax)
    }

    var phoneError: CheckoutFieldError? {
        CheckoutRules.isValidPhone(phone) ? nil : .phoneInvalid
    }

    /// The delivery a quote can take, nil until a wilaya is picked.
    var delivery: CheckoutDeliveryInput? {
        guard let wilayaId else { return nil }
        return CheckoutDeliveryInput(
            kind: kind,
            wilayaId: wilayaId,
            communeId: communeId,
            addressLine: kind == .home && !trimmedAddressLine.isEmpty ? trimmedAddressLine : nil,
            stopdeskId: kind == .stopdesk ? stopdeskId : nil
        )
    }

    /// The quote's body for the goods, nil until a wilaya is picked.
    func request(for target: CheckoutTarget) -> CheckoutRequest? {
        guard let delivery else { return nil }
        return CheckoutRequest(
            listingId: target.bundleId == nil ? target.listingId : nil,
            bundleId: target.bundleId,
            offerId: target.offerId,
            delivery: delivery,
            promoCode: appliedPromoCode,
            useWallet: useWallet,
            paymentMethod: paymentMethod
        )
    }

    /// Everything an order needs (the website's `formValid`): the recipient, a phone, the wilaya and the
    /// commune (stop-desk too), then the street or the desk.
    var isComplete: Bool {
        guard recipientNameError == nil, phoneError == nil, wilayaId != nil, communeId != nil else { return false }
        switch kind {
        case .home: return !trimmedAddressLine.isEmpty
        case .stopdesk: return stopdeskId != nil
        }
    }

    /// The home address of this order, to offer saving it.
    var addressDraft: AddressDraft? {
        guard kind == .home, isComplete, let wilayaId, let communeId else { return nil }
        return AddressDraft(recipientName: trimmedRecipientName, phone: phone.trimmingCharacters(in: .whitespaces),
                            wilayaId: wilayaId, communeId: communeId, addressLine: trimmedAddressLine)
    }

    /// A home address that is not saved yet: the payment screen offers to save it.
    func unsavedAddress(among saved: [SavedAddress]) -> AddressDraft? {
        guard let draft = addressDraft else { return nil }
        let digits = { (phone: String) in phone.filter(\.isNumber) }
        let known = saved.contains {
            $0.wilaya.id == draft.wilayaId && $0.communeId == draft.communeId
                && $0.addressLine.trimmingCharacters(in: .whitespacesAndNewlines) == draft.addressLine
                && $0.recipientName.trimmingCharacters(in: .whitespacesAndNewlines) == draft.recipientName
                && digits($0.phone) == digits(draft.phone)
        }
        return known ? nil : draft
    }

    /// Fills home delivery from a saved address. Its commune is asked again when it has none.
    mutating func apply(_ address: SavedAddress) {
        recipientName = address.recipientName
        phone = address.phone
        if wilayaId != address.wilaya.id { stopdeskId = nil }
        wilayaId = address.wilaya.id
        communeId = address.communeId
        addressLine = address.addressLine
    }

    /// A new wilaya: its communes and desks are other ones.
    mutating func selectWilaya(_ id: Int) {
        guard id != wilayaId else { return }
        wilayaId = id
        communeId = nil
        stopdeskId = nil
    }

    /// A new commune narrows the desks: the desk is picked again.
    mutating func selectCommune(_ id: Int) {
        guard id != communeId else { return }
        communeId = id
        stopdeskId = nil
    }
}

// MARK: - Summary

/// One line of the order summary, from the quote's `amounts` (screens.md §0.2): discounts are negative.
struct CheckoutSummaryRow: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// "Article", or "Lot · 2 articles".
        case item(bundleCount: Int?)
        case protectionFee
        /// `estimate`: the fee is the wilaya's highest until a commune is picked.
        case shipping(estimate: Bool)
        case promo(kind: PromoKindValue, code: String)
        case voucher
        /// "Total", shown above the wallet line when the wallet pays part of it.
        case total
        case wallet
    }

    let kind: Kind
    let amount: Int
}

enum CheckoutSummary {
    /// The lines above "Total à payer", as the website's summary shows them.
    static func rows(for pricing: CheckoutPricing) -> [CheckoutSummaryRow] {
        let amounts = pricing.amounts
        let bundleCount = pricing.goods.bundleId == nil ? nil : pricing.goods.items.count
        var rows = [
            CheckoutSummaryRow(kind: .item(bundleCount: bundleCount), amount: amounts.itemPrice),
            CheckoutSummaryRow(kind: .protectionFee, amount: amounts.protectionFee),
            CheckoutSummaryRow(kind: .shipping(estimate: !pricing.fees.exact), amount: amounts.shippingFee),
        ]
        if let promo = pricing.promo {
            rows.append(CheckoutSummaryRow(kind: .promo(kind: promo.kind, code: promo.code), amount: -amounts.promoDiscount))
        }
        if amounts.voucherDiscount > 0 {
            rows.append(CheckoutSummaryRow(kind: .voucher, amount: -amounts.voucherDiscount))
        }
        if amounts.walletApplied > 0 {
            rows.append(CheckoutSummaryRow(kind: .total, amount: amounts.total))
            rows.append(CheckoutSummaryRow(kind: .wallet, amount: -amounts.walletApplied))
        }
        return rows
    }

    /// The payment list shows when something is left to pay and there is a choice (screens.md §7 G11).
    static func showsPaymentMethods(_ pricing: CheckoutPricing) -> Bool {
        pricing.amounts.amountDue > 0 && pricing.paymentMethods.count > 1
    }
}

/// The checkout button (screens.md §7 G11, Button).
enum CheckoutAction: Equatable, Sendable {
    /// No quote yet, or the form is not complete: "Payer …", disabled.
    case pending
    /// The wallet pays it all: "Confirmer la commande".
    case confirm
    /// "Commander — 1 910 DA à la livraison".
    case cashOnDelivery(amount: Int)
    /// "Payer 3 420 DA".
    case pay(amount: Int)

    var isCashOnDelivery: Bool {
        if case .cashOnDelivery = self { return true }
        return false
    }

    static func of(_ pricing: CheckoutPricing?) -> CheckoutAction {
        guard let pricing else { return .pending }
        if pricing.amounts.amountDue == 0 { return .confirm }
        if pricing.isCashOnDelivery { return .cashOnDelivery(amount: pricing.cashOnDelivery?.total ?? pricing.amounts.amountDue) }
        return .pay(amount: pricing.amounts.amountDue)
    }
}

// MARK: - Payment result

/// How the member came to the payment screen.
enum PaymentAttempt: Hashable, Sendable {
    /// The gateway's page handed back with `result=success` (only a hint).
    case returnedSuccess
    /// The gateway's page handed back with `result=failure`.
    case returnedFailure
    /// The member closed the payment page without coming back through it.
    case closed
    /// No payment page: cash on delivery, the wallet, an order opened again.
    case none
}

/// What the payment screen tells after the sync (slice D, After the sync).
enum PaymentOutcome: Equatable, Sendable {
    /// Paid online: "Paiement confirmé !".
    case paid
    /// Confirmed without a payment page: cash on delivery (`cash`) or the wallet.
    case confirmed(cash: CashCollection?)
    /// Back with success, but the gateway has not settled yet: a late confirmation still lands.
    case awaitingConfirmation
    /// The payment failed or was cancelled: "Paiement non abouti", with "Payer maintenant".
    case failed
    /// Waiting for payment, nothing tried in this visit: the deadline and "Payer maintenant".
    case awaitingPayment
    /// The payment deadline passed: the order was cancelled.
    case expired
    /// Another status (refunded, disputed, unknown): its label only.
    case other

    static func of(_ order: OrderPaymentInfo, attempt: PaymentAttempt) -> PaymentOutcome {
        switch order.status {
        case .pendingPayment:
            switch attempt {
            case .returnedSuccess: return .awaitingConfirmation
            case .returnedFailure, .closed: return .failed
            case .none: return .awaitingPayment
            }
        case .paid, .prepared, .shipped, .delivered, .completed:
            if let cash = order.cashOnDelivery { return .confirmed(cash: cash) }
            let walletOnly = order.amounts.walletApplied > 0 && order.amounts.walletApplied >= order.amounts.total
            return walletOnly ? .confirmed(cash: nil) : .paid
        case .cancelled: return .expired
        case .refunded, .disputed, .unknown: return .other
        }
    }

    /// Worth syncing again in a moment.
    var retriesSync: Bool { self == .awaitingConfirmation }
}

/// Whole days until the seller must ship, for "Le vendeur a maintenant {days} jours…" (at least 1).
func daysUntil(_ date: Date?, from now: Date = Date()) -> Int? {
    guard let date else { return nil }
    return max(1, Int((date.timeIntervalSince(now) / 86_400).rounded()))
}
