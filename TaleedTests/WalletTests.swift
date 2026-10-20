import Foundation
@testable import Taleed
import TaleedAPI
import Testing

// MARK: - Rules

struct WalletRulesTests {
    @Test func theHeadlineAddsTheVouchers() {
        #expect(walletSummary(balance: 3000, vouchers: 500).headline == 3500)
        #expect(WalletRules.showsVoucherPart(walletSummary(vouchers: 500)))
        #expect(!WalletRules.showsVoucherPart(walletSummary(vouchers: 0)))
        // A negative balance after an adjustment shows as it is.
        #expect(walletSummary(balance: -400, vouchers: 0).headline == -400)
    }

    @Test func thePayoutButtonNeedsTheMinimum() {
        #expect(WalletRules.canRequestPayout(walletSummary(balance: 100)))
        #expect(!WalletRules.canRequestPayout(walletSummary(balance: 99)))
        #expect(!WalletRules.canRequestPayout(walletSummary(balance: 0)))
        #expect(!WalletRules.canRequestPayout(walletSummary(balance: -50)))
        // Vouchers are never withdrawable.
        #expect(!WalletRules.canRequestPayout(walletSummary(balance: 0, vouchers: 500)))
    }

    @Test func topUpShowsOnlyWithAGateway() {
        #expect(WalletRules.showsTopUp(walletSummary()))
        #expect(!WalletRules.showsTopUp(walletSummary(methods: [])))
        #expect(!WalletRules.showsTopUpMethodPicker(walletSummary()))
        let chargily = PaymentChoice(value: "chargily", label: "Chargily Pay", hint: "CIB")
        #expect(WalletRules.showsTopUpMethodPicker(walletSummary(methods: [chargily, walletMockMethod])))
    }

    @Test func amountsAreGreenFromZeroAndVouchersOnlyWhileActive() {
        #expect(WalletRules.amountTone(walletEntry("a", amount: 5000)) == .credit)
        #expect(WalletRules.amountTone(walletEntry("b", amount: 0)) == .credit)
        #expect(WalletRules.amountTone(walletEntry("c", kind: .purchase, amount: -2000)) == .debit)
        let active = WalletVoucherInfo(status: .active, statusLabel: "Utilisable dès 1500 DA d’achat", expiresAt: nil)
        let used = WalletVoucherInfo(status: .used, statusLabel: "Utilisé", expiresAt: nil)
        #expect(WalletRules.amountTone(walletEntry("d", kind: .voucher, amount: 500, voucher: active)) == .credit)
        #expect(WalletRules.amountTone(walletEntry("e", kind: .voucher, amount: 500, voucher: used)) == .muted)
    }

    @Test func payoutBadgesFollowTheWebsitesVariants() {
        #expect(WalletRules.payoutTone(.requested) == .brand)
        #expect(WalletRules.payoutTone(.processing) == .neutral)
        #expect(WalletRules.payoutTone(.paid) == .success)
        #expect(WalletRules.payoutTone(.rejected) == .error)
        #expect(WalletRules.payoutTone(.unknown) == .neutral)
    }

    @Test func topUpBannersFromTheSync() {
        #expect(TopUpBanner(.paid) == .paid)
        #expect(TopUpBanner(.failed) == .failed)
        #expect(TopUpBanner(.pending) == .pending)
        #expect(TopUpBanner(.unknown) == .pending)
    }
}

// MARK: - Text

struct WalletTextTests {
    @Test func creditsReadWithAPlus() {
        #expect(WalletText.signedAmount(5000, language: .fr) == "+5\u{202F}000\u{00A0}DA")
        #expect(WalletText.signedAmount(0, language: .en) == "+0\u{00A0}DA")
        #expect(WalletText.signedAmount(-2000, language: .fr) == "-2\u{202F}000\u{00A0}DA")
        // Arabic: the sign before the digits, inside the right-to-left marks, as a negative amount.
        #expect(WalletText.signedAmount(5000, language: .ar) == "\u{200F}\u{200E}+5.000\u{00A0}د.ج.\u{200F}")
        #expect(WalletText.signedAmount(-2000, language: .ar) == PriceFormatter.format(-2000, language: .ar))
    }

