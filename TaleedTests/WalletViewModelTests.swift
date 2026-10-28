import Foundation
@testable import Taleed
import TaleedAPI
import Testing

// MARK: - View model

@MainActor
struct WalletViewModelTests {
    @Test func loadingShowsTheAmountsAndBothLists() async {
        let api = FakeWalletApi()
        let model = WalletViewModel(api: api)
        await model.loadIfNeeded()
        #expect(model.summary?.owed == 4200)
        #expect(model.summary?.inPayout == 1500)
        #expect(model.summary?.inProgress == 3000)
        #expect(model.history.items.map(\.id) == ["e1", "e2"])
        #expect(model.payoutCount == 1)
        #expect(model.summary?.limits.voucherAmount == 500)
        #expect(model.summary?.limits.voucherValidityDays == 365)
    }

    @Test func aFailedHeaderShowsTheErrorThenRetries() async {
        let api = FakeWalletApi()
        api.summaries = [.failure(.network)]
        let model = WalletViewModel(api: api)
        await model.loadIfNeeded()
        #expect(model.loadError == .network)
        #expect(model.summary == nil)
        await model.retry()
        #expect(model.loadError == nil)
        #expect(model.summary != nil)
    }

    @Test func savedDetailsShowAtOnceWithTheToast() async {
        let api = FakeWalletApi()
        api.defaultSummary = walletSummary(owed: 4200, account: nil)
        let model = WalletViewModel(api: api)
        await model.loadIfNeeded()
        #expect(WalletRules.owedNote(model.summary!) == .needsDetails)
        let outcome = await model.savePayoutDetails(method: "RIB", accountDetails: "00799999000123456789")
        #expect(outcome == .saved)
        #expect(api.saved.map(\.method) == ["RIB"])
        #expect(api.saved.map(\.accountDetails) == ["00799999000123456789"])
        #expect(model.summary?.payoutAccount?.accountDetails == "00799999000123456789")
        #expect(model.notice == .payoutDetailsSaved)
        #expect(WalletRules.owedNote(model.summary!) == nil)
    }

    @Test func refusedDetailsPointAtTheField() async {
        let api = FakeWalletApi()
        api.saveResults = [.failure(walletFailure(.invalidRequest, status: 400,
                                                  issues: [ApiFieldIssue(path: "body.accountDetails", message: "Too short")]))]
        let model = WalletViewModel(api: api)
        await model.loadIfNeeded()
        let outcome = await model.savePayoutDetails(method: "CCP", accountDetails: "1234")
        #expect(outcome == .detailsRefused)
        #expect(model.notice == nil)
        #expect(model.summary?.payoutAccount == walletAccount)
    }

    @Test func otherFailuresKeepTheSheetWithAToast() async {
        let api = FakeWalletApi()
        api.saveResults = [.failure(.network)]
        let model = WalletViewModel(api: api)
        await model.loadIfNeeded()
        let outcome = await model.savePayoutDetails(method: "CCP", accountDetails: "0012345678 clé 90")
        #expect(outcome == .failed)
        #expect(model.notice == .error(.network))
        #expect(!model.isSavingDetails)
    }

    @Test func pullToRefreshReloadsTheHeaderAndTheLists() async {
        let api = FakeWalletApi()
        let model = WalletViewModel(api: api)
        await model.loadIfNeeded()
        api.defaultSummary = walletSummary(owed: 0, inPayout: 4200)
        await model.refresh()
        #expect(model.summary?.owed == 0)
        #expect(model.summary?.inPayout == 4200)
        #expect(api.historyCalls == 2)
    }

    @Test func aShortAbsenceKeepsTheScreen() async {
        let api = FakeWalletApi()
        let model = WalletViewModel(api: api)
        await model.loadIfNeeded()
        let start = ContinuousClock.now
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start + .seconds(5))
        #expect(api.summaryCalls == 1)
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start + .seconds(31))
        #expect(api.summaryCalls == 2)
    }
}

// MARK: - Routing

@MainActor
struct WalletRouterTests {
    /// A top-up return link (top-ups ended with slice H) opens Earnings.
    @Test func anOldTopUpReturnOpensEarnings() {
        #expect(LinkRouter.destination(for: URL(string: "taleed://payment-return?kind=top_up&id=t5&result=success")!)
            == .screen(.wallet))
    }
}
