import SwiftUI
import TaleedAPI

/// The calls of Earnings (slice H; the API paths keep `/wallet`). All of `/wallet` is open to suspended
/// members.
@MainActor
protocol WalletApi: AnyObject {
    /// `GET /wallet`. `automatic`: a refresh the member did not ask for (back in the foreground).
    func wallet(automatic: Bool) async throws(ApiError) -> WalletSummary
    /// `GET /wallet/history`: newest first, 20 a page; vouchers granted are lines too.
    func history(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<WalletEntryRow>
    /// `GET /wallet/payouts`: the payouts the weekly run created, newest first, 20 a page.
    func payouts(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<PayoutRow>
    /// `PUT /wallet/payout-account`: saves the payout details (trimmed by the caller). A change never
    /// alters the payouts already created.
    func savePayoutAccount(method: String, accountDetails: String) async throws(ApiError) -> PayoutAccountInfo
    /// The voucher rules' numbers, from `program` of `GET /me/referrals` (not open to suspended members).
    func voucherRules(automatic: Bool) async throws(ApiError) -> VoucherRulesInfo
}

extension WalletApi {
    func wallet() async throws(ApiError) -> WalletSummary { try await wallet(automatic: false) }
}

extension GeneratedTaleedApi: WalletApi {
    func wallet(automatic: Bool) async throws(ApiError) -> WalletSummary {
        WalletSummary(try await caller.call(.read, automatic: automatic) { try await WalletAPI.getWallet(apiConfiguration: $0) })
    }

    func history(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<WalletEntryRow> {
        let page = try await caller.call(.read, automatic: automatic) {
            try await WalletAPI.listWalletHistory(cursor: cursor, apiConfiguration: $0)
        }
        return Page(items: page.items.map(WalletEntryRow.init), nextCursor: page.nextCursor, total: page.total)
    }

    func payouts(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<PayoutRow> {
        let page = try await caller.call(.read, automatic: automatic) {
            try await WalletAPI.listPayouts(cursor: cursor, apiConfiguration: $0)
        }
        return Page(items: page.items.map(PayoutRow.init), nextCursor: page.nextCursor, total: page.total)
    }

    func savePayoutAccount(method: String, accountDetails: String) async throws(ApiError) -> PayoutAccountInfo {
        let body = PayoutAccountUpdate(method: PayoutMethod(rawValue: method) ?? .unknownDefaultOpenApi, accountDetails: accountDetails)
        // A `PUT` of the same body gives the same result: safe to repeat after no answer.
        return PayoutAccountInfo(try await caller.call(.read) {
            try await WalletAPI.savePayoutAccount(payoutAccountUpdate: body, apiConfiguration: $0)
        })
    }

    func voucherRules(automatic: Bool) async throws(ApiError) -> VoucherRulesInfo {
        let program = try await referrals(cursor: nil, automatic: automatic).program
        return VoucherRulesInfo(voucherAmount: program.voucherAmount, minItemPrice: program.minItemPrice,
                                validityDays: program.voucherValidityDays)
    }
}

// MARK: Mapping

extension WalletSummary {
    init(_ wallet: Wallet) {
        self.init(
            owed: wallet.owed,
            inPayout: wallet.inPayout,
            inProgress: wallet.inProgress,
            voucherBalance: wallet.voucherBalance,
            nextPayoutAt: wallet.nextPayoutAt,
            payoutAccount: wallet.payoutAccount.map(PayoutAccountInfo.init),
            limits: WalletLimitsInfo(minPayout: wallet.limits.minPayout, payoutDetailsMin: wallet.limits.payoutDetailsMin,
                                     payoutDetailsMax: wallet.limits.payoutDetailsMax,
                                     voucherMinItemPrice: wallet.limits.voucherMinItemPrice)
        )
    }
}

extension PayoutAccountInfo {
    init(_ account: PayoutAccount) {
        self.init(method: account.method.rawValue, methodLabel: account.methodLabel, accountDetails: account.accountDetails,
                  updatedAt: account.updatedAt)
    }
}

extension WalletEntryRow {
    init(_ entry: WalletEntry) {
        let kind: WalletEntryKind = switch entry.type {
        case .saleRelease: .saleRelease
        case .payout: .payout
        case .adjustment: .adjustment
        case .refundDebit: .refundDebit
        case .topUp: .topUp
        case .purchase: .purchase
        case .purchaseRefund: .purchaseRefund
        case .voucher: .voucher
        case .unknownDefaultOpenApi: .unknown
        }
        self.init(id: entry.id, kind: kind, label: entry.label, amount: entry.amount,
                  note: entry.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                  orderId: entry.orderId, voucher: entry.voucher.map(WalletVoucherInfo.init), createdAt: entry.createdAt)
    }
}

extension WalletVoucherInfo {
    init(_ voucher: VoucherState) {
        let status: VoucherStanding = switch voucher.status {
        case .active: .active
        case .used: .used
        case .expired: .expired
        case .unknownDefaultOpenApi: .unknown
        }
        self.init(status: status, statusLabel: voucher.statusLabel, expiresAt: voucher.expiresAt)
    }
}

extension PayoutRow {
    init(_ payout: Payout) {
        let status: PayoutState = switch payout.status {
        case .requested: .requested
        case .processing: .processing
        case .paid: .paid
        case .rejected: .rejected
        case .unknownDefaultOpenApi: .unknown
        }
        self.init(id: payout.id, amount: payout.amount, methodLabel: payout.methodLabel,
                  status: status, statusLabel: payout.statusLabel,
                  reference: payout.reference?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                  proofURL: URL(apiString: payout.proofUrl), requestedAt: payout.requestedAt, processedAt: payout.processedAt)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: Dependencies

/// The Earnings API, set once at the root (`AppRootView`).
private struct WalletApiKey: EnvironmentKey {
    static var defaultValue: (any WalletApi)? { nil }
}

extension EnvironmentValues {
    var walletApi: (any WalletApi)? {
        get { self[WalletApiKey.self] }
        set { self[WalletApiKey.self] = newValue }
    }
}