    @Test func ledgerLinesShowTheNoteAndTheDate() {
        let locale = Locale(identifier: "fr_FR")
        let date = OrderText.date(Date(timeIntervalSince1970: 1_760_000_000), locale: locale)
        let detail = WalletText.entryDetail(walletEntry("a", note: "T-000010"), locale: locale) { "Expire le \($0)" }
        #expect(detail == "\("T-000010".isolatedLeftToRight)\u{00A0}·\u{00A0}\(date)")
        #expect(WalletText.entryDetail(walletEntry("b", note: nil), locale: locale) { $0 } == date)
    }

    @Test func voucherLinesShowTheirStatusAndExpiryWhileActive() {
        let locale = Locale(identifier: "fr_FR")
        let created = Date(timeIntervalSince1970: 1_760_000_000)
        let expires = Date(timeIntervalSince1970: 1_790_000_000)
        let active = WalletVoucherInfo(status: .active, statusLabel: "Utilisable dès 1500 DA d’achat", expiresAt: expires)
        let voucherEntry = walletEntry("v", kind: .voucher, amount: 500, voucher: active)
        let detail = WalletText.entryDetail(voucherEntry, locale: locale) { "Expire le \($0)" }
        #expect(detail == "Utilisable dès 1500 DA d’achat\u{00A0}·\u{00A0}\(OrderText.date(created, locale: locale))\u{00A0}·\u{00A0}"
            + "Expire le \(OrderText.date(expires, locale: locale))")
        let expired = WalletVoucherInfo(status: .expired, statusLabel: "Expiré", expiresAt: expires)
        let expiredDetail = WalletText.entryDetail(walletEntry("w", kind: .voucher, amount: 500, voucher: expired), locale: locale) { $0 }
        #expect(expiredDetail == "Expiré\u{00A0}·\u{00A0}\(OrderText.date(created, locale: locale))")
    }

    @Test func payoutLinesShowTheMethodTheTimeAndReference() {
        let locale = Locale(identifier: "fr_FR")
        let date = OrderText.dateTime(Date(timeIntervalSince1970: 1_760_000_000), locale: locale)
        let method = walletPayout("p").methodLabel
        #expect(WalletText.payoutDetail(walletPayout("p"), locale: locale) == "\(method)\u{00A0}·\u{00A0}\(date)")
        #expect(WalletText.payoutDetail(walletPayout("q", reference: "VIR-2026-0042"), locale: locale)
            == "\(method)\u{00A0}·\u{00A0}\(date)\u{00A0}·\u{00A0}\("VIR-2026-0042".isolatedLeftToRight)")
        // The separators never break: no plain space around the dots.
        #expect(!WalletText.payoutDetail(walletPayout("p"), locale: locale).contains(" · "))
    }
}

// MARK: - Forms

struct WalletFormTests {
    @Test func amountsAreWholeNumbersInRange() {
        #expect(WalletAmountInput(text: "", range: 100...7500) == .empty)
        #expect(WalletAmountInput(text: "50", range: 100...7500) == .invalid)
        #expect(WalletAmountInput(text: "7501", range: 100...7500) == .invalid)
        #expect(WalletAmountInput(text: "1 000", range: 100...7500) == .valid(1000))
        #expect(WalletAmountInput(text: "١٠٠٠", range: 100...7500) == .valid(1000))
        #expect(WalletAmountInput(text: "100", range: nil) == .invalid)
    }

    @Test func thePayoutFormIsPrefilledWithTheBalance() {
        var form = PayoutFormInput(balance: 7500, minPayout: 100)
        #expect(form.amountText == "7500")
        #expect(form.method == "CCP")
        #expect(!form.isValid)
        form.accountDetails = "  0012345678 clé 90 \n"
        #expect(form.trimmedDetails == "0012345678 clé 90")
        #expect(form.isValid)
        form.amountText = "1000"
        #expect(form.amount == .valid(1000))
        form.amountText = "8000"
        #expect(form.amount == .invalid)
        #expect(!form.isValid)
        #expect(PayoutFormInput(balance: 0, minPayout: 100).amountText.isEmpty)
        #expect(PayoutFormInput(balance: 50, minPayout: 100).amountRange == nil)
    }

