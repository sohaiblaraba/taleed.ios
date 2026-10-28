import Foundation
@testable import Taleed
import TaleedAPI
import Testing

// MARK: - Rules

struct WalletRulesTests {
    @Test func theOwedNoteFollowsTheWebsitesOrder() {
        // Negative after an adjustment, whatever the details.
        #expect(WalletRules.owedNote(walletSummary(owed: -400)) == .negative)
        #expect(WalletRules.owedNote(walletSummary(owed: -400, account: nil)) == .negative)
        // Enough for the run, no details: ask for them.
        #expect(WalletRules.owedNote(walletSummary(owed: 100, account: nil)) == .needsDetails)
        #expect(WalletRules.owedNote(walletSummary(owed: 4200, account: nil)) == .needsDetails)
        // Under the minimum: it waits, with or without details.
        #expect(WalletRules.owedNote(walletSummary(owed: 99)) == .belowMinimum(100))
        #expect(WalletRules.owedNote(walletSummary(owed: 50, account: nil)) == .belowMinimum(100))
        // Paid by the next run, or nothing owed: no note.
        #expect(WalletRules.owedNote(walletSummary(owed: 100)) == nil)
        #expect(WalletRules.owedNote(walletSummary(owed: 0)) == nil)
        #expect(WalletRules.owedNote(walletSummary(owed: 0, account: nil)) == nil)
    }

    @Test func theNextPayoutDateShowsOnlyWhenTheNextRunPaysTheAmount() {
        #expect(WalletRules.showsNextPayoutDate(walletSummary(owed: 4200)))
        #expect(WalletRules.showsNextPayoutDate(walletSummary(owed: 100)))
        // Nothing owed, or negative: nothing to pay.
        #expect(!WalletRules.showsNextPayoutDate(walletSummary(owed: 0)))
        #expect(!WalletRules.showsNextPayoutDate(walletSummary(owed: -1)))
        // An owed note says why the next run will not pay it: no date then (the website's wallet page).
        #expect(!WalletRules.showsNextPayoutDate(walletSummary(owed: 50)))
        #expect(!WalletRules.showsNextPayoutDate(walletSummary(owed: 4200, account: nil)))
        #expect(!WalletRules.showsNextPayoutDate(walletSummary(owed: 99, account: nil)))
    }

    @Test func thePayoutSheetOffersOnlyTheMethodsThisBuildCanSend() {
        let fallback = [CatalogOption(value: "CCP", label: "CCP"), CatalogOption(value: "RIB", label: "Virement bancaire (RIB)"),
                        CatalogOption(value: "BARIDIMOB", label: "BaridiMob")]
        let catalog = [CatalogOption(value: "RIB", label: "RIB (catalog)"), CatalogOption(value: "PAYPAL", label: "PayPal"),
                       CatalogOption(value: "CCP", label: "CCP (catalog)")]
        #expect(WalletRules.payoutMethods(catalog, fallback: fallback).map(\.value) == ["RIB", "CCP"])
        #expect(WalletRules.payoutMethods(catalog, fallback: fallback).first?.label == "RIB (catalog)")
        // No catalog yet, an empty one, or only methods this build does not know: the website's labels.
        #expect(WalletRules.payoutMethods(nil, fallback: fallback) == fallback)
        #expect(WalletRules.payoutMethods([], fallback: fallback) == fallback)
        #expect(WalletRules.payoutMethods([CatalogOption(value: "PAYPAL", label: "PayPal")], fallback: fallback) == fallback)
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
        let detail = WalletText.entryDetail(walletEntry("a", kind: .saleRelease, note: "T-000010"), locale: locale) { "Expire le \($0)" }
        #expect(detail == "\("T-000010".isolatedLeftToRight)\u{00A0}·\u{00A0}\(date)")
        #expect(WalletText.entryDetail(walletEntry("b", kind: .saleRelease, note: nil), locale: locale) { $0 } == date)
    }

