import SwiftUI
import TaleedAPI

/// The calls of the wallet screens (screens.md §2 G14, slice D "Wallet", slice F "Top-ups").
@MainActor
protocol WalletApi: AnyObject {
    /// `GET /wallet`. `automatic`: a refresh the member did not ask for (back in the foreground).
    func wallet(automatic: Bool) async throws(ApiError) -> WalletSummary
    /// `GET /wallet/history`: newest first, 20 a page; vouchers granted are lines too.
    func history(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<WalletEntryRow>
    /// `GET /wallet/payouts`: newest first, 20 a page.
    func payouts(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<PayoutRow>
    /// `POST /wallet/payouts`. A repeat with the same `clientId` and body answers the request already
    /// made; another body with that `clientId` is `400 invalid_request` on `body.clientId`.
    func requestPayout(_ request: PayoutRequest) async throws(ApiError) -> PayoutRow
    /// `POST /wallet/top-ups`: a top-up waiting for its payment, and the gateway's page.
    func startTopUp(amount: Int, method: String) async throws(ApiError) -> StartedTopUp
    /// `POST /wallet/top-ups/{id}/sync`: asks the gateway; repeated freely.
    func syncTopUp(id: String) async throws(ApiError) -> TopUpInfo
    /// `GET /wallet/top-ups`, the first page: the member's latest top-ups, website ones included.
    func recentTopUps() async throws(ApiError) -> [TopUpInfo]
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

    func requestPayout(_ request: PayoutRequest) async throws(ApiError) -> PayoutRow {
        let body = PayoutCreate(amount: request.amount, method: PayoutMethod(rawValue: request.method) ?? .unknownDefaultOpenApi,
                                accountDetails: request.accountDetails, clientId: request.clientId)
        // The `clientId` makes a repeat answer the request already made (slice D): safe to repeat
        // after no answer, like the other `clientId` actions.
        return PayoutRow(try await caller.call(.read) { try await WalletAPI.requestPayout(payoutCreate: body, apiConfiguration: $0) })
    }

    func startTopUp(amount: Int, method: String) async throws(ApiError) -> StartedTopUp {
        let body = TopUpCreate(amount: amount, method: PaymentMethod(rawValue: method) ?? .unknownDefaultOpenApi)
        // Each call starts another top-up: the member's tap only.
        let started = try await caller.call(.write) { try await WalletAPI.startTopUp(topUpCreate: body, apiConfiguration: $0) }
        return StartedTopUp(topUp: TopUpInfo(started.topUp), paymentURL: URL(apiString: started.paymentUrl))
    }

    func syncTopUp(id: String) async throws(ApiError) -> TopUpInfo {
        TopUpInfo(try await caller.call(.read) { try await WalletAPI.syncTopUp(id: id, apiConfiguration: $0) })
    }

    func recentTopUps() async throws(ApiError) -> [TopUpInfo] {
        let page = try await caller.call(.read, automatic: true) { try await WalletAPI.listTopUps(apiConfiguration: $0) }
        return page.items.map(TopUpInfo.init)
    }
}

// MARK: Mapping

extension WalletSummary {
    init(_ wallet: Wallet) {
        self.init(
            balance: wallet.balance,
            voucherBalance: wallet.voucherBalance,
            pendingEscrow: wallet.pendingEscrow,
            // A gateway added after this build cannot be sent back: left out.
            topUpMethods: wallet.topUpMethods.compactMap {
                $0.value == .unknownDefaultOpenApi ? nil : PaymentChoice(value: $0.value.rawValue, label: $0.label, hint: $0.hint)
            },
            limits: WalletLimitsInfo(minPayout: wallet.limits.minPayout, minTopUp: wallet.limits.minTopUp,
                                     maxTopUp: wallet.limits.maxTopUp)
        )
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
        self.init(id: payout.id, amount: payout.amount, methodLabel: payout.methodLabel, accountDetails: payout.accountDetails,
                  status: status, statusLabel: payout.statusLabel,
                  reference: payout.reference?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                  proofURL: URL(apiString: payout.proofUrl), requestedAt: payout.requestedAt, processedAt: payout.processedAt)
    }
}

extension TopUpInfo {
    init(_ topUp: TopUp) {
        let status: TopUpState = switch topUp.status {
        case .pending: .pending
        case .paid: .paid
        case .failed: .failed
        case .unknownDefaultOpenApi: .unknown
        }
        self.init(id: topUp.id, amount: topUp.amount, status: status)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: Dependencies

/// The wallet's API, set once at the root (`AppRootView`).
private struct WalletApiKey: EnvironmentKey {
    static var defaultValue: (any WalletApi)? { nil }
}

extension EnvironmentValues {
    var walletApi: (any WalletApi)? {
        get { self[WalletApiKey.self] }
        set { self[WalletApiKey.self] = newValue }
    }
}
