import AuthenticationServices
import SwiftUI

/// The wallet (screens.md §2 G14 and §7 G14; website `wallet/page.tsx`; Figma does not draw it,
/// decision D-12): back and "Portefeuille", the result of the last top-up, the two tiles ("Solde
/// disponible" with its voucher part, "En attente") first, as the screen's main figure, then "Recharger"
/// (only when a gateway takes top-ups) and "Demander un virement" (disabled under the minimum, with
/// "Minimum : 100 DA" under it), then the tabs "Historique" and "Virements (n)", which stay at the top
/// while scrolling. Signed out: the sign-in prompt.
///
/// States: a skeleton of the header and the tabs while the header loads, the error with Retry (offline
/// included), each tab's loading, error and empty states, pull-to-refresh, pagination, a quiet reload
/// back from the background.
struct WalletView: View {
    let api: WalletApi
    /// Opens the payout form once the wallet has loaded (account deletion with money left, G16).
    var opensPayout = false
    @Environment(SessionManager.self) private var session
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if session.isSignedIn {
            // A new screen for another member.
            WalletScreen(api: api, opensPayout: opensPayout).id(session.user?.id)
        } else {
            ShellScreen {
                TaleedTopAppBar(title: l10n.string(.walletTitle), onBack: { dismiss() })
            } content: {
                SignInPromptView(icon: .money, title: l10n.string(.appWalletSignedOutTitle))
            }
        }
    }
}

private struct WalletScreen: View {
    @State private var model: WalletViewModel
    @State private var showsTopUp = false
    @State private var showsPayout = false
    /// The top-up the sheet started: its page opens once the sheet is gone, and only then.
    @State private var startedTopUp: StartedTopUp?
    /// False from "Recharger" until the top-up sheet's dismissal has run (its closing animation included).
    @State private var isTopUpSheetGone = true
    @State private var isInBrowser = false
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(AppToasts.self) private var toasts
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    /// Opens the payout form once the wallet has loaded (account deletion with money left, G16).
    private let opensPayout: Bool
    @State private var didOpenPayout = false

