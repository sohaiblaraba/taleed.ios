import Foundation
@testable import Taleed
import TaleedAPI

// MARK: - Fixtures

let walletMockMethod = PaymentChoice(value: "mock", label: "Paiement simulé", hint: "Environnement de test")

func walletSummary(balance: Int = 7500, vouchers: Int = 0, pending: Int = 5500, methods: [PaymentChoice] = [walletMockMethod],
                   minPayout: Int = 100) -> WalletSummary {
    WalletSummary(balance: balance, voucherBalance: vouchers, pendingEscrow: pending, topUpMethods: methods,
                  limits: WalletLimitsInfo(minPayout: minPayout, minTopUp: 100, maxTopUp: 1_000_000))
}

func walletEntry(_ id: String, kind: WalletEntryKind = .topUp, amount: Int = 5000, note: String? = "mock",
                 orderId: String? = nil, voucher: WalletVoucherInfo? = nil,
                 date: Date = Date(timeIntervalSince1970: 1_760_000_000)) -> WalletEntryRow {
    WalletEntryRow(id: id, kind: kind, label: "Rechargement", amount: amount, note: note, orderId: orderId, voucher: voucher,
                   createdAt: date)
}

func walletPayout(_ id: String, amount: Int = 1000, status: PayoutState = .requested, reference: String? = nil) -> PayoutRow {
    PayoutRow(id: id, amount: amount, methodLabel: "CCP", accountDetails: "0012345678 clé 90", status: status,
              statusLabel: "Demandé", reference: reference, proofURL: nil, requestedAt: Date(timeIntervalSince1970: 1_760_000_000),
              processedAt: nil)
}

func walletFailure(_ code: ApiErrorCode, status: Int = 409, issues: [ApiFieldIssue] = []) -> Taleed.ApiError {
    .failed(ApiFailure(status: status, code: code, issues: issues))
}

/// The wallet calls from canned results.
@MainActor
final class FakeWalletApi: WalletApi {
    var summaries: [Result<WalletSummary, Taleed.ApiError>] = []
    var defaultSummary = walletSummary()
    var historyItems = [walletEntry("e1"), walletEntry("e2", kind: .purchase, amount: -2000, note: "T-000010", orderId: "o1")]
    var payoutItems = [walletPayout("p1", status: .paid, reference: "VIR-2026-0042")]
    var payoutResults: [Result<PayoutRow, Taleed.ApiError>] = []
    var startResult: Result<StartedTopUp, Taleed.ApiError> = .success(
        StartedTopUp(topUp: TopUpInfo(id: "t1", amount: 5000, status: .pending), paymentURL: URL(string: "http://localhost:3000/pay/t1"))
    )
    var syncResults: [String: [Result<TopUpInfo, Taleed.ApiError>]] = [:]
    var recent: [TopUpInfo] = []
    private(set) var summaryCalls = 0
    private(set) var historyCalls = 0
    private(set) var payoutRequests: [PayoutRequest] = []
    private(set) var syncCalls: [String] = []

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

    func requestPayout(_ request: PayoutRequest) async throws(Taleed.ApiError) -> PayoutRow {
        payoutRequests.append(request)
        if !payoutResults.isEmpty { return try payoutResults.removeFirst().get() }
        let row = walletPayout("new\(payoutRequests.count)", amount: request.amount)
        payoutItems.insert(row, at: 0)
        return row
    }

    func startTopUp(amount: Int, method: String) async throws(Taleed.ApiError) -> StartedTopUp { try startResult.get() }

    func syncTopUp(id: String) async throws(Taleed.ApiError) -> TopUpInfo {
        syncCalls.append(id)
        if var results = syncResults[id], !results.isEmpty {
            let result = results.removeFirst()
            syncResults[id] = results
            return try result.get()
        }
        return TopUpInfo(id: id, amount: 5000, status: .pending)
    }

    func recentTopUps() async throws(Taleed.ApiError) -> [TopUpInfo] { recent }
}
