import SwiftUI

/// Earnings (slice H; website `wallet/page.tsx`; Figma does not draw it, decision D-12): back and
/// "Earnings", the weekly note, the three amounts ("Owed to you" with the next payout's date and why it
/// waits, "In payout", "In progress") as the screen's main figures, the payout details card (the sheet to
/// add or change them), the vouchers with their rules, then the tabs "History" and "Payouts (n)", which
/// stay at the top while scrolling. Nothing here adds, spends or withdraws money (store compliance).
/// Signed out: the sign-in prompt.
///
/// States: a skeleton of the top while the summary loads, the error with Retry (offline included), each
/// tab's loading, error and empty states, pull-to-refresh, pagination, a quiet reload back from the
/// background. Open to suspended members.
struct WalletView: View {
    let api: WalletApi
    /// Opens the payout details sheet once the summary has loaded (a bank refund that waits for them).
    var opensPayoutDetails = false
    @Environment(SessionManager.self) private var session
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if session.isSignedIn {
            // A new screen for another member.
            WalletScreen(api: api, opensPayoutDetails: opensPayoutDetails).id(session.user?.id)
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
    @State private var showsPayoutDetails = false
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppToasts.self) private var toasts
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private let opensPayoutDetails: Bool
    @State private var didOpenPayoutDetails = false

    init(api: WalletApi, opensPayoutDetails: Bool) {
        _model = State(initialValue: WalletViewModel(api: api))
        self.opensPayoutDetails = opensPayoutDetails
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.walletTitle), onBack: { dismiss() })
        } content: {
            content
        }
        .task { await model.loadIfNeeded() }
        .onChange(of: model.summary != nil, initial: true) { _, loaded in
            guard loaded, opensPayoutDetails, !didOpenPayoutDetails else { return }
            didOpenPayoutDetails = true
            showsPayoutDetails = true
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: model.wentToBackground()
            case .active: Task { await model.returnedToForeground() }
            default: break
            }
        }
        .onChange(of: model.notice) { _, notice in
            guard let notice else { return }
            model.notice = nil
            switch notice {
            case let .error(error): toasts.show(error: error)
            case .payoutDetailsSaved: toasts.show(l10n.string(.walletPayoutDetailsSaved))
            }
        }
        .onChange(of: model.history.refreshError) { _, error in if let error { toasts.show(error: error) } }
        .onChange(of: model.payouts.refreshError) { _, error in if let error { toasts.show(error: error) } }
        .taleedSheet(isPresented: $showsPayoutDetails) {
            if let summary = model.summary {
                PayoutDetailsSheet(account: summary.payoutAccount, limits: summary.limits, methods: payoutMethods,
                                   save: { method, details in
                                       let outcome = await model.savePayoutDetails(method: method, accountDetails: details)
                                       if outcome == .saved {
                                           showsPayoutDetails = false
                                           // The owed note may change with the details.
                                           Task { await model.reloadSummary() }
                                       }
                                       return outcome
                                   },
                                   onClose: { showsPayoutDetails = false })
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
                        EarningsWeeklyNote()
                        WalletTiles(summary: summary)
                        PayoutDetailsCard(account: summary.payoutAccount) { showsPayoutDetails = true }
                        VouchersCard(voucherBalance: summary.voucherBalance, limits: summary.limits)
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

    /// "History" and "Payouts (3)" (the API's total, the website counts at most 50); no "(0)", as
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

    /// The catalog's labels (`GET /catalog`), only for the methods this build can send; the website's own
    /// while the catalog is not there yet.
    private var payoutMethods: [CatalogOption] {
        WalletRules.payoutMethods(catalog.catalog?.payoutMethods, fallback: [
            CatalogOption(value: "CCP", label: l10n.string(.walletMethodCcp)),
            CatalogOption(value: "RIB", label: l10n.string(.walletMethodRib)),
            CatalogOption(value: "BARIDIMOB", label: l10n.string(.walletMethodBaridimob)),
        ])
    }
}
