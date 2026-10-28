import Foundation
import TaleedAPI

/// What Earnings shows, decided from the server's numbers and flags (slice H; the website's `/wallet`).
enum WalletRules {
    /// The sentence under "Owed to you" that says why the next run will not pay it (the website's
    /// `owedNote`, in its order).
    enum OwedNote: Equatable, Sendable {
        /// Negative after an adjustment: "You owe this amount after an adjustment…"
        case negative
        /// Enough for the next run but no payout details: "Add your payout details to receive this amount."
        case needsDetails
        /// Under the minimum: "Payouts start from 100 DA: a smaller amount waits for a later week."
        case belowMinimum(Int)
    }

    static func owedNote(_ summary: WalletSummary) -> OwedNote? {
        if summary.owed < 0 { return .negative }
        if summary.owed >= summary.limits.minPayout, summary.payoutAccount == nil { return .needsDetails }
        if summary.owed > 0, summary.owed < summary.limits.minPayout { return .belowMinimum(summary.limits.minPayout) }
        return nil
    }

    /// "Paid with the next weekly payout, on {date}." The website shows it always; the app leaves it out
    /// for a negative amount, which the next run does not pay.
    static func showsNextPayoutDate(_ summary: WalletSummary) -> Bool {
        summary.owed >= 0
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
    /// destructive): the design-system badge has no outline, so a payout just created reads in the brand
    /// tone.
    static func payoutTone(_ status: PayoutState) -> TaleedTone {
        switch status {
        case .requested: .brand
        case .processing, .unknown: .neutral
        case .paid: .success
        case .rejected: .error
        }
    }

    /// The voucher rules' numbers: the program's when it is known, otherwise the server's current values
    /// with the minimum item price of `GET /wallet` (a suspended member gets no program).
    static func voucherRules(program: VoucherRulesInfo?, limits: WalletLimitsInfo) -> VoucherRulesInfo {
        program ?? VoucherRulesInfo(voucherAmount: VoucherRulesInfo.fallbackAmount, minItemPrice: limits.voucherMinItemPrice,
                                    validityDays: VoucherRulesInfo.fallbackValidityDays)
    }
}

extension VoucherRulesInfo {
    /// The server's `REFERRAL_VOUCHER_AMOUNT` and `VOUCHER_EXPIRY_DAYS` (slice H), used only while the
    /// program of `GET /me/referrals` is not there.
    static let fallbackAmount = 500
    static let fallbackValidityDays = 365
}

/// Text of the Earnings lines.
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
    /// "Utilisable dès 1500 DA d’achat · 4 oct. 2026 · Expire le 4 oct. 2027". A card payment line (an
    /// old top-up) carries the gateway's id as its note: no note then, as it means nothing to the member.
    static func entryDetail(_ entry: WalletEntryRow, locale: Locale, expires: (String) -> String) -> String {
        let date = OrderText.date(entry.createdAt, locale: locale)
        if let voucher = entry.voucher {
            var parts = [voucher.statusLabel, date]
            if voucher.status == .active, let expiresAt = voucher.expiresAt {
                parts.append(expires(OrderText.date(expiresAt, locale: locale)))
            }
            return parts.joined(separator: separator)
        }
        let note = entry.kind == .topUp ? nil : entry.note?.isolatedLeftToRight
        return [note, date].compactMap { $0 }.joined(separator: separator)
    }

    /// A payout's second line: "CCP · 4 oct. 2026, 14:32 · VIR-2026-0042".
    static func payoutDetail(_ payout: PayoutRow, locale: Locale) -> String {
        [payout.methodLabel, OrderText.dateTime(payout.requestedAt, locale: locale), payout.reference?.isolatedLeftToRight]
            .compactMap { $0 }
            .joined(separator: separator)
    }
}

/// The payout details form (slice H; the website's `PayoutAccountForm`): a method and the account details,
/// `payoutDetailsMin` to `payoutDetailsMax` characters once trimmed. No per-method format check (neither
/// the website nor the API has one). The API decides in the end.
struct PayoutDetailsInput: Equatable {
    var method: String
    var accountDetails: String
    let minLength: Int
    let maxLength: Int

    /// The website's first method.
    static let defaultMethod = "CCP"
    /// The field takes a little more than the maximum, as the website's (`maxLength + 20`), so that a text
    /// pasted too long shows the error rather than being cut without a word.
    static let overflowAllowance = 20

    /// Prefilled with the saved details, else the default method (or the first one offered) and nothing.
    init(account: PayoutAccountInfo?, methods: [String], limits: WalletLimitsInfo) {
        let fallback = methods.contains(Self.defaultMethod) ? Self.defaultMethod : (methods.first ?? Self.defaultMethod)
        method = account.map(\.method).flatMap { methods.isEmpty || methods.contains($0) ? $0 : nil } ?? fallback
        accountDetails = account?.accountDetails ?? ""
        minLength = limits.payoutDetailsMin
        maxLength = limits.payoutDetailsMax
    }

    var trimmedDetails: String { accountDetails.trimmingCharacters(in: .whitespacesAndNewlines) }

    var detailsAreValid: Bool {
        guard minLength <= maxLength else { return false }
        return (minLength...maxLength).contains(trimmedDetails.count)
    }

    /// What the field accepts while typing.
    var inputLimit: Int { maxLength + Self.overflowAllowance }

    /// "Enter 5 to 300 characters." turns red under the field once something is typed and the length is
    /// out of bounds, as the website's form; an empty field is not an error (the button waits).
    var showsLengthError: Bool {
        !trimmedDetails.isEmpty && !detailsAreValid
    }

    /// "Save" is enabled once the details are valid.
    var isValid: Bool { !method.isEmpty && detailsAreValid }
}
