import Foundation
@testable import Taleed
import TaleedAPI

// MARK: - Fixtures

let walletNextRun = Date(timeIntervalSince1970: 1_793_602_800)

let walletAccount = PayoutAccountInfo(method: "CCP", methodLabel: "CCP", accountDetails: "0012345678 clé 90",
                                      updatedAt: Date(timeIntervalSince1970: 1_760_000_000))

func walletSummary(owed: Int = 4200, inPayout: Int = 1500, inProgress: Int = 3000, vouchers: Int = 0,
                   account: PayoutAccountInfo? = walletAccount, minPayout: Int = 100) -> WalletSummary {
    WalletSummary(owed: owed, inPayout: inPayout, inProgress: inProgress, voucherBalance: vouchers, nextPayoutAt: walletNextRun,
                  payoutAccount: account,
                  limits: WalletLimitsInfo(minPayout: minPayout, payoutDetailsMin: 5, payoutDetailsMax: 300, voucherMinItemPrice: 1500))
}

func walletEntry(_ id: String, kind: WalletEntryKind = .saleRelease, amount: Int = 5000, note: String? = "T-000010",
                 orderId: String? = nil, voucher: WalletVoucherInfo? = nil,
                 date: Date = Date(timeIntervalSince1970: 1_760_000_000)) -> WalletEntryRow {
    WalletEntryRow(id: id, kind: kind, label: "Vente finalisée", amount: amount, note: note, orderId: orderId, voucher: voucher,
                   createdAt: date)
}

func walletPayout(_ id: String, amount: Int = 1000, status: PayoutState = .requested, reference: String? = nil) -> PayoutRow {
    PayoutRow(id: id, amount: amount, methodLabel: "CCP", status: status, statusLabel: "Créé", reference: reference, proofURL: nil,
              requestedAt: Date(timeIntervalSince1970: 1_760_000_000), processedAt: nil)
}

func walletFailure(_ code: ApiErrorCode, status: Int = 409, issues: [ApiFieldIssue] = []) -> Taleed.ApiError {
    .failed(ApiFailure(status: status, code: code, issues: issues))
}

/// The Earnings calls from canned results.
@MainActor
final class FakeWalletApi: WalletApi {
    var summaries: [Result<WalletSummary, Taleed.ApiError>] = []
    var defaultSummary = walletSummary()
    var historyItems = [walletEntry("e1"), walletEntry("e2", kind: .purchase, amount: -2000, note: "T-000010", orderId: "o1")]
    var payoutItems = [walletPayout("p1", status: .paid, reference: "VIR-2026-0042")]
    var saveResults: [Result<PayoutAccountInfo, Taleed.ApiError>] = []
    var program: Result<VoucherRulesInfo, Taleed.ApiError> = .success(
        VoucherRulesInfo(voucherAmount: 500, minItemPrice: 1500, validityDays: 365)
    )
    private(set) var summaryCalls = 0
    private(set) var historyCalls = 0
    private(set) var programCalls = 0
    private(set) var saved: [(method: String, accountDetails: String)] = []

    func wallet(automatic: Bool) async throws(Taleed.ApiError) -> WalletSummary {
        summaryCalls += 1
        if !summaries.isEmpty { return try summaries.removeFirst().get() }
        return defaultSummary
    }

    func history(cursor: String?, automatic: Bool) async throws(Taleed.ApiError) -> Page<WalletEntryRow> {
        historyCalls += 1
        return Page(items: historyItems, nextCursor: nil, total: historyItems.count)
    }

    func payouts(cursor: String?, automatic: Bool) async throws(Taleed.ApiError) -> Page<PayoutRow> {
        Page(items: payoutItems, nextCursor: nil, total: payoutItems.count)
    }

    func savePayoutAccount(method: String, accountDetails: String) async throws(Taleed.ApiError) -> PayoutAccountInfo {
        saved.append((method, accountDetails))
        if !saveResults.isEmpty { return try saveResults.removeFirst().get() }
        return PayoutAccountInfo(method: method, methodLabel: method, accountDetails: accountDetails, updatedAt: Date())
    }

    func voucherRules(automatic: Bool) async throws(Taleed.ApiError) -> VoucherRulesInfo {
        programCalls += 1
        return try program.get()
    }
}
