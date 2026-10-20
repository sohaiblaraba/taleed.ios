import Foundation
import Observation
import UIKit

/// The referral screen (screens.md §2 and §7 G18; website `referrals/page.tsx`, `copy-invite-link.tsx`,
/// `referrals-dialog.tsx`; slice E "Referrals", slice F "Vouchers").
///
/// `GET /me/referrals` gives the program and the members invited (one paged list, 30 a page, de-duplicated
/// by id); the program of each page replaces the one on screen. While the member may refer, the vouchers
/// (`GET /me/vouchers`, 20 a page) load too; the website hides both lists behind the verification gate.
@MainActor
@Observable
final class ReferralsViewModel {
    /// One-off messages, shown as toasts by the screen.
    enum Notice: Equatable {
        /// "Lien copié !".
        case copied
    }

    /// Nil until a first page came.
    private(set) var program: ReferralProgramInfo?
    let referrals: PagedList<ReferralRow>
    let vouchers: PagedList<VoucherRow>
    /// "Lien copié !" on the button, for `copiedDuration` after a copy.
    private(set) var isCopied = false
    var notice: Notice?

    @ObservationIgnored private let pager: ReferralsPager
    @ObservationIgnored private let copyToPasteboard: (String) -> Void
    @ObservationIgnored private let copiedDuration: Duration
    @ObservationIgnored private var copyGeneration = 0
    @ObservationIgnored private var backgroundSince: ContinuousClock.Instant?

    /// The website's 2.5 s.
    static let copiedFor: Duration = .milliseconds(2500)
    /// A shorter absence keeps the screen as it is.
    static let foregroundReloadAfter: Duration = .seconds(30)

    init(api: ReferralsApi, copiedDuration: Duration = ReferralsViewModel.copiedFor,
         copy: @escaping (String) -> Void = { UIPasteboard.general.string = $0 }) {
        self.copiedDuration = copiedDuration
        copyToPasteboard = copy
        let pager = ReferralsPager(api: api)
        self.pager = pager
        referrals = PagedList { cursor throws(ApiError) in try await pager.referrals(cursor: cursor) }
        vouchers = PagedList { cursor throws(ApiError) in try await pager.vouchers(cursor: cursor) }
        pager.onProgram = { [weak self] program in self?.program = program }
    }

    /// The first page failed and nothing is on screen: the error with "Réessayer" (offline included).
    var loadError: ApiError? { program == nil ? referrals.error : nil }

    var access: ReferralAccess? { program?.access }

    /// "Vos bons d’achat" shows once the member has vouchers, and only past the gate (website, slice F).
    var showsVouchers: Bool { program?.canRefer == true && vouchers.hasLoaded && !vouchers.items.isEmpty }

    /// "Vos filleuls (n)": the API's total, once known.
    var referralCount: Int? { referrals.hasLoaded ? referrals.total : nil }

    /// "Vos filleuls" holds only its empty state (no member, no voucher, no voucher error): the sheet
    /// fits it instead of taking the full height.
    var isSheetCompact: Bool {
        referrals.isEmpty && !showsVouchers && !(program?.canRefer == true && !vouchers.hasLoaded && vouchers.error != nil)
    }

    // MARK: Loading

    func loadIfNeeded() async {
        await referrals.loadIfNeeded()
        await loadVouchersIfNeeded()
    }

    func retry() async {
        await referrals.reload()
        await loadVouchersIfNeeded()
    }

    /// Pull-to-refresh: the program and both lists; a failure keeps what is on screen (the lists report it).
    func refresh() async {
        if program?.canRefer == true {
            async let referralsLoad = referrals.refresh()
            async let vouchersLoad = vouchers.refresh()
            _ = await (referralsLoad, vouchersLoad)
        } else {
            await referrals.refresh()
        }
        // Verified meanwhile: the vouchers now.
        await loadVouchersIfNeeded()
    }

    /// The vouchers' own retry (in the "Vos filleuls" sheet).
    func retryVouchers() async {
        await vouchers.retry()
    }

    private func loadVouchersIfNeeded() async {
        guard program?.canRefer == true else { return }
        await vouchers.loadIfNeeded()
    }

    func wentToBackground(at instant: ContinuousClock.Instant = .now) {
        backgroundSince = instant
    }

    /// Back after a while (screens.md §0.6): everything again, quietly (a verification may have been
    /// approved, a member invited may have joined).
    func returnedToForeground(at instant: ContinuousClock.Instant = .now) async {
        guard let since = backgroundSince else { return }
        backgroundSince = nil
        guard program != nil, instant - since >= Self.foregroundReloadAfter else { return }
        pager.isAutomatic = true
        defer { pager.isAutomatic = false }
        await refresh()
    }

    // MARK: Invite

    /// "Copier le lien d’invitation": the invite link on the pasteboard, then "Lien copié !" on the button
    /// and as a toast for 2.5 s (website `copy-invite-link.tsx`).
    func copyInvite() {
        guard case let .invite(url) = program?.access else { return }
        copyToPasteboard(url.absoluteString)
        notice = .copied
        copyGeneration += 1
        let generation = copyGeneration
        isCopied = true
        Task { [weak self, copiedDuration] in
            try? await Task.sleep(for: copiedDuration)
            guard let self, generation == self.copyGeneration else { return }
            self.isCopied = false
        }
    }
}

/// Fetches the pages of both lists; hands each page's program to the screen; marks the refreshes the
/// member did not ask for.
@MainActor
private final class ReferralsPager {
    let api: ReferralsApi
    var isAutomatic = false
    var onProgram: ((ReferralProgramInfo) -> Void)?

    init(api: ReferralsApi) {
        self.api = api
    }

    func referrals(cursor: String?) async throws(ApiError) -> Page<ReferralRow> {
        let result = try await api.referrals(cursor: cursor, automatic: isAutomatic)
        onProgram?(result.program)
        return result.page
    }

    func vouchers(cursor: String?) async throws(ApiError) -> Page<VoucherRow> {
        try await api.vouchers(cursor: cursor, automatic: isAutomatic)
    }
}
