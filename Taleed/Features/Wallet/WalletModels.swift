import Foundation

// The app models of the wallet (screens.md §2 G14 and §7 G14, slice D "Wallet", slice F "Top-ups").
// Amounts, labels and limits come from the server (screens.md §0.1): the app only adds the balance and
// the vouchers for the headline, as the API asks.

/// `GET /wallet`: the header of the wallet screen.
struct WalletSummary: Equatable, Sendable {
    /// What can be spent and withdrawn. Negative after an adjustment by the Taleed team.
    let balance: Int
    /// Active vouchers: spent on orders on their own, never withdrawn.
    let voucherBalance: Int
    /// The member's sales paid but not completed yet.
    let pendingEscrow: Int
    /// The card gateways a top-up can use, in display order. Empty: no "Recharger".
    let topUpMethods: [PaymentChoice]
    let limits: WalletLimitsInfo

    /// The headline: "balance + voucherBalance" (slice D).
    var headline: Int { balance + voucherBalance }
}

/// The bounds of the wallet forms.
struct WalletLimitsInfo: Equatable, Sendable {
    let minPayout: Int
    let minTopUp: Int
    let maxTopUp: Int

    static let `default` = WalletLimitsInfo(minPayout: 100, minTopUp: 100, maxTopUp: 1_000_000)
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
    /// "Vente — fonds libérés", "Bon d’achat — parrainage"…, from the server.
    let label: String
    /// Signed: a credit is positive, a debit negative.
    let amount: Int
    /// The order number, a transfer reference, the gateway.
    let note: String?
    /// The order it is about: the line opens it.
    let orderId: String?
    let voucher: WalletVoucherInfo?
    let createdAt: Date
}

/// Where a payout request stands.
enum PayoutState: Equatable, Sendable {
    case requested, processing, paid, rejected, unknown
}

/// A line of `GET /wallet/payouts`, or the request just made.
struct PayoutRow: Identifiable, Equatable, Sendable {
    let id: String
    let amount: Int
    /// "CCP", "Virement bancaire (RIB)", from the server.
    let methodLabel: String
    let accountDetails: String
    let status: PayoutState
    /// "Demandé", "Versé"…, from the server.
    let statusLabel: String
    /// `PAID`: the transfer's reference.
    let reference: String?
    /// `PAID`: the receipt the Taleed team attached (an image or a PDF), opened in the browser.
    let proofURL: URL?
    let requestedAt: Date
    let processedAt: Date?
}

/// Where a top-up stands after a sync.
enum TopUpState: Equatable, Sendable {
    case pending, paid, failed, unknown
}

/// A top-up (`TopUp`).
struct TopUpInfo: Identifiable, Equatable, Sendable {
    let id: String
    let amount: Int
    let status: TopUpState
}

/// `POST /wallet/top-ups`: the top-up waiting for its payment and the gateway's page.
struct StartedTopUp: Equatable, Sendable {
    let topUp: TopUpInfo
    /// Nil when the server gave an address the app cannot open.
    let paymentURL: URL?
}

/// `POST /wallet/payouts`.
struct PayoutRequest: Equatable, Sendable {
    let amount: Int
    /// `CCP`, `RIB`, `BARIDIMOB`.
    let method: String
    /// Trimmed.
    let accountDetails: String
    /// The id of this submission: the same on a retry of the same request, a new one for another.
    let clientId: String
}
