import Foundation
import Observation

/// The order screen, buyer side (screens.md §2 G12 screens 2–3 and §7 G12; slice D "The order screen",
/// "Actions", "Receiving", "Cancelling"): `GET /orders/{id}`, then the buyer's buttons from `actions`
/// only. Every action answers the order, shown at once. An action that no longer applies
/// (`invalid_state`, `dispute_exists`, `already_reviewed`) reloads the order and says so; one that lost
/// its connection or failed on the server may have happened anyway, so the order reloads first.
/// There is no live stream: it reloads on pull, on return to the foreground, and when shown again.
@MainActor
@Observable
final class OrderDetailViewModel {
    /// A running action, to show its spinner and keep the other buttons still.
    enum Busy: Equatable {
        case paying, cancelling, confirming
    }

    /// Something to tell in a toast.
    enum Notice: Equatable {
        case success(L10nKey)
        /// After the payment page: the order is paid, still waits, or the payment failed.
        case payment(L10nKey, kind: TaleedFeedbackKind)
        case error(ApiError)
    }

    let orderId: String
    private(set) var order: OrderDetailInfo?
    /// The first load failed: an error with Retry (`404`: "no longer available").
    private(set) var loadError: ApiError?
    private(set) var isLoading = false
    private(set) var busy: Busy?
    /// Whether the payment page is open.
    private(set) var isInPaymentPage = false
    var notice: Notice?

    @ObservationIgnored private let api: OrdersApi
    @ObservationIgnored private let followUpDelay: Duration
    @ObservationIgnored private var hasAppeared = false

    init(orderId: String, api: OrdersApi, followUpDelay: Duration = .seconds(3)) {
        self.orderId = orderId
        self.api = api
        self.followUpDelay = followUpDelay
    }

    var buyerActions: [OrderRules.BuyerAction] {
        guard let order, order.side == .buyer else { return [] }
        return OrderRules.buyerActions(order.actions)
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard order == nil, loadError == nil, !isLoading else { return }
        await load()
    }

    func retry() async {
        loadError = nil
        await load()
    }

    /// Shown again (back from the dispute thread, a conversation): quietly up to date.
    func appeared() async {
        guard hasAppeared else {
            hasAppeared = true
            return
        }
        await reload(automatic: true)
    }

    /// Pull-to-refresh, the foreground, a changed answer: the order again. `automatic` keeps quiet on
    /// failure; otherwise a failure while the order is on screen shows a toast.
    func reload(automatic: Bool = false) async {
        guard order != nil else {
            await load()
            return
        }
        do {
            order = try await api.order(id: orderId, automatic: automatic)
        } catch {
            if error.isNotFound {
                order = nil
                loadError = error
            } else if !automatic {
                notice = .error(error)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            #if DEBUG
            try debugFailFirstLoad()
            #endif
            order = try await api.order(id: orderId)
            loadError = nil
        } catch {
            loadError = error
        }
    }

    /// The new order an action, a review or a payment sync answered.
    func show(_ order: OrderDetailInfo) {
        guard order.id == orderId else { return }
        self.order = order
    }

    // MARK: Buyer actions

    /// "Annuler la commande", once confirmed.
    func cancel() async {
        await run(.cancelling, success: .ordersCancelled)
    }

    /// "Confirmer la réception", once confirmed: the order is completed and the seller paid.
    func confirmReceipt() async {
        await run(.confirming, success: .ordersReceiptConfirmed)
    }

    private func run(_ action: Busy, success: L10nKey) async {
        guard busy == nil else { return }
        busy = action
        defer { busy = nil }
        do {
            switch action {
            case .cancelling: order = try await api.cancel(orderId: orderId)
            case .confirming: order = try await api.confirmReceipt(orderId: orderId)
            case .paying: return
            }
            notice = .success(success)
        } catch {
            await actionFailed(error)
        }
    }

    /// A refused or lost action: the order moved on, or may have changed anyway. Reload, then say why.
    func actionFailed(_ error: ApiError) async {
        if Self.reloadsAfter(error) { await reload(automatic: true) }
        notice = .error(error)
    }

    /// Errors after which the order on screen may be out of date (slice D, Retrying and Other errors).
    nonisolated static func reloadsAfter(_ error: ApiError) -> Bool {
        switch error.code {
        case .invalidState, .disputeExists, .alreadyReviewed, .forbidden, .notFound: return true
        default: return error == .network || (error.status ?? 0) >= 500
        }
    }

    // MARK: Paying

    /// "Payer maintenant": a new page from the gateway (`POST /orders/{id}/payment`). Nil when there is
    /// none (the toast says why; the order is reloaded when it moved on).
    func paymentPage() async -> URL? {
        guard busy == nil, order?.actions.canPay == true else { return nil }
        busy = .paying
        defer { busy = nil }
        do {
            if let url = try await api.paymentPage(orderId: orderId) {
                isInPaymentPage = true
                return url
            }
            notice = .error(.failed(ApiFailure(status: 503, code: .paymentUnavailable)))
        } catch {
            await actionFailed(error)
        }
        return nil
    }

    /// The payment page closed (through the return link or by the member): ask the API how it went
    /// (`POST /orders/{id}/payment/sync`), whatever the page said.
    func paymentPageClosed(callback: URL?) async {
        isInPaymentPage = false
        let attempt = OrderPaymentViewModel.attempt(from: callback)
        await syncPayment(attempt: attempt, followUps: 2)
    }

    private func syncPayment(attempt: PaymentAttempt, followUps: Int) async {
        let synced: OrderDetailInfo
        do {
            synced = try await api.syncPayment(orderId: orderId)
        } catch {
            notice = .error(error)
            return
        }
        order = synced
        notice = Self.paymentNotice(status: synced.status, attempt: attempt)
        // A late confirmation still lands: sync again in a moment (slice D, After the sync).
        guard synced.status == .pendingPayment, attempt == .returnedSuccess, followUps > 0 else { return }
        try? await Task.sleep(for: followUpDelay)
        guard !Task.isCancelled, order?.status == .pendingPayment else { return }
        await syncPayment(attempt: attempt, followUps: followUps - 1)
    }

    /// The toast after the payment page, from the synced status (slice D, After the sync).
    nonisolated static func paymentNotice(status: OrderState, attempt: PaymentAttempt) -> Notice? {
        switch status {
        case .pendingPayment:
            switch attempt {
            case .returnedSuccess: return .payment(.appCheckoutPendingTitle, kind: .info)
            case .returnedFailure, .closed: return .payment(.checkoutFailedTitle, kind: .error)
            case .none: return nil
            }
        case .cancelled: return .payment(.appCheckoutPaymentExpired, kind: .error)
        case .paid, .prepared, .shipped, .delivered, .completed: return .payment(.checkoutSuccessTitle, kind: .success)
        case .refunded, .disputed, .unknown: return nil
        }
    }

    #if DEBUG
    @ObservationIgnored private var debugFailed = false

    /// `-TaleedDebugOrder offline` fails the first load (screenshots of the offline state).
    private func debugFailFirstLoad() throws(ApiError) {
        guard UserDefaults.standard.string(forKey: "TaleedDebugOrder") == "offline", !debugFailed else { return }
        debugFailed = true
        throw .network
    }
    #endif
}
