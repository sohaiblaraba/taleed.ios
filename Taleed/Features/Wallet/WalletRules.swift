import Foundation
import TaleedAPI

/// What the wallet screen shows, decided from the server's numbers and flags (screens.md §7 G14).
enum WalletRules {
    /// "Demander un virement" is disabled while the balance is under the minimum (screens.md §7 G14
    /// correction); "Minimum : 100 DA" then shows under it. Vouchers never count: they cannot be withdrawn.
    static func canRequestPayout(_ summary: WalletSummary) -> Bool {
        summary.balance >= summary.limits.minPayout
    }

    /// "Recharger" only when a card gateway can take a top-up (slice D: empty hides it).
    static func showsTopUp(_ summary: WalletSummary) -> Bool {
        !summary.topUpMethods.isEmpty
    }

    /// The top-up form picks a method only when there is more than one (the website's dialog).
    static func showsTopUpMethodPicker(_ summary: WalletSummary) -> Bool {
        summary.topUpMethods.count > 1
    }

    /// "dont 500 DA en bons d’achat (non retirables)" under the headline.
    static func showsVoucherPart(_ summary: WalletSummary) -> Bool {
        summary.voucherBalance > 0
    }

    /// The colour of a history amount.
    enum AmountTone: Equatable {
        /// Green, "+".
        case credit
        /// Red, "−".
        case debit
        /// A voucher used or expired: "+", muted.
        case muted
    }

    /// Ledger lines: green with "+" from 0 up, red below. Vouchers: always "+", green only while active.
    static func amountTone(_ entry: WalletEntryRow) -> AmountTone {
        if let voucher = entry.voucher {
            return voucher.status == .active ? .credit : .muted
        }
        if entry.kind == .voucher { return .muted }
        return entry.amount >= 0 ? .credit : .debit
    }

    /// The badge of a payout's status, after the website's variants (outline, secondary, success,
    /// destructive): the design-system badge has no outline, so a request waiting reads in the brand tone.
    static func payoutTone(_ status: PayoutState) -> TaleedTone {
        switch status {
        case .requested: .brand
        case .processing, .unknown: .neutral
        case .paid: .success
        case .rejected: .error
        }
    }
}

/// Text of the wallet lines.
enum WalletText {
    private static let rightToLeftMark = "\u{200F}"
    private static let leftToRightMark = "\u{200E}"
    /// " · " between the parts of a line, with no-break spaces: the dot never ends or starts a line.
    static let separator = "\u{00A0}·\u{00A0}"

    /// "+5 000 DA" or "-2 000 DA" (the website's `+` before credits). In Arabic the sign stays before the
    /// digits, as the price formatter writes a negative amount.
    static func signedAmount(_ amount: Int, language: AppLanguage) -> String {
        let formatted = PriceFormatter.format(amount, language: language)
        guard amount >= 0 else { return formatted }
        guard formatted.hasPrefix(rightToLeftMark) else { return "+" + formatted }
        return rightToLeftMark + leftToRightMark + "+" + String(formatted.unicodeScalars.dropFirst())
    }

    /// A history line's second line: "T-000104 · 4 oct. 2026" (a date, not a relative time). Vouchers:
    /// "Utilisable dès 1500 DA d’achat · 4 oct. 2026 · Expire le 4 oct. 2027".
    static func entryDetail(_ entry: WalletEntryRow, locale: Locale, expires: (String) -> String) -> String {
        let date = OrderText.date(entry.createdAt, locale: locale)
        if let voucher = entry.voucher {
            var parts = [voucher.statusLabel, date]
            if voucher.status == .active, let expiresAt = voucher.expiresAt {
                parts.append(expires(OrderText.date(expiresAt, locale: locale)))
            }
            return parts.joined(separator: separator)
        }
        return [entry.note?.isolatedLeftToRight, date].compactMap { $0 }.joined(separator: separator)
    }

    /// A payout's second line: "CCP · 4 oct. 2026, 14:32 · VIR-2026-0042" (the time tells apart requests
    /// of the same amount made the same day).
    static func payoutDetail(_ payout: PayoutRow, locale: Locale) -> String {
        [payout.methodLabel, OrderText.dateTime(payout.requestedAt, locale: locale), payout.reference?.isolatedLeftToRight]
            .compactMap { $0 }
            .joined(separator: separator)
    }
}

/// An amount typed in a wallet form, checked against its bounds before sending. The API decides in
/// the end (`insufficient_balance`, `invalid_request`).
enum WalletAmountInput: Equatable {
    case empty
    case invalid
    case valid(Int)

