import Foundation

// The app models of Earnings (slice H; the website's `/wallet` page). There is no stored balance: what is
// owed is paid by the weekly payout run to the payout details, never spent or withdrawn in the app.
// Amounts, labels, limits and dates come from the server (screens.md §0.1).

/// `GET /wallet`: the header of Earnings.
struct WalletSummary: Equatable, Sendable {
    /// Owed to the member and not in a payout yet. Negative after an adjustment by the Taleed team.
    let owed: Int
    /// Payouts created by the weekly run and not sent yet.
    let inPayout: Int
    /// Sales paid and not completed yet: owed once each order completes.
    let inProgress: Int
    /// Active vouchers: each takes money off one order on its own, never paid out.
    let voucherBalance: Int
    /// The next weekly payout run (Monday 08:00, Algiers).
    let nextPayoutAt: Date
    /// Nil until the member saves payout details.
    var payoutAccount: PayoutAccountInfo?
    let limits: WalletLimitsInfo
}

/// Where the weekly run sends the payouts and where bank refunds go (`PayoutAccount`).
struct PayoutAccountInfo: Equatable, Sendable {
    /// `CCP`, `RIB`, `BARIDIMOB`.
    let method: String
    /// "CCP", "Bank transfer (RIB)", from the server.
    let methodLabel: String
    /// As the member wrote it.
    let accountDetails: String
    let updatedAt: Date
}

/// The bounds that Earnings shows and checks (`WalletLimits`).
struct WalletLimitsInfo: Equatable, Sendable {
    /// The weekly run pays `owed` from this amount.
    let minPayout: Int
    /// The account details' length once trimmed.
    let payoutDetailsMin: Int
    let payoutDetailsMax: Int
    /// Vouchers apply to orders from this item price.
    let voucherMinItemPrice: Int
    /// The value of one voucher, for the voucher rules.
    let voucherAmount: Int
    /// Days a voucher stays usable once granted, for the voucher rules.
    let voucherValidityDays: Int

    static let `default` = WalletLimitsInfo(minPayout: 100, payoutDetailsMin: 5, payoutDetailsMax: 300, voucherMinItemPrice: 1500,
                                            voucherAmount: 500, voucherValidityDays: 365)
}

/// What a history line is about; picks the icon only (the server writes the label).
enum WalletEntryKind: Equatable, Sendable {
    case saleRelease, payout, adjustment, refundDebit, topUp, purchase, purchaseRefund, voucher
    /// A type added after this build: shown with its label and a neutral icon.
    case unknown
}

/// Where a voucher of the history stands.
enum VoucherStanding: Equatable, Sendable {
    case active, used, expired, unknown
}

/// The voucher part of a `VOUCHER` history line.
struct WalletVoucherInfo: Equatable, Sendable {
    let status: VoucherStanding
    /// "Utilisable dès 1500 DA d’achat", "Utilisé", "Expiré".
    let statusLabel: String
    /// While active: "Expire le {date}".
    let expiresAt: Date?
}

/// A line of `GET /wallet/history`.
struct WalletEntryRow: Identifiable, Equatable, Sendable {
    let id: String
    let kind: WalletEntryKind
    /// "Sale completed", "Payout sent", "Referral voucher"…, from the server.
    let label: String
    /// Signed: a credit is positive, a debit negative.
    let amount: Int
    /// The order number, a transfer reference.
    let note: String?
    /// The order it is about: the line opens it.
    let orderId: String?
    let voucher: WalletVoucherInfo?
    let createdAt: Date
}

/// Where a payout stands.
enum PayoutState: Equatable, Sendable {
    case requested, processing, paid, rejected, unknown
}

/// A line of `GET /wallet/payouts`: a payout the weekly run created.
struct PayoutRow: Identifiable, Equatable, Sendable {
    let id: String
    let amount: Int
    /// "CCP", "Bank transfer (RIB)", from the server.
    let methodLabel: String
    let status: PayoutState
    /// "Created", "Being sent", "Sent", "Rejected", from the server.
    let statusLabel: String
    /// `PAID`: the transfer's reference.
    let reference: String?
    /// `PAID`: the receipt the Taleed team attached (an image or a PDF), opened in the browser.
    let proofURL: URL?
    /// When the weekly run created it.
    let requestedAt: Date
    let processedAt: Date?
}
