import Foundation

// The app models of the referral screen (screens.md §2 and §7 G18, slice E "Referrals", slice F
// "Vouchers"). The rules, amounts and permissions come from `program` (screens.md §0.1): the app never
// writes an amount, a count or a number of days of its own.

/// `program` of `GET /me/referrals`: the same on every page.
struct ReferralProgramInfo: Equatable, Sendable {
    /// Only verified members invite (`canRefer`); otherwise the screen explains and leads to verification.
    let canRefer: Bool
    let code: String?
    /// The link to share; nil while `canRefer` is false.
    let inviteURL: URL?
    /// The value of one voucher.
    let voucherAmount: Int
    /// Items the new member puts on sale within `listingWindowDays` of joining: one voucher each.
    let listingGoal: Int
    let listingWindowDays: Int
    /// Vouchers each member gets for the new member's first sale within `saleWindowDays`.
    let saleVouchers: Int
    let saleWindowDays: Int
    /// A voucher applies to an item price from this amount, one per order.
    let minItemPrice: Int
    /// At most this much in vouchers per member over 365 days.
    let annualCap: Int
    let voucherValidityDays: Int
    /// The program's terms, opened in the in-app browser.
    let termsURL: URL?

    /// What each side can earn: the listing voucher plus the sale vouchers (screens.md §7 G18:
    /// `voucherAmount × (1 + saleVouchers)`, "1 500 DA").
    var totalPerSide: Int { voucherAmount * (1 + saleVouchers) }

    /// What the first sale brings each side ("1 000 DA de plus").
    var saleReward: Int { voucherAmount * saleVouchers }

    /// What the invite part of the screen shows.
    var access: ReferralAccess {
        guard canRefer else { return .gate }
        guard let inviteURL else { return .none }
        return .invite(inviteURL)
    }
}

/// The invite part of the screen.
enum ReferralAccess: Equatable, Sendable {
    /// Verified: the link, Copy, Share and "Vos filleuls".
    case invite(URL)
    /// Not verified (or the badge was removed, decision 16): the amber box that leads to verification.
    /// The members invited and the vouchers stay hidden, as on the website.
    case gate
    /// `canRefer` without a link (not expected): no invite controls.
    case none
}

/// `GET /me/referrals`: the program and a page of members invited.
struct ReferralsPage: Sendable {
    let program: ReferralProgramInfo
    let page: Page<ReferralRow>
}

/// Where one of a referral's two rewards stands (slice E table: done, still possible, missed).
enum ReferralMilestone: Equatable, Sendable {
    /// Rewarded.
    case done
    /// Not rewarded yet, and the window is still open until this date.
    case open(until: Date)
    /// Not rewarded and the window closed.
    case missed

    static func of(rewarded: Bool, deadline: Date, now: Date) -> ReferralMilestone {
        if rewarded { return .done }
        return now < deadline ? .open(until: deadline) : .missed
    }
}

/// A member invited.
struct ReferralRow: Identifiable, Equatable, Sendable {
    let id: String
    let member: MemberRef
    let joinedAt: Date
    /// Their items for sale, reserved or sold, counted up to the goal by the server.
    let listingCount: Int
    let listingDeadline: Date
    let listingRewarded: Bool
    let saleDeadline: Date
    let saleRewarded: Bool

    func listingMilestone(now: Date = .now) -> ReferralMilestone {
        .of(rewarded: listingRewarded, deadline: listingDeadline, now: now)
    }

    func saleMilestone(now: Date = .now) -> ReferralMilestone {
        .of(rewarded: saleRewarded, deadline: saleDeadline, now: now)
    }
}

/// A voucher of `GET /me/vouchers`.
struct VoucherRow: Identifiable, Equatable, Sendable {
    let id: String
    let amount: Int
    let status: VoucherStanding
    /// "Utilisable dès 1500 DA d’achat", "Utilisé", "Expiré", from the server.
    let statusLabel: String
    /// "Bon d’achat — parrainage", "Bon d’achat — bienvenue", from the server.
    let label: String
    let expiresAt: Date?
    /// `USED`: the order it was spent on.
    let orderId: String?
    let createdAt: Date

    /// Used and expired vouchers are greyed (an unknown status too: it cannot be spent as far as the app knows).
    var isGreyed: Bool { status != .active }
    /// "Expire le {date}" while active only, as the website.
    var shownExpiry: Date? { status == .active ? expiresAt : nil }
    /// A used voucher opens the order it paid for.
    var openableOrderId: String? { status == .used ? orderId : nil }
}