    /// `range` nil: no amount can be valid (a balance under the minimum payout).
    init(text: String, range: ClosedRange<Int>?) {
        let digits = OfferAmountInput.normalizedDigits(text)
        guard !digits.isEmpty else {
            self = .empty
            return
        }
        guard let amount = Int(digits), let range, range.contains(amount) else {
            self = .invalid
            return
        }
        self = .valid(amount)
    }

    var amount: Int? {
        if case let .valid(amount) = self { return amount }
        return nil
    }
}

/// The payout form (screens.md §7 G14 "Payout dialog"): the amount from the minimum up to the balance,
/// a method, and the account details, 5 to 300 characters once trimmed. No per-method format check
/// (neither the website nor the API has one).
struct PayoutFormInput: Equatable {
    var amountText: String
    var method: String
    var accountDetails: String
    /// Follows the header: a refused amount reloads it.
    var balance: Int
    let minPayout: Int

    static let detailsMinLength = PayoutCreate.accountDetailsRule.minLength ?? 5
    static let detailsMaxLength = PayoutCreate.accountDetailsRule.maxLength ?? 300
    /// The website's first method.
    static let defaultMethod = "CCP"

    /// Prefilled with the whole balance, as the website.
    init(balance: Int, minPayout: Int, method: String = PayoutFormInput.defaultMethod) {
        self.balance = balance
        self.minPayout = minPayout
        self.method = method
        amountText = balance > 0 ? String(balance) : ""
        accountDetails = ""
    }

    var amountRange: ClosedRange<Int>? {
        minPayout <= balance ? minPayout...balance : nil
    }

    var amount: WalletAmountInput { WalletAmountInput(text: amountText, range: amountRange) }

    var trimmedDetails: String { accountDetails.trimmingCharacters(in: .whitespacesAndNewlines) }

    var detailsAreValid: Bool {
        (Self.detailsMinLength...Self.detailsMaxLength).contains(trimmedDetails.count)
    }

    /// "Envoyer la demande" is enabled once the three are valid.
    var isValid: Bool { amount.amount != nil && !method.isEmpty && detailsAreValid }
}

/// The `clientId` of payout requests: the same for a retry of the same request (an answer that never
/// came), a new one for any other request. A reused `clientId` with another body is refused
/// (`400 invalid_request` on `body.clientId`, screens.md §7 G14).
struct PayoutSubmission {
    private var last: PayoutRequest?
    private let makeId: () -> String

    init(makeId: @escaping () -> String = { UUID().uuidString }) {
        self.makeId = makeId
    }

    mutating func request(amount: Int, method: String, accountDetails: String) -> PayoutRequest {
        if let last, last.amount == amount, last.method == method, last.accountDetails == accountDetails {
            return last
        }
        let request = PayoutRequest(amount: amount, method: method, accountDetails: accountDetails, clientId: makeId())
        last = request
        return request
    }

    /// The request went through or was refused: the next one is new.
    mutating func reset() {
        last = nil
    }
}

/// The top-up form (screens.md §7 G14 "Top-up dialog"): 1 000 DA prefilled, any whole amount between the
/// limits (the website's step of 50 is HTML only), and the first method unless the member picks another.
struct TopUpFormInput: Equatable {
    var amountText: String
    var method: String?
    let limits: WalletLimitsInfo

    static let defaultAmount = 1000

    init(limits: WalletLimitsInfo, methods: [PaymentChoice]) {
        self.limits = limits
        amountText = String(Self.defaultAmount)
        method = methods.first?.value
    }

    var amountRange: ClosedRange<Int>? {
        limits.minTopUp <= limits.maxTopUp ? limits.minTopUp...limits.maxTopUp : nil
    }

    var amount: WalletAmountInput { WalletAmountInput(text: amountText, range: amountRange) }

    var isValid: Bool { amount.amount != nil && method != nil }
}

/// The result banner after a top-up's sync (the website's wallet banners).
enum TopUpBanner: Equatable {
    /// "Vérification du paiement…" while the sync runs.
    case checking
    /// "Paiement confirmé — votre solde a été crédité."
    case paid
    /// "Paiement non confirmé…": the gateway has not settled it yet.
    case pending
    /// "Le paiement a échoué ou a été annulé. Aucun montant n’a été débité."
    case failed

    init(_ state: TopUpState) {
        switch state {
        case .paid: self = .paid
        case .failed: self = .failed
        // A status added after this build: as not settled yet.
        case .pending, .unknown: self = .pending
        }
    }
}