    @Test func accountDetailsNeedFiveToThreeHundredCharactersOnceTrimmed() {
        var form = PayoutFormInput(balance: 7500, minPayout: 100)
        form.accountDetails = "  1234 "
        #expect(!form.detailsAreValid)
        form.accountDetails = "12345"
        #expect(form.detailsAreValid)
        form.accountDetails = String(repeating: "1", count: 301)
        #expect(!form.detailsAreValid)
        #expect(PayoutFormInput.detailsMinLength == 5)
        #expect(PayoutFormInput.detailsMaxLength == 300)
    }

    @Test func aRetryOfTheSameRequestKeepsItsClientId() {
        var ids = ["id1", "id2", "id3"]
        var submission = PayoutSubmission { ids.removeFirst() }
        let first = submission.request(amount: 1000, method: "CCP", accountDetails: "0012345678 clé 90")
        #expect(first.clientId == "id1")
        #expect(submission.request(amount: 1000, method: "CCP", accountDetails: "0012345678 clé 90").clientId == "id1")
        // Another body with the same id would be refused (`body.clientId`): a new id.
        #expect(submission.request(amount: 900, method: "CCP", accountDetails: "0012345678 clé 90").clientId == "id2")
        submission.reset()
        #expect(submission.request(amount: 900, method: "CCP", accountDetails: "0012345678 clé 90").clientId == "id3")
    }

    @Test func theTopUpFormStartsAtOneThousand() {
        var form = TopUpFormInput(limits: .default, methods: [walletMockMethod])
        #expect(form.amountText == "1000")
        #expect(form.method == "mock")
        #expect(form.isValid)
        form.amountText = "50"
        #expect(form.amount == .invalid)
        #expect(!form.isValid)
        form.amountText = "1000001"
        #expect(!form.isValid)
        form.amountText = "5025"
        #expect(form.amount == .valid(5025))
        #expect(!TopUpFormInput(limits: .default, methods: []).isValid)
    }
}

// MARK: - Mapping

struct WalletMappingTests {
    @Test func unknownTypesDecodeAndShow() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(WalletEntryType.self, from: Data("\"CASHBACK\"".utf8)) == .unknownDefaultOpenApi)
        #expect(try decoder.decode(PayoutStatus.self, from: Data("\"ON_HOLD\"".utf8)) == .unknownDefaultOpenApi)
        let generated = WalletEntry(id: "x", type: .unknownDefaultOpenApi, label: "Cashback", amount: 100, note: " ",
                                    orderId: nil, voucher: nil, createdAt: Date())
        let row = WalletEntryRow(generated)
        #expect(row.kind == .unknown)
        #expect(row.note == nil)
        #expect(WalletEntryRowView.icon(row.kind) == .money)
    }

    @Test func aVoucherLineKeepsItsStatus() {
        let generated = WalletEntry(id: "v", type: .voucher, label: "Bon d’achat — parrainage", amount: 500, note: nil, orderId: "o9",
                                    voucher: VoucherState(status: .used, statusLabel: "Utilisé", expiresAt: nil), createdAt: Date())
        let row = WalletEntryRow(generated)
        #expect(row.kind == .voucher)
        #expect(row.voucher?.status == .used)
        #expect(row.orderId == "o9")
    }

    @Test func gatewaysUnknownToThisBuildAreLeftOut() {
        let wallet = Wallet(balance: 3000, voucherBalance: 500, pendingEscrow: 2500,
                            topUpMethods: [PaymentMethodOption(value: .unknownDefaultOpenApi, label: "New", hint: ""),
                                           PaymentMethodOption(value: .chargily, label: "Chargily Pay", hint: "CIB")],
                            limits: WalletLimits(minPayout: 100, minTopUp: 100, maxTopUp: 1_000_000, voucherMinItemPrice: 1500))
        let mapped = WalletSummary(wallet)
        #expect(mapped.topUpMethods.map(\.value) == ["chargily"])
        #expect(mapped.headline == 3500)
    }
}
