import Foundation
import SwiftUI

/// The referral screen's copy, filled from `program` (screens.md §7 G18: the website's text hard-codes
/// 1 500 DA, 500 DA, 3 articles, 7 and 30 days; the app takes every figure from the server).
@MainActor
struct ReferralsCopy {
    let program: ReferralProgramInfo
    let l10n: LanguageManager

    private var language: AppLanguage { l10n.language }

    func amount(_ value: Int) -> String { PriceFormatter.format(value, language: language) }

    /// "3 articles", "مقالين"…
    func items(_ count: Int) -> String { l10n.format(.appReferralsItems, count) }

    /// "7 jours", "30 يومًا"…
    func days(_ count: Int) -> String { l10n.format(.appReferralsDays, count) }

    func date(_ date: Date) -> String { OrderText.date(date, locale: language.formattingLocale) }

    /// "Gagnez 1 500 DA en parrainant" (also the Profile hub's row).
    var eyebrow: String { l10n.format(.appReferralsEyebrow, amount(program.totalPerSide)) }

    /// "Invitez un ami — 1 500 DA pour vous, 1 500 DA pour lui".
    var heroTitle: String { l10n.format(.appReferralsHeroTitle, amount(program.totalPerSide)) }

    /// "Dès que votre ami publie 3 articles, vous recevez chacun 500 DA… Puis 1 000 DA de plus chacun…".
    var heroBody: String {
        l10n.format(.appReferralsHeroBody, items(program.listingGoal), amount(program.voucherAmount), amount(program.saleReward))
    }

    /// "S’il publie 3 articles dans les 7 jours suivant son inscription… 2 bons de 500 DA."
    var step2Body: String {
        l10n.format(.appReferralsStep2Body, items(program.listingGoal), days(program.listingWindowDays), amount(program.voucherAmount),
                    days(program.saleWindowDays), l10n.format(.appReferralsVouchers, program.saleVouchers))
    }

    /// "… de votre prochaine commande de 1 500 DA ou plus …".
    var step3Body: String { l10n.format(.appReferralsStep3Body, amount(program.minItemPrice)) }

    /// The rules the steps leave out: one voucher per order and its validity, the yearly cap, the sale to
    /// the inviter.
    var rules: [String] {
        [
            l10n.format(.appReferralsRuleValidity, days(program.voucherValidityDays)),
            l10n.format(.appReferralsRuleCap, amount(program.annualCap)),
            l10n.string(.appReferralsRuleInviterSale),
        ]
    }

    // MARK: Members invited

    /// "Inscrit le 19 oct. 2026".
    func joined(_ row: ReferralRow) -> String { l10n.format(.referralsJoinedOn, date(row.joinedAt)) }

    /// The listings badge: "0/3 articles publiés", or "3 articles ✓ — 500 DA versés".
    func listings(_ row: ReferralRow, now: Date = .now) -> MilestoneText {
        let milestone = row.listingMilestone(now: now)
        if milestone == .done {
            return MilestoneText(milestone: milestone,
                                 title: l10n.format(.appReferralsMilestoneListingsDone, items(program.listingGoal),
                                                    amount(program.voucherAmount)),
                                 caption: nil)
        }
        let count = min(max(row.listingCount, 0), program.listingGoal)
        return MilestoneText(milestone: milestone, title: l10n.format(.referralsMilestoneListings, count, program.listingGoal),
                             caption: caption(milestone))
    }

    /// The sale badge: "Première vente → 2×500 DA", or "Première vente ✓ — 2×500 DA versés".
    func sale(_ row: ReferralRow, now: Date = .now) -> MilestoneText {
        let milestone = row.saleMilestone(now: now)
        let key: L10nKey = milestone == .done ? .appReferralsMilestoneSaleDone : .appReferralsMilestoneSale
        return MilestoneText(milestone: milestone, title: l10n.format(key, program.saleVouchers, amount(program.voucherAmount)),
                             caption: caption(milestone))
    }

    /// Beyond the website (screens.md §7 G18): "Jusqu’au {date}" while possible, "Délai dépassé" after.
    private func caption(_ milestone: ReferralMilestone) -> String? {
        switch milestone {
        case .done: nil
        case let .open(until): l10n.format(.appReferralsDeadlineUntil, date(until))
        case .missed: l10n.string(.appReferralsDeadlineMissed)
        }
    }

    // MARK: Terms

    /// "Le programme de parrainage est soumis à des conditions.", the tagged part a link to `termsURL`
    /// (plain text when there is none).
    static func termsNote(_ text: String, termsURL: URL?, linkColor: Color) -> AttributedString {
        guard let open = text.range(of: "<terms>"), let close = text.range(of: "</terms>", range: open.upperBound..<text.endIndex) else {
            return AttributedString(text)
        }
        var result = AttributedString(String(text[..<open.lowerBound]))
        var link = AttributedString(String(text[open.upperBound..<close.lowerBound]))
        if let termsURL {
            link.link = termsURL
            link.underlineStyle = .single
            link.foregroundColor = linkColor
        }
        result += link
        result += AttributedString(String(text[close.upperBound...]))
        return result
    }
}

/// A reward badge of a member invited, and the line under it.
struct MilestoneText: Equatable {
    let milestone: ReferralMilestone
    let title: String
    let caption: String?
}
