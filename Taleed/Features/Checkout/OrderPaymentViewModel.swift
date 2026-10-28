import Foundation
import Observation

/// The payment screen of an order (screens.md §2 G11 steps 9–11, slice D "After the sync" and "Paying
/// again"): `POST /orders/{id}/payment/sync` when it opens, whatever the payment page said, then the
/// result: paid, confirmed (cash on delivery), still waiting with "Payer maintenant", or
/// cancelled. After a home delivery to a new address it offers to save the address.
@MainActor
@Observable
final class OrderPaymentViewModel {
    enum Notice: Equatable {
        case error(ApiError)
    }

    /// "Enregistrer cette adresse".
    enum AddressOffer: Equatable {
        case offered
        case saving
        case saved
    }

    let orderId: String
    private(set) var attempt: PaymentAttempt
    private(set) var order: OrderPaymentInfo?
    /// The first sync failed: an error with "Réessayer" (`404`: "no longer available").
    private(set) var loadError: ApiError?
    private(set) var isSyncing = false
    private(set) var isPaying = false
    private(set) var addressOffer: AddressOffer?
    var notice: Notice?

    @ObservationIgnored private let api: CheckoutApi
    @ObservationIgnored private let addressToSave: AddressDraft?
    /// Syncs left while the gateway has not settled a payment the member says went through.
    @ObservationIgnored private var followUps = 2
    @ObservationIgnored private let followUpDelay: Duration

    init(target: OrderPaymentTarget, api: CheckoutApi, followUpDelay: Duration = .seconds(3)) {
        orderId = target.orderId
        attempt = target.attempt
        addressToSave = target.addressToSave
        addressOffer = target.addressToSave == nil ? nil : .offered
        self.api = api
        self.followUpDelay = followUpDelay
    }

    var outcome: PaymentOutcome? {
        order.map { PaymentOutcome.of($0, attempt: attempt) }
    }

    // MARK: Syncing

    func loadIfNeeded() async {
        guard order == nil, loadError == nil, !isSyncing else { return }
        await sync()
    }

    func retry() async {
        loadError = nil
        await sync()
    }

    /// Asks the gateway through the API (repeated freely). `automatic`: back on screen or in the
    /// foreground, no error toast.
    func sync(automatic: Bool = false) async {
        guard !isSyncing else { return }
        isSyncing = true
        do {
            #if DEBUG
            try debugFailFirstLoad()
            #endif
            let order = try await api.syncPayment(orderId: orderId)
            self.order = order
            loadError = nil
            isSyncing = false
        } catch {
            isSyncing = false
            if error.isNotFound || order == nil {
                order = nil
                loadError = error
            } else if !automatic {
                notice = .error(error)
            }
            return
        }
        await followUpIfNeeded()
    }

    /// Back from the payment page with success while the order still waits: a late confirmation still
    /// lands, so sync again in a moment, twice at most.
    private func followUpIfNeeded() async {
        guard outcome?.retriesSync == true, followUps > 0 else { return }
        followUps -= 1
        try? await Task.sleep(for: followUpDelay)
        guard !Task.isCancelled else { return }
        await sync(automatic: true)
    }

    // MARK: Paying again

    /// "Payer maintenant": a new page from the gateway (`POST /orders/{id}/payment`). Nil when there is
    /// none (the notice says why, or the order moved on and is shown again).
    func paymentPage() async -> URL? {
        guard !isPaying, order?.canPay == true else { return nil }
        isPaying = true
        defer { isPaying = false }
        do {
            if let url = try await api.payOrder(orderId: orderId) { return url }
            notice = .error(.failed(ApiFailure(status: 503, code: .paymentUnavailable)))
        } catch {
            notice = .error(error)
            // `invalid_state`: paid or cancelled meanwhile.
            if error.code == .invalidState || error.code == .notFound { await sync(automatic: true) }
        }
        return nil
    }

    /// The payment page closed: through the return link (`callback`) or by the member. Sync either way.
    func paymentPageClosed(callback: URL?) async {
        attempt = Self.attempt(from: callback)
        followUps = 2
        await sync()
    }

    /// The payment page's verdict from its return link; closed without one.
    nonisolated static func attempt(from callback: URL?) -> PaymentAttempt {
        guard let callback, case let .paymentReturn(paymentReturn) = LinkRouter.destination(for: callback) else { return .closed }
        return paymentReturn.succeeded ? .returnedSuccess : .returnedFailure
    }

    // MARK: Saving the address

    /// "Enregistrer l'adresse" (`POST /me/addresses`, not idempotent: the button is disabled while it sends).
    func saveAddress() async {
        guard let addressToSave, addressOffer == .offered else { return }
        addressOffer = .saving
        do {
            _ = try await api.saveAddress(addressToSave)
            addressOffer = .saved
        } catch {
            addressOffer = .offered
            notice = .error(error)
        }
    }

    func dismissAddressOffer() {
        if addressOffer == .offered { addressOffer = nil }
    }

    #if DEBUG
    @ObservationIgnored private var debugFailed = false

    /// `-TaleedDebugOrderPayment offline` fails the first sync (screenshots of the offline state).
    private func debugFailFirstLoad() throws(ApiError) {
        guard UserDefaults.standard.string(forKey: "TaleedDebugOrderPayment") == "offline", !debugFailed else { return }
        debugFailed = true
        throw .network
    }
    #endif
}