    init(api: WalletApi, opensPayout: Bool) {
        _model = State(initialValue: WalletViewModel(api: api))
        self.opensPayout = opensPayout
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.walletTitle), onBack: { dismiss() })
        } content: {
            content
        }
        .task { await model.loadIfNeeded() }
        .onChange(of: model.summary != nil, initial: true) { _, loaded in
            guard loaded, opensPayout, !didOpenPayout else { return }
            didOpenPayout = true
            showsPayout = true
        }
        .onAppear { takePaymentReturn() }
        .onChange(of: router.pendingPaymentReturn) { _, _ in takePaymentReturn() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: model.wentToBackground()
            case .active where !isInBrowser: Task { await model.returnedToForeground() }
            default: break
            }
        }
        .onChange(of: model.notice) { _, notice in
            guard let notice else { return }
            model.notice = nil
            switch notice {
            case let .error(error): toasts.show(error: error)
            case .payoutRequested: toasts.show(l10n.string(.walletPayoutRequested))
            }
        }
        .onChange(of: model.history.refreshError) { _, error in if let error { toasts.show(error: error) } }
        .onChange(of: model.payouts.refreshError) { _, error in if let error { toasts.show(error: error) } }
        .taleedSheet(isPresented: $showsTopUp, onDismiss: topUpSheetDismissed) {
            if let summary = model.summary {
                TopUpSheet(summary: summary, isStarting: model.isStartingTopUp, start: startTopUp, onClose: { showsTopUp = false })
                    .appLanguage(l10n.language)
            }
        }
        .taleedSheet(isPresented: $showsPayout) {
            if let summary = model.summary {
                PayoutSheet(summary: summary, methods: payoutMethods,
                            submit: { amount, method, details in
                                let outcome = await model.requestPayout(amount: amount, method: method, accountDetails: details)
                                if outcome == .sent {
                                    showsPayout = false
                                    Task { await model.reloadAfterPayout() }
                                }
                                return outcome
                            },
                            onClose: { showsPayout = false })
                    .appLanguage(l10n.language)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let summary = model.summary {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                        if let banner = model.banner { TopUpBannerView(banner: banner, onDismiss: model.dismissBanner) }
                        WalletTiles(summary: summary)
                        WalletActions(summary: summary, onTopUp: openTopUpSheet, onPayout: { showsPayout = true })
                            .disabled(isInBrowser)
                    }
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .padding(.top, TaleedSpacing.s16)
                    .padding(.bottom, TaleedSpacing.s24)
                    Section {
                        switch model.tab {
                        case .history: WalletHistorySection(list: model.history)
                        case .payouts: WalletPayoutsSection(list: model.payouts)
                        }
                    } header: {
                        tabs
                    }
                }
                .padding(.bottom, TaleedSpacing.s24)
            }
            .refreshable { await model.refresh() }
            .accessibilityIdentifier("wallet.scroll")
        } else if let error = model.loadError {
            if error.isNotFound {
                NotFoundStateView(onBack: { dismiss() })
            } else {
                ErrorStateView(error: error, retry: { Task { await model.retry() } }, onBack: { dismiss() })
            }
        } else {
            WalletSkeleton()
        }
    }

    /// "Historique" and "Virements (3)" (the API's total, the website counts at most 50); no "(0)", as
    /// "Vos filleuls" on Referrals.
    private var tabs: some View {
        let payouts = l10n.string(.walletPayouts)
        let titles = [
            l10n.string(.walletHistory),
            model.payoutCount.flatMap { $0 > 0 ? l10n.format(.appMyListingsTabCount, payouts, $0) : nil } ?? payouts,
        ]
        return TaleedTabs(titles: titles, selection: Binding(
            get: { model.tab.rawValue },
            set: { model.tab = WalletViewModel.Tab(rawValue: $0) ?? .history }
        ))
        .background(TaleedColor.surfacePrimary)
        .accessibilityIdentifier("wallet.tabs")
    }

    /// The catalog's labels (`GET /catalog`); the website's own while the catalog is not there yet.
    private var payoutMethods: [CatalogOption] {
        if let methods = catalog.catalog?.payoutMethods, !methods.isEmpty { return methods }
        return [
            CatalogOption(value: "CCP", label: l10n.string(.walletMethodCcp)),
            CatalogOption(value: "RIB", label: l10n.string(.walletMethodRib)),
            CatalogOption(value: "BARIDIMOB", label: l10n.string(.walletMethodBaridimob)),
        ]
    }

    // MARK: Top-up

    private func openTopUpSheet() {
        // The last top-up's result is old news once another one starts.
        model.dismissBanner()
        startedTopUp = nil
        isTopUpSheetGone = false
        showsTopUp = true
    }

    /// "Procéder au paiement": the top-up starts, the sheet closes, then the gateway's page opens. The
    /// sheet cannot be closed meanwhile; should it be gone anyway, the page opens at once.
    private func startTopUp(amount: Int, method: String) async {
        guard let started = await model.startTopUp(amount: amount, method: method) else { return }
        if isTopUpSheetGone {
            openPaymentPage(started)
        } else {
            startedTopUp = started
            showsTopUp = false
        }
    }

    /// The sheet is gone: the top-up it started (if any) opens; nothing is kept for a later dismissal.
    private func topUpSheetDismissed() {
        isTopUpSheetGone = true
        guard let started = startedTopUp else { return }
        startedTopUp = nil
        openPaymentPage(started)
    }

    private func openPaymentPage(_ started: StartedTopUp) {
        guard let url = started.paymentURL, !isInBrowser else { return }
        isInBrowser = true
        Task {
            // Back through the return link, or the member closed the page: either way, ask the API.
            _ = try? await webAuthenticationSession.authenticate(
                using: url, callbackURLScheme: LinkRouter.appScheme, preferredBrowserSession: .ephemeral
            )
            isInBrowser = false
            await model.topUpPageClosed(id: started.topUp.id)
        }
    }

    /// A `taleed://payment-return?kind=top_up` link that reached the app on its own.
    private func takePaymentReturn() {
        guard let paymentReturn = router.consumePaymentReturn(kind: .topUp) else { return }
        Task { await model.paymentReturned(paymentReturn) }
    }
}
