import Foundation
@testable import Taleed
import TaleedAPI
import Testing

// MARK: - View model

@MainActor
struct WalletViewModelTests {
    @Test func loadingShowsTheHeaderAndBothLists() async {
        let api = FakeWalletApi()
        let model = WalletViewModel(api: api)
        await model.loadIfNeeded()
        #expect(model.summary?.headline == 7500)
        #expect(model.history.items.map(\.id) == ["e1", "e2"])
        #expect(model.payoutCount == 1)
        #expect(model.banner == nil)
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

    @Test func openingSyncsPendingTopUpsAndSaysWhenOneIsCredited() async {
        let api = FakeWalletApi()
        api.recent = [TopUpInfo(id: "t9", amount: 5000, status: .pending), TopUpInfo(id: "t8", amount: 300, status: .paid)]
        api.syncResults["t9"] = [.success(TopUpInfo(id: "t9", amount: 5000, status: .paid))]
        let model = WalletViewModel(api: api)
        await model.loadIfNeeded()
        #expect(api.syncCalls == ["t9"])
        #expect(model.banner == .paid)
        // The header again after the credit.
        #expect(api.summaryCalls == 2)
    }

    @Test func aPendingTopUpThatStaysPendingChangesNothing() async {
        let api = FakeWalletApi()
        api.recent = [TopUpInfo(id: "t9", amount: 5000, status: .pending)]
        let model = WalletViewModel(api: api)
        await model.loadIfNeeded()
        #expect(api.syncCalls == ["t9"])
        #expect(model.banner == nil)
        #expect(api.summaryCalls == 1)
    }

    @Test func aPayoutIsListedAndTheHeaderReloads() async {
        let api = FakeWalletApi()
        let model = WalletViewModel(api: api)
        await model.loadIfNeeded()
        api.defaultSummary = walletSummary(balance: 6500)
        let outcome = await model.requestPayout(amount: 1000, method: "CCP", accountDetails: "0012345678 clé 90")
        #expect(outcome == .sent)
        #expect(model.notice == .payoutRequested)
        #expect(model.tab == .payouts)
        #expect(model.payouts.items.first?.amount == 1000)
        await model.reloadAfterPayout()
        #expect(model.summary?.balance == 6500)
        #expect(model.payouts.items.map(\.id) == ["new1", "p1"])
        #expect(api.payoutRequests.first?.accountDetails == "0012345678 clé 90")
    }

    @Test func insufficientBalanceRefusesTheAmountAndReloads() async {
        let api = FakeWalletApi()
        let model = WalletViewModel(api: api, makeClientId: { UUID().uuidString })
        await model.loadIfNeeded()
        api.payoutResults = [.failure(walletFailure(.insufficientBalance))]
        api.defaultSummary = walletSummary(balance: 500)
        let outcome = await model.requestPayout(amount: 9000, method: "CCP", accountDetails: "0012345678 clé 90")
        #expect(outcome == .amountRefused)
        #expect(model.summary?.balance == 500)
        #expect(model.notice == nil)
    }

    @Test func noAnswerKeepsTheClientIdForTheRetry() async {
        let api = FakeWalletApi()
        var count = 0
        let model = WalletViewModel(api: api, makeClientId: { count += 1; return "c\(count)" })
        await model.loadIfNeeded()
        api.payoutResults = [.failure(.network)]
        #expect(await model.requestPayout(amount: 1000, method: "CCP", accountDetails: "0012345678 clé 90") == .failed)
        #expect(model.notice == .error(.network))
        #expect(await model.requestPayout(amount: 1000, method: "CCP", accountDetails: "0012345678 clé 90") == .sent)
        #expect(api.payoutRequests.map(\.clientId) == ["c1", "c1"])
    }

    @Test func fieldIssuesPointAtTheirField() async {
        let api = FakeWalletApi()
        let model = WalletViewModel(api: api)
        await model.loadIfNeeded()
        let issue = ApiFieldIssue(path: "body.accountDetails", message: "Too short")
        api.payoutResults = [.failure(walletFailure(.invalidRequest, status: 400, issues: [issue]))]
        #expect(await model.requestPayout(amount: 1000, method: "CCP", accountDetails: "12345") == .detailsRefused)
    }

    @Test func aGatewayTurnedOffReloadsTheHeader() async {
        let api = FakeWalletApi()
        let model = WalletViewModel(api: api)
        await model.loadIfNeeded()
        api.startResult = .failure(walletFailure(.paymentMethodUnavailable))
        api.defaultSummary = walletSummary(methods: [])
        #expect(await model.startTopUp(amount: 5000, method: "mock") == nil)
        #expect(model.notice == .error(walletFailure(.paymentMethodUnavailable)))
        #expect(model.summary?.topUpMethods.isEmpty == true)
    }

    @Test func aStartedTopUpOpensItsPage() async {
        let api = FakeWalletApi()
        let model = WalletViewModel(api: api)
        await model.loadIfNeeded()
        let started = await model.startTopUp(amount: 5000, method: "mock")
        #expect(started?.topUp.id == "t1")
        #expect(started?.paymentURL != nil)
    }

    @Test func backFromThePagePaidCreditsTheBalance() async {
        let api = FakeWalletApi()
        let model = WalletViewModel(api: api, followUpDelay: .zero)
        await model.loadIfNeeded()
        api.syncResults["t1"] = [.success(TopUpInfo(id: "t1", amount: 5000, status: .pending)),
                                 .success(TopUpInfo(id: "t1", amount: 5000, status: .paid))]
        api.defaultSummary = walletSummary(balance: 12500)
        model.tab = .payouts
        await model.topUpPageClosed(id: "t1")
        #expect(model.banner == .paid)
        #expect(model.summary?.balance == 12500)
        // The new "Rechargement" line shows: the history is selected.
        #expect(model.tab == .history)
        #expect(api.syncCalls == ["t1", "t1"])
    }

    @Test func aFailedPaymentChangesNothing() async {
        let api = FakeWalletApi()
        let model = WalletViewModel(api: api, followUpDelay: .zero)
        await model.loadIfNeeded()
        let calls = api.summaryCalls
        api.syncResults["t1"] = [.success(TopUpInfo(id: "t1", amount: 5000, status: .failed))]
        await model.topUpPageClosed(id: "t1")
        #expect(model.banner == .failed)
        #expect(api.summaryCalls == calls)
    }

    @Test func aTopUpStillPendingStopsAfterTheFollowUps() async {
        let api = FakeWalletApi()
        let model = WalletViewModel(api: api, followUpDelay: .zero)
        await model.loadIfNeeded()
        await model.paymentReturned(PaymentReturn(kind: .topUp, id: "t2", succeeded: true))
        #expect(model.banner == .pending)
        #expect(api.syncCalls == Array(repeating: "t2", count: 1 + WalletViewModel.followUps))
        model.dismissBanner()
        #expect(model.banner == nil)
    }
}

// MARK: - Router

@MainActor
struct WalletRouterTests {
    @Test func aTopUpReturnWaitsForTheWalletWhateverItsId() {
        let router = AppRouter()
        router.isSignedIn = { true }
        router.launchWillShowItsScreen()
        router.open(url: URL(string: "taleed://payment-return?kind=top_up&id=t5&result=success")!)
        #expect(router.path(.profile) == [.wallet])
        #expect(router.consumePaymentReturn(kind: .order) == nil)
        #expect(router.consumePaymentReturn(kind: .topUp) == PaymentReturn(kind: .topUp, id: "t5", succeeded: true))
        #expect(router.consumePaymentReturn(kind: .topUp) == nil)
    }
}
