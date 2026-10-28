import Foundation
import Observation

/// Earnings (slice H; the website's `/wallet` page): the header of `GET /wallet` (owed, in payout, in
/// progress, the payout details, the vouchers), the history and the payouts (each a paged list
/// de-duplicated by id), the voucher rules' numbers, and saving the payout details
/// (`PUT /wallet/payout-account`). Nothing here can be spent, added or withdrawn.
@MainActor
@Observable
final class WalletViewModel {
    enum Tab: Int, CaseIterable {
        case history, payouts
    }

    /// One-off messages, shown as toasts by the screen.
    enum Notice: Equatable {
        case error(ApiError)
        /// "Payout details saved."
        case payoutDetailsSaved
    }

    /// What became of saving the payout details, for its sheet.
    enum SaveOutcome: Equatable {
        /// Saved: the sheet closes.
        case saved
        /// The API refused the account details: "Enter 5 to 300 characters." under the field.
        case detailsRefused
        /// Anything else: a toast; the sheet stays for a retry.
        case failed
    }

    private(set) var summary: WalletSummary?
    /// The header failed and nothing is on screen: the error with "Retry".
    private(set) var loadError: ApiError?
    private(set) var isLoading = false
    /// The program's numbers for the voucher rules; nil until they come (or for a suspended member).
    private(set) var voucherProgram: VoucherRulesInfo?
    var tab: Tab = .history
    let history: PagedList<WalletEntryRow>
    let payouts: PagedList<PayoutRow>
    var notice: Notice?
    private(set) var isSavingDetails = false

    @ObservationIgnored private let api: WalletApi
    @ObservationIgnored private let pager: WalletPager
    /// `GET /me/referrals` answers `banned` to a suspended member: not asked then.
    @ObservationIgnored private let loadsVoucherProgram: Bool
    @ObservationIgnored private var backgroundSince: ContinuousClock.Instant?

    /// A shorter absence keeps the screen as it is.
    static let foregroundReloadAfter: Duration = .seconds(30)

    init(api: WalletApi, loadsVoucherProgram: Bool = true) {
        self.api = api
        self.loadsVoucherProgram = loadsVoucherProgram
        let pager = WalletPager(api: api)
        self.pager = pager
        history = PagedList { cursor throws(ApiError) in try await pager.history(cursor: cursor) }
        payouts = PagedList { cursor throws(ApiError) in try await pager.payouts(cursor: cursor) }
    }

    /// "Payouts (3)": the API's total, once the first page came.
    var payoutCount: Int? { payouts.hasLoaded ? payouts.total : nil }

    /// The voucher rules' numbers: the program's, else the server's current values.
    var voucherRules: VoucherRulesInfo? {
        summary.map { WalletRules.voucherRules(program: voucherProgram, limits: $0.limits) }
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard summary == nil, loadError == nil, !isLoading else { return }
        await load()
    }

    func retry() async {
        loadError = nil
        await load()
    }

    /// The header first (the screen needs it), then both lists and the voucher rules' numbers.
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
        async let programLoad: Void = loadVoucherProgram()
        _ = await (historyLoad, payoutsLoad, programLoad)
    }

    /// Quiet: without an answer the rules use the server's current values.
    private func loadVoucherProgram() async {
        guard loadsVoucherProgram, voucherProgram == nil else { return }
        voucherProgram = try? await api.voucherRules(automatic: true)
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

    /// Back after a while (screens.md §0.6): the header and the lists again, quietly.
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
    }

    // MARK: Payout details

    /// "Save" (`PUT /wallet/payout-account`). The form is valid; the API decides in the end. The header
    /// shows the saved details at once, then reloads (the owed note may change).
    func savePayoutDetails(method: String, accountDetails: String) async -> SaveOutcome {
        guard !isSavingDetails else { return .failed }
        isSavingDetails = true
        defer { isSavingDetails = false }
        do {
            let account = try await api.savePayoutAccount(method: method, accountDetails: accountDetails)
            summary?.payoutAccount = account
            notice = .payoutDetailsSaved
            return .saved
        } catch {
            if error.code == .invalidRequest, error.issue(at: "body.accountDetails") != nil { return .detailsRefused }
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
