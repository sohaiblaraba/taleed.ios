import Foundation
@testable import Taleed
import Testing

// MARK: - Fixtures

private let joined = Date(timeIntervalSince1970: 1_760_000_000)
private let day: TimeInterval = 86_400

private func program(canRefer: Bool = true, url: String? = "http://localhost:3000/r/8f68e2ab", amount: Int = 500, goal: Int = 3,
                     saleVouchers: Int = 2) -> ReferralProgramInfo {
    ReferralProgramInfo(canRefer: canRefer, code: canRefer ? "8f68e2ab" : nil, inviteURL: canRefer ? url.flatMap(URL.init(string:)) : nil,
                        voucherAmount: amount, listingGoal: goal, listingWindowDays: 7, saleVouchers: saleVouchers,
                        saleWindowDays: 30, minItemPrice: 1500, annualCap: 15000, voucherValidityDays: 365,
                        termsURL: URL(string: "http://localhost:3000/referrals/terms"))
}

private func referral(_ id: String, count: Int = 0, listingRewarded: Bool = false, saleRewarded: Bool = false) -> ReferralRow {
    ReferralRow(id: id, member: MemberRef(id: "m-\(id)", username: id, displayName: "@\(id)", avatarURL: nil, isVerified: false,
                                          isOfficial: false),
                joinedAt: joined, listingCount: count, listingDeadline: joined + 7 * day, listingRewarded: listingRewarded,
                saleDeadline: joined + 30 * day, saleRewarded: saleRewarded)
}

private func voucher(_ id: String, status: VoucherStanding = .active, orderId: String? = nil) -> VoucherRow {
    VoucherRow(id: id, amount: 500, status: status, statusLabel: "Utilisable dès 1500 DA d’achat", label: "Bon d’achat — parrainage",
               expiresAt: joined + 365 * day, orderId: orderId, createdAt: joined)
}

/// The referral calls from canned results.
@MainActor
private final class FakeReferralsApi: ReferralsApi {
    var programs: [ReferralProgramInfo] = [program()]
    var referralResults: [Result<Page<ReferralRow>, Taleed.ApiError>] = []
    var defaultReferrals = Page(items: [referral("r1"), referral("r2")], nextCursor: nil, total: 2)
    var voucherItems = [voucher("v1")]
    private(set) var referralCalls: [(cursor: String?, automatic: Bool)] = []
    private(set) var voucherCalls = 0

    func referrals(cursor: String?, automatic: Bool) async throws(Taleed.ApiError) -> ReferralsPage {
        referralCalls.append((cursor, automatic))
        let program = programs.count > 1 ? programs.removeFirst() : programs[0]
        let page = referralResults.isEmpty ? defaultReferrals : try referralResults.removeFirst().get()
        return ReferralsPage(program: program, page: page)
    }

    func vouchers(cursor: String?, automatic: Bool) async throws(Taleed.ApiError) -> Page<VoucherRow> {
        voucherCalls += 1
        return Page(items: voucherItems, nextCursor: nil, total: voucherItems.count)
    }
}

@MainActor
private func languageManager(_ language: AppLanguage) -> LanguageManager {
    let suite = "ReferralsTests.\(language.rawValue)"
    let defaults = UserDefaults(suiteName: suite) ?? .standard
    defaults.removePersistentDomain(forName: suite)
    let manager = LanguageManager(defaults: defaults, preferredLanguages: ["fr"])
    manager.select(language)
    return manager
}

/// The formatter's spaces (narrow no-break, no-break) as plain spaces, to compare with readable text.
private func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: "\u{200F}", with: "").replacingOccurrences(of: "\u{200E}", with: "")
        .replacingOccurrences(of: "\u{2067}", with: "").replacingOccurrences(of: "\u{2066}", with: "")
        .replacingOccurrences(of: "\u{2069}", with: "")
}

// MARK: - Rules

struct ReferralRulesTests {
    @Test func aRewardIsDoneStillPossibleOrMissed() {
        let deadline = joined + 7 * day
        #expect(ReferralMilestone.of(rewarded: true, deadline: deadline, now: deadline + day) == .done)
        #expect(ReferralMilestone.of(rewarded: false, deadline: deadline, now: deadline - 1) == .open(until: deadline))
        #expect(ReferralMilestone.of(rewarded: false, deadline: deadline, now: deadline) == .missed)
    }

    @Test func eachRewardFollowsItsOwnDeadline() {
        let row = referral("r1", listingRewarded: true)
        let now = joined + 10 * day
        #expect(row.listingMilestone(now: now) == .done)
        #expect(row.saleMilestone(now: now) == .open(until: joined + 30 * day))
        #expect(referral("r2").listingMilestone(now: now) == .missed)
    }

