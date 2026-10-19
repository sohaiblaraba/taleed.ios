import Foundation
import Observation

/// The wallet screen (screens.md §2 G14 and §7 G14, slice D "Wallet", slice F "Top-ups"): the header of
/// `GET /wallet`, the history and the payouts (each a paged list de-duplicated by id), the top-up through
/// the gateway's page then `POST /wallet/top-ups/{id}/sync`, and the payout request.
///
/// When the screen opens it also syncs every top-up still pending (`GET /wallet/top-ups`, then a sync
/// each), so a top-up paid while the app was closed is credited, as the website's wallet page does.
@MainActor
@Observable
final class WalletViewModel {
    enum Tab: Int, CaseIterable {
        case history, payouts
    }

    /// One-off messages, shown as toasts by the screen.
    enum Notice: Equatable {
        case error(ApiError)
        case payoutRequested
    }

    /// What became of a payout request, for its sheet.
    enum PayoutOutcome: Equatable {
        /// Sent: the sheet closes.
        case sent
        /// `insufficient_balance` or a refused amount: "Montant invalide ou supérieur au solde disponible."
        /// under the amount; the balance was reloaded.
        case amountRefused
        /// The API refused the account details.
        case detailsRefused
        /// Anything else: a toast; the sheet stays, and a retry of the same request keeps its `clientId`.
        case failed
    }

    private(set) var summary: WalletSummary?
    /// The header failed and nothing is on screen: the error with "Réessayer".
    private(set) var loadError: ApiError?
    private(set) var isLoading = false
    var tab: Tab = .history
    let history: PagedList<WalletEntryRow>
    let payouts: PagedList<PayoutRow>
    /// The result of the last top-up, at the top of the screen until dismissed.
    private(set) var banner: TopUpBanner?
    var notice: Notice?
    private(set) var isStartingTopUp = false
    private(set) var isRequestingPayout = false

    @ObservationIgnored private let api: WalletApi
    @ObservationIgnored private let pager: WalletPager
    @ObservationIgnored private var submission: PayoutSubmission
    @ObservationIgnored private var backgroundSince: ContinuousClock.Instant?
    @ObservationIgnored private let followUpDelay: Duration
    /// Bumped by every top-up sync the member waits for, so that an older follow-up stops.
    @ObservationIgnored private var topUpGeneration = 0

    /// A shorter absence keeps the screen as it is.
    static let foregroundReloadAfter: Duration = .seconds(30)
    /// Syncs left after a "pending" answer, `followUpDelay` apart: a late confirmation still lands.
    static let followUps = 2

    init(api: WalletApi, followUpDelay: Duration = .seconds(3), makeClientId: @escaping () -> String = { UUID().uuidString }) {
        self.api = api
        self.followUpDelay = followUpDelay
        submission = PayoutSubmission(makeId: makeClientId)
        let pager = WalletPager(api: api)
        self.pager = pager
        history = PagedList { cursor throws(ApiError) in try await pager.history(cursor: cursor) }
        payouts = PagedList { cursor throws(ApiError) in try await pager.payouts(cursor: cursor) }
    }

    /// "Virements (3)": the API's total, once the first page came.
    var payoutCount: Int? { payouts.hasLoaded ? payouts.total : nil }

    // MARK: Loading

    func loadIfNeeded() async {
        guard summary == nil, loadError == nil, !isLoading else { return }
        await load()
    }

    func retry() async {
        loadError = nil
        await load()
    }

    /// The header first (the screen needs it), then both lists and the pending top-ups.
    private func load() async {
        isLoading = true
        do {
            #if DEBUG
            try debugFailFirstLoad()
            #endif
            summary = try await api.wallet()
            loadError = nil
        } catch {
            isLoading = false
            guard !Task.isCancelled else { return }
            loadError = error
            return
        }
        isLoading = false
        async let historyLoad: Void = history.loadIfNeeded()
        async let payoutsLoad: Void = payouts.loadIfNeeded()
        _ = await (historyLoad, payoutsLoad)
        await syncPendingTopUps()
    }

    /// Pull-to-refresh: the header and both lists; a failure keeps what is on screen and says so.
    func refresh() async {
        async let summaryLoad: Void = reloadSummary(automatic: false)
        async let historyLoad = history.refresh()
        async let payoutsLoad = payouts.refresh()
        _ = await (summaryLoad, historyLoad, payoutsLoad)
    }

    /// The header again. `automatic`: no toast when it fails.
    func reloadSummary(automatic: Bool = true) async {
        do {
            summary = try await api.wallet(automatic: automatic)
            loadError = nil
        } catch {
            guard !Task.isCancelled else { return }
            if summary == nil {
                loadError = error
            } else if !automatic {
                notice = .error(error)
            }
        }
    }

    func wentToBackground(at instant: ContinuousClock.Instant = .now) {
        backgroundSince = instant
    }

    /// Back after a while (screens.md §0.6): the header and the lists again, quietly, and the pending
    /// top-ups (one may have been paid in the browser meanwhile).
    func returnedToForeground(at instant: ContinuousClock.Instant = .now) async {
        guard let since = backgroundSince else { return }
        backgroundSince = nil
        guard summary != nil, instant - since >= Self.foregroundReloadAfter else { return }
        pager.isAutomatic = true
        defer { pager.isAutomatic = false }
        await reloadSummary()
        async let historyLoad = history.refresh()
        async let payoutsLoad = payouts.refresh()
        _ = await (historyLoad, payoutsLoad)
        await syncPendingTopUps()
    }

