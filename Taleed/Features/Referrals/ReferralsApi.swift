import SwiftUI
import TaleedAPI

/// The calls of the referral screen (screens.md §2 and §7 G18, slice E "Referrals", slice F "Vouchers").
@MainActor
protocol ReferralsApi: AnyObject {
    /// `GET /me/referrals`: the program (the same on every page) and the members invited, newest first,
    /// 30 a page. `automatic`: a refresh the member did not ask for (back in the foreground).
    func referrals(cursor: String?, automatic: Bool) async throws(ApiError) -> ReferralsPage
    /// `GET /me/vouchers`: `ACTIVE` first, then `USED`, then `EXPIRED`, newest first within each; 20 a page.
    func vouchers(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<VoucherRow>
}

extension GeneratedTaleedApi: ReferralsApi {
    func referrals(cursor: String?, automatic: Bool) async throws(ApiError) -> ReferralsPage {
        #if DEBUG
        if !automatic { try ReferralsDebugFailures.fail(.load) }
        #endif
        let page = try await caller.call(.read, automatic: automatic) {
            try await ReferralsAPI.listReferrals(cursor: cursor, apiConfiguration: $0)
        }
        return ReferralsPage(program: ReferralProgramInfo(page.program),
                             page: Page(items: page.items.map(ReferralRow.init), nextCursor: page.nextCursor, total: page.total))
    }

    func vouchers(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<VoucherRow> {
        let page = try await caller.call(.read, automatic: automatic) {
            try await ReferralsAPI.listVouchers(cursor: cursor, apiConfiguration: $0)
        }
        return Page(items: page.items.map(VoucherRow.init), nextCursor: page.nextCursor, total: page.total)
    }
}

// MARK: Mapping

extension ReferralProgramInfo {
    init(_ program: ReferralProgram) {
        let code = program.code?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            canRefer: program.canRefer,
            code: code?.isEmpty == false ? code : nil,
            inviteURL: URL(apiString: program.inviteUrl),
            voucherAmount: program.voucherAmount,
            listingGoal: program.listingGoal,
            listingWindowDays: program.listingWindowDays,
            saleVouchers: program.saleVouchers,
            saleWindowDays: program.saleWindowDays,
            minItemPrice: program.minItemPrice,
            annualCap: program.annualCap,
            voucherValidityDays: program.voucherValidityDays,
            termsURL: URL(apiString: program.termsUrl)
        )
    }
}

extension ReferralRow {
    init(_ referral: Referral) {
        self.init(
            id: referral.id,
            member: MemberRef(referral.member),
            joinedAt: referral.joinedAt,
            listingCount: referral.listingCount,
            listingDeadline: referral.listingDeadlineAt,
            listingRewarded: referral.listingRewarded,
            saleDeadline: referral.saleDeadlineAt,
            saleRewarded: referral.saleRewarded
        )
    }
}

extension VoucherRow {
    init(_ voucher: Voucher) {
        let status: VoucherStanding = switch voucher.status {
        case .active: .active
        case .used: .used
        case .expired: .expired
        case .unknownDefaultOpenApi: .unknown
        }
        self.init(id: voucher.id, amount: voucher.amount, status: status, statusLabel: voucher.statusLabel, label: voucher.label,
                  expiresAt: voucher.expiresAt, orderId: voucher.orderId, createdAt: voucher.createdAt)
    }
}

// MARK: Dependencies

/// The referral screen's API, set once at the root (`AppRootView`).
private struct ReferralsApiKey: EnvironmentKey {
    static var defaultValue: (any ReferralsApi)? { nil }
}

extension EnvironmentValues {
    var referralsApi: (any ReferralsApi)? {
        get { self[ReferralsApiKey.self] }
        set { self[ReferralsApiKey.self] = newValue }
    }
}

#if DEBUG
/// `-TaleedDebugReferrals offline`: the screen's first `GET /me/referrals` fails offline (then works), for
/// screenshots of the error state (screens.md §0.6).
@MainActor
enum ReferralsDebugFailures {
    enum Point: String {
        case load = "offline"
    }

    private static var used: Set<String> = []

    static func fail(_ point: Point) throws(ApiError) {
        let modes = Set((UserDefaults.standard.string(forKey: "TaleedDebugReferrals") ?? "").split(separator: ",").map(String.init))
        guard modes.contains(point.rawValue), !used.contains(point.rawValue) else { return }
        used.insert(point.rawValue)
        throw .network
    }
}
#endif