    @Test func theInvitePartFollowsCanRefer() {
        #expect(program().access == .invite(URL(string: "http://localhost:3000/r/8f68e2ab")!))
        #expect(program(canRefer: false).access == .gate)
        #expect(program(url: nil).access == .none)
    }

    @Test func theTotalsComeFromTheProgram() {
        #expect(program().totalPerSide == 1500)
        #expect(program().saleReward == 1000)
        #expect(program(amount: 300, saleVouchers: 3).totalPerSide == 1200)
    }

    @Test func usedAndExpiredVouchersAreGreyedAndOnlyActiveOnesShowTheirExpiry() {
        #expect(!voucher("a").isGreyed)
        #expect(voucher("a").shownExpiry != nil)
        #expect(voucher("u", status: .used, orderId: "o1").isGreyed)
        #expect(voucher("u", status: .used, orderId: "o1").shownExpiry == nil)
        #expect(voucher("u", status: .used, orderId: "o1").openableOrderId == "o1")
        #expect(voucher("e", status: .expired, orderId: "o1").openableOrderId == nil)
        #expect(voucher("x", status: .unknown).isGreyed)
    }
}

// MARK: - Copy

@MainActor
struct ReferralCopyTests {
    @Test func frenchCopyIsFilledFromTheProgram() {
        let copy = ReferralsCopy(program: program(), l10n: languageManager(.fr))
        #expect(plain(copy.eyebrow) == "Gagnez 1 500 DA en parrainant")
        #expect(plain(copy.heroTitle) == "Invitez un ami — 1 500 DA pour vous, 1 500 DA pour lui")
        #expect(plain(copy.heroBody) == "Dès que votre ami publie 3 articles, vous recevez chacun 500 DA à dépenser sur Taleed. "
            + "Puis 1 000 DA de plus chacun lorsqu’il réalise sa première vente.")
        #expect(plain(copy.step2Body).contains("S’il publie 3 articles dans les 7 jours suivant son inscription"))
        #expect(plain(copy.step2Body).hasSuffix("vous recevez chacun 2 bons de 500 DA."))
        #expect(plain(copy.step3Body).contains("commande de 1 500 DA ou plus"))
        #expect(copy.rules.map(plain) == [
            "Un bon par commande, valable 365 jours après son attribution.",
            "Jusqu’à 15 000 DA de bons par période de 365 jours.",
            "Une vente de votre filleul à vous-même ne compte pas.",
        ])
    }

    @Test func otherProgramValuesChangeTheCopy() {
        let copy = ReferralsCopy(program: program(amount: 300, goal: 1, saleVouchers: 1), l10n: languageManager(.fr))
        #expect(plain(copy.eyebrow) == "Gagnez 600 DA en parrainant")
        #expect(plain(copy.heroBody).hasPrefix("Dès que votre ami publie 1 article, vous recevez chacun 300 DA"))
        #expect(plain(copy.step2Body).hasSuffix("vous recevez chacun 1 bon de 300 DA."))
    }

    @Test func arabicUsesItsPluralForms() {
        let copy = ReferralsCopy(program: program(), l10n: languageManager(.ar))
        let step2 = plain(copy.step2Body)
        #expect(step2.contains("3 مقالات"))
        #expect(step2.contains("7 أيام"))
        #expect(step2.contains("30 يومًا"))
        #expect(step2.contains("قسيمتين"))
        #expect(plain(copy.rules[0]).contains("365 يومًا"))
    }

    @Test func theBadgesSayWhereEachRewardStands() {
        let copy = ReferralsCopy(program: program(), l10n: languageManager(.fr))
        let early = joined + day
        let open = copy.listings(referral("r1", count: 1), now: early)
        #expect(open.title == "1/3 articles publiés")
        #expect(open.milestone == .open(until: joined + 7 * day))
        #expect(open.caption?.hasPrefix("Jusqu’au ") == true)

        let done = copy.listings(referral("r1", count: 3, listingRewarded: true), now: early)
        #expect(plain(done.title) == "3 articles ✓ — 500 DA versés")
        #expect(done.caption == nil)

        let missed = copy.sale(referral("r1"), now: joined + 31 * day)
        #expect(plain(missed.title) == "Première vente → 2×500 DA")
        #expect(missed.caption == "Délai dépassé")

        let sold = copy.sale(referral("r1", saleRewarded: true), now: early)
        #expect(plain(sold.title) == "Première vente ✓ — 2×500 DA versés")
    }

    @Test func aCountAboveTheGoalShowsTheGoal() {
        let copy = ReferralsCopy(program: program(), l10n: languageManager(.fr))
        #expect(copy.listings(referral("r1", count: 5), now: joined).title == "3/3 articles publiés")
    }

    @Test func theTermsNoteLinksTheTaggedWords() {
        let url = URL(string: "http://localhost:3000/referrals/terms")!
        let note = ReferralsCopy.termsNote("Le programme est soumis à des <terms>conditions</terms>.", termsURL: url, linkColor: .black)
        #expect(String(note.characters) == "Le programme est soumis à des conditions.")
        let links = note.runs.compactMap(\.link)
        #expect(links == [url])
        let untagged = ReferralsCopy.termsNote("Sans lien.", termsURL: url, linkColor: .black)
        #expect(untagged.runs.compactMap(\.link).isEmpty)
    }
}