    /// The header and the history after money moved (a top-up credited).
    private func reloadAfterCredit() async {
        await reloadSummary()
        _ = await history.refresh()
    }

    // MARK: Top-ups

    /// "Procéder au paiement": starts a top-up. Nil when it could not start (the notice says why).
    func startTopUp(amount: Int, method: String) async -> StartedTopUp? {
        guard !isStartingTopUp else { return nil }
        isStartingTopUp = true
        defer { isStartingTopUp = false }
        do {
            let started = try await api.startTopUp(amount: amount, method: method)
            guard started.paymentURL != nil else {
                // No page to open: the top-up cannot be paid; it lapses on its own.
                notice = .error(.failed(ApiFailure(status: 503, code: .paymentUnavailable)))
                return nil
            }
            return started
        } catch {
            notice = .error(error)
            // The gateway was turned off meanwhile: the header's methods again.
            if error.code == .paymentMethodUnavailable { await reloadSummary() }
            return nil
        }
    }

    /// The gateway's page closed, through the return link or by the member: ask the API how it went,
    /// whatever the page said (slice D, Paying online).
    func topUpPageClosed(id: String) async {
        await syncTopUp(id: id)
    }

    /// A `taleed://payment-return?kind=top_up` link (the browser handed back to the app on its own).
    func paymentReturned(_ paymentReturn: PaymentReturn) async {
        await syncTopUp(id: paymentReturn.id)
    }

    func dismissBanner() {
        banner = nil
    }

    private func syncTopUp(id: String) async {
        topUpGeneration += 1
        let generation = topUpGeneration
        banner = .checking
        var followUps = Self.followUps
        while true {
            let state: TopUpState
            do {
                state = try await api.syncTopUp(id: id).status
            } catch {
                guard generation == topUpGeneration, !Task.isCancelled else { return }
                // Unknown for now: the next visit's sync of pending top-ups settles it.
                banner = .pending
                if error.code != .notFound { notice = .error(error) }
                return
            }
            guard generation == topUpGeneration else { return }
            banner = TopUpBanner(state)
            switch state {
            case .paid:
                await reloadAfterCredit()
                return
            case .pending, .unknown:
                guard followUps > 0 else { return }
                followUps -= 1
                try? await Task.sleep(for: followUpDelay)
                guard !Task.isCancelled, generation == topUpGeneration else { return }
            case .failed:
                return
            }
        }
    }

    /// Syncs every top-up the first page lists as pending (slice F); a credit reloads the header and
    /// the history and says so. Quiet: a failure waits for the next visit.
    func syncPendingTopUps() async {
        guard let topUps = try? await api.recentTopUps() else { return }
        var credited = false
        for topUp in topUps where topUp.status == .pending {
            if let synced = try? await api.syncTopUp(id: topUp.id), synced.status == .paid {
                credited = true
            }
        }
        guard credited else { return }
        if banner == nil || banner == .pending { banner = .paid }
        await reloadAfterCredit()
    }

    // MARK: Payouts

    /// "Envoyer la demande" (`POST /wallet/payouts`). The form is valid; the API decides in the end.
    func requestPayout(amount: Int, method: String, accountDetails: String) async -> PayoutOutcome {
        guard !isRequestingPayout else { return .failed }
        isRequestingPayout = true
        defer { isRequestingPayout = false }
        let request = submission.request(amount: amount, method: method, accountDetails: accountDetails)
        do {
            let payout = try await api.requestPayout(request)
            submission.reset()
            notice = .payoutRequested
            payouts.prepend(payout)
            tab = .payouts
            return .sent
        } catch {
            return await payoutFailed(error)
        }
    }

    /// After a payout went through and its sheet closed: the header (the amount is set aside) and the
    /// payouts as the server lists them.
    func reloadAfterPayout() async {
        await reloadSummary()
        _ = await payouts.refresh()
    }

    private func payoutFailed(_ error: ApiError) async -> PayoutOutcome {
        switch error.code {
        case .insufficientBalance:
            submission.reset()
            await reloadSummary()
            return .amountRefused
        case .invalidRequest:
            submission.reset()
            if error.issue(at: "body.amount") != nil { return .amountRefused }
            if error.issue(at: "body.accountDetails") != nil { return .detailsRefused }
            notice = .error(error)
            return .failed
        default:
            // No answer, a 5xx: the member's retry of the same request sends the same `clientId`.
            // A refusal that will not change on a retry starts a new request next time.
            if !error.isTransient { submission.reset() }
            notice = .error(error)
            return .failed
        }
    }

    #if DEBUG
    @ObservationIgnored private var debugFailed = false

    /// `-TaleedDebugWallet offline` fails the first load once (screenshots of the offline state).
    private func debugFailFirstLoad() throws(ApiError) {
        guard UserDefaults.standard.string(forKey: "TaleedDebugWallet") == "offline", !debugFailed else { return }
        debugFailed = true
        throw .network
    }
    #endif
}

/// Fetches the pages of both lists; marks the refreshes the member did not ask for.
@MainActor
private final class WalletPager {
    let api: WalletApi
    var isAutomatic = false

    init(api: WalletApi) {
        self.api = api
    }

    func history(cursor: String?) async throws(ApiError) -> Page<WalletEntryRow> {
        try await api.history(cursor: cursor, automatic: isAutomatic)
    }

    func payouts(cursor: String?) async throws(ApiError) -> Page<PayoutRow> {
        try await api.payouts(cursor: cursor, automatic: isAutomatic)
    }
}