    /// An old top-up line ("Card payment") carries the gateway's id: never shown.
    @Test func cardPaymentLinesShowTheDateOnly() {
        let locale = Locale(identifier: "fr_FR")
        let date = OrderText.date(Date(timeIntervalSince1970: 1_760_000_000), locale: locale)
        #expect(WalletText.entryDetail(walletEntry("t", kind: .topUp, note: "mock"), locale: locale) { $0 } == date)
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

// MARK: - Payout details form

struct PayoutDetailsFormTests {
    private let limits = walletSummary().limits
    private let methods = ["CCP", "RIB", "BARIDIMOB"]

    @Test func aNewFormStartsWithCcpAndNoDetails() {
        let form = PayoutDetailsInput(account: nil, methods: methods, limits: limits)
        #expect(form.method == "CCP")
        #expect(form.accountDetails.isEmpty)
        #expect(!form.isValid)
        #expect(!form.showsLengthError)
        // Without CCP among the methods: the first one offered.
        #expect(PayoutDetailsInput(account: nil, methods: ["RIB", "BARIDIMOB"], limits: limits).method == "RIB")
    }

    @Test func savedDetailsArePrefilled() {
        let account = PayoutAccountInfo(method: "RIB", methodLabel: "Virement bancaire (RIB)", accountDetails: "00799999000123456789",
                                        updatedAt: Date())
        let form = PayoutDetailsInput(account: account, methods: methods, limits: limits)
        #expect(form.method == "RIB")
        #expect(form.accountDetails == "00799999000123456789")
        #expect(form.isValid)
    }

    @Test func accountDetailsNeedFiveToThreeHundredCharactersOnceTrimmed() {
        var form = PayoutDetailsInput(account: nil, methods: methods, limits: limits)
        form.accountDetails = "  1234 \n"
        #expect(form.trimmedDetails == "1234")
        #expect(!form.detailsAreValid)
        #expect(form.showsLengthError)
        form.accountDetails = "12345"
        #expect(form.detailsAreValid)
        #expect(!form.showsLengthError)
        form.accountDetails = String(repeating: "1", count: 300)
        #expect(form.isValid)
        form.accountDetails = String(repeating: "1", count: 301)
        #expect(!form.isValid)
        #expect(form.showsLengthError)
        // Blank is not an error: the button waits.
        form.accountDetails = "   "
        #expect(!form.isValid)
        #expect(!form.showsLengthError)
    }

    @Test func theAccountDetailsNeverShowInDescriptions() {
        let secret = "00799999000123456789"
        let account = PayoutAccountInfo(method: "RIB", methodLabel: "Virement bancaire (RIB)", accountDetails: secret, updatedAt: Date())
        let form = PayoutDetailsInput(account: account, methods: methods, limits: limits)
        for text in [String(describing: account), String(reflecting: account), "\(account)",
                     String(describing: form), String(reflecting: form), "\(form)",
                     String(describing: Optional(account)), String(describing: [form])] {
            #expect(!text.contains(secret))
            #expect(text.contains("<redacted>"))
        }
        #expect(String(describing: account).contains("RIB"))
    }

    @Test func theFieldTakesALittleMoreThanTheMaximum() {
        let form = PayoutDetailsInput(account: nil, methods: methods, limits: limits)
        #expect(form.inputLimit == 320)
        #expect(form.minLength == 5)
        #expect(form.maxLength == 300)
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

    @Test func theSummaryKeepsTheServersAmountsAndDetails() {
        let updated = Date(timeIntervalSince1970: 1_760_000_000)
        let wallet = Wallet(owed: -400, inPayout: 1500, inProgress: 3000, voucherBalance: 500, nextPayoutAt: walletNextRun,
                            payoutAccount: PayoutAccount(method: .ccp, methodLabel: "CCP", accountDetails: "0012345678 clé 90",
                                                         updatedAt: updated),
                            limits: WalletLimits(minPayout: 100, payoutDetailsMin: 5, payoutDetailsMax: 300, voucherMinItemPrice: 1500,
                                                 voucherAmount: 700, voucherValidityDays: 180))
        let mapped = WalletSummary(wallet)
        #expect(mapped.owed == -400)
        #expect(mapped.inPayout == 1500)
        #expect(mapped.inProgress == 3000)
        #expect(mapped.voucherBalance == 500)
        #expect(mapped.nextPayoutAt == walletNextRun)
        #expect(mapped.payoutAccount == PayoutAccountInfo(method: "CCP", methodLabel: "CCP", accountDetails: "0012345678 clé 90",
                                                          updatedAt: updated))
        // The voucher rules' numbers come from `limits` (API 1.7.1).
        #expect(mapped.limits == WalletLimitsInfo(minPayout: 100, payoutDetailsMin: 5, payoutDetailsMax: 300, voucherMinItemPrice: 1500,
                                                  voucherAmount: 700, voucherValidityDays: 180))
        let empty = Wallet(owed: 0, inPayout: 0, inProgress: 0, voucherBalance: 0, nextPayoutAt: walletNextRun, payoutAccount: nil,
                           limits: wallet.limits)
        #expect(WalletSummary(empty).payoutAccount == nil)
    }

    /// No stored balance (slice H): the generated client has no top-up, payout request or balance left.
    @Test func theContractHasNoStoredBalance() {
        let walletKeys = Set(Wallet.CodingKeys.allCases.map(\.rawValue))
        #expect(walletKeys == ["owed", "inPayout", "inProgress", "voucherBalance", "nextPayoutAt", "payoutAccount", "limits"])
        #expect(!CheckoutAmounts.CodingKeys.allCases.map(\.rawValue).contains("walletApplied"))
        #expect(!CheckoutQuote.CodingKeys.allCases.map(\.rawValue).contains("walletBalance"))
        #expect(!CheckoutQuoteRequest.CodingKeys.allCases.map(\.rawValue).contains("useWallet"))
        #expect(!OrderCreate.CodingKeys.allCases.map(\.rawValue).contains("useWallet"))
    }
}