// MARK: - View model

@MainActor
struct ReferralsViewModelTests {
    @Test func loadingShowsTheProgramTheMembersAndTheVouchers() async {
        let api = FakeReferralsApi()
        let model = ReferralsViewModel(api: api, copy: { _ in })
        await model.loadIfNeeded()
        #expect(model.program == program())
        #expect(model.referrals.items.map(\.id) == ["r1", "r2"])
        #expect(model.referralCount == 2)
        #expect(api.voucherCalls == 1)
        #expect(model.showsVouchers)
    }

    @Test func notVerifiedShowsTheGateAndLoadsNoVouchers() async {
        let api = FakeReferralsApi()
        api.programs = [program(canRefer: false)]
        let model = ReferralsViewModel(api: api, copy: { _ in })
        await model.loadIfNeeded()
        #expect(model.access == .gate)
        #expect(api.voucherCalls == 0)
        #expect(!model.showsVouchers)
    }

    @Test func noVouchersHidesTheirSection() async {
        let api = FakeReferralsApi()
        api.voucherItems = []
        let model = ReferralsViewModel(api: api, copy: { _ in })
        await model.loadIfNeeded()
        #expect(!model.showsVouchers)
    }

    @Test func aFailedFirstLoadShowsTheErrorThenRetries() async {
        let api = FakeReferralsApi()
        api.referralResults = [.failure(.network)]
        let model = ReferralsViewModel(api: api, copy: { _ in })
        await model.loadIfNeeded()
        #expect(model.loadError == .network)
        #expect(model.program == nil)
        await model.retry()
        #expect(model.loadError == nil)
        #expect(model.program != nil)
        #expect(api.voucherCalls == 1)
    }

    @Test func verifiedMeanwhileLoadsTheVouchersOnRefresh() async {
        let api = FakeReferralsApi()
        api.programs = [program(canRefer: false), program()]
        let model = ReferralsViewModel(api: api, copy: { _ in })
        await model.loadIfNeeded()
        #expect(api.voucherCalls == 0)
        await model.refresh()
        #expect(model.access == .invite(URL(string: "http://localhost:3000/r/8f68e2ab")!))
        #expect(api.voucherCalls == 1)
    }

    @Test func copyPutsTheLinkOnThePasteboardThenTheLabelComesBack() async throws {
        let api = FakeReferralsApi()
        var copied: [String] = []
        let model = ReferralsViewModel(api: api, copiedDuration: .milliseconds(50), copy: { copied.append($0) })
        await model.loadIfNeeded()
        model.copyInvite()
        #expect(copied == ["http://localhost:3000/r/8f68e2ab"])
        #expect(model.isCopied)
        #expect(model.notice == .copied)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!model.isCopied)
    }

    @Test func behindTheGateNothingIsCopied() async {
        let api = FakeReferralsApi()
        api.programs = [program(canRefer: false)]
        var copied: [String] = []
        let model = ReferralsViewModel(api: api, copy: { copied.append($0) })
        await model.loadIfNeeded()
        model.copyInvite()
        #expect(copied.isEmpty)
        #expect(!model.isCopied)
        #expect(model.notice == nil)
    }

    @Test func aLongAbsenceReloadsQuietly() async {
        let api = FakeReferralsApi()
        let model = ReferralsViewModel(api: api, copy: { _ in })
        await model.loadIfNeeded()
        let start = ContinuousClock.now
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start + .seconds(5))
        #expect(api.referralCalls.count == 1)
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start + .seconds(60))
        #expect(api.referralCalls.count == 2)
        #expect(api.referralCalls.last?.automatic == true)
    }

    @Test func membersAreListedOnceAcrossPages() async {
        let api = FakeReferralsApi()
        api.referralResults = [
            .success(Page(items: [referral("r1"), referral("r2")], nextCursor: "c1", total: 3)),
            .success(Page(items: [referral("r2"), referral("r3")], nextCursor: nil, total: 3)),
        ]
        let model = ReferralsViewModel(api: api, copy: { _ in })
        await model.loadIfNeeded()
        await model.referrals.loadMore()
        #expect(model.referrals.items.map(\.id) == ["r1", "r2", "r3"])
        #expect(api.referralCalls.map(\.cursor) == [nil, "c1"])
    }
}
