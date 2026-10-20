import AuthenticationServices
import SwiftUI

/// The wallet (screens.md §2 G14 and §7 G14; website `wallet/page.tsx`; Figma does not draw it,
/// decision D-12): back and "Portefeuille", the result of the last top-up, "Recharger" (only when a
/// gateway takes top-ups) and "Demander un virement" (disabled under the minimum, with "Minimum : 100 DA"),
/// the two tiles ("Solde disponible" with its voucher part, "En attente"), then the tabs "Historique" and
/// "Virements (n)", which stay at the top while scrolling.
///
/// States: a skeleton while the header loads, the error with Retry (offline included), each tab's
/// loading, error and empty states, pull-to-refresh, pagination, a quiet reload back from the background.
struct WalletView: View {
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

    init(api: WalletApi, opensPayout: Bool = false) {
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
                        WalletActions(summary: summary, onTopUp: openTopUpSheet, onPayout: { showsPayout = true })
                            .disabled(isInBrowser)
                        WalletTiles(summary: summary)
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

    /// "Historique" and "Virements (3)" (the API's total, the website counts at most 50).
    private var tabs: some View {
        let payouts = l10n.string(.walletPayouts)
        let titles = [
            l10n.string(.walletHistory),
            model.payoutCount.map { l10n.format(.appMyListingsTabCount, payouts, $0) } ?? payouts,
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

// MARK: - Header

/// "Recharger" (mint, the website's CTA) and "Demander un virement" (blue), side by side when they fit,
/// stacked otherwise; "Minimum : 100 DA" under them while the balance is under the minimum.
private struct WalletActions: View {
    let summary: WalletSummary
    let onTopUp: () -> Void
    let onPayout: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TaleedSpacing.s12) { buttons }
                VStack(spacing: TaleedSpacing.s12) { buttons }
            }
            if !WalletRules.canRequestPayout(summary) {
                FieldHelper(text: l10n.format(.walletMinPayout, PriceFormatter.format(summary.limits.minPayout, language: l10n.language)))
                    .accessibilityHidden(false)
                    .accessibilityIdentifier("wallet.minPayout")
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if WalletRules.showsTopUp(summary) {
            TaleedButton(title: l10n.string(.walletTopUp), kind: .secondary, size: .large, leadingIcon: .plusCircle,
                         isFullWidth: true, action: onTopUp)
                .accessibilityIdentifier("wallet.topUp")
        }
        TaleedButton(title: l10n.string(.walletRequestPayout), kind: .primary, size: .large, leadingIcon: .money,
                     isFullWidth: true, action: onPayout)
            .disabled(!WalletRules.canRequestPayout(summary))
            .accessibilityHint(WalletRules.canRequestPayout(summary)
                ? "" : l10n.format(.walletMinPayout, PriceFormatter.format(summary.limits.minPayout, language: l10n.language)))
            .accessibilityIdentifier("wallet.requestPayout")
    }
}

/// The two tiles of the website, in one bordered card: "Solde disponible" (balance plus vouchers, with
/// the voucher part) and "En attente (commandes en cours)", muted, with its hint.
private struct WalletTiles: View {
    let summary: WalletSummary
    @Environment(LanguageManager.self) private var l10n

    static let headlineStyle = TaleedTextStyle(size: 28, weight: .extrabold, lineHeight: nil, letterSpacing: 0, relativeTo: .title)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tile(icon: .money, title: l10n.string(.walletBalance), amount: summary.headline, color: TaleedColor.textPrimary,
                 note: WalletRules.showsVoucherPart(summary)
                     ? (.ticket, l10n.format(.walletVoucherPart, PriceFormatter.format(summary.voucherBalance, language: l10n.language)))
                     : nil)
                .accessibilityIdentifier("wallet.balance")
            Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1).accessibilityHidden(true)
            tile(icon: .lockKey, title: l10n.string(.walletPendingEscrow), amount: summary.pendingEscrow,
                 color: TaleedColor.textSecondary, note: (.info, l10n.string(.walletPendingHint)))
                .accessibilityIdentifier("wallet.pending")
        }
        .taleedCard(radius: TaleedRadius.l)
    }

    private func tile(icon: TaleedIcon, title: String, amount: Int, color: Color, note: (TaleedIcon, String)?) -> some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            HStack(spacing: 6) {
                TaleedIconView(icon, size: 14, color: TaleedColor.textSecondary)
                    .accessibilityHidden(true)
                Text(title.uppercased(with: l10n.language.locale))
                    .taleedFont(TaleedFont.eyebrow)
                    .foregroundStyle(TaleedColor.textSecondary)
                    .accessibilityLabel(title)
            }
            PriceText(amount: amount, style: Self.headlineStyle, color: color)
            if let note {
                HStack(alignment: .firstTextBaseline, spacing: TaleedSpacing.s4) {
                    TaleedIconView(note.0, size: 12, color: TaleedColor.textSecondary)
                        .accessibilityHidden(true)
                    Text(note.1)
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The top-up's result, as the website's banners; "Vérification du paiement…" while the sync runs.
private struct TopUpBannerView: View {
    let banner: TopUpBanner
    let onDismiss: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        Group {
            switch banner {
            case .checking:
                HStack(spacing: TaleedSpacing.s12) {
                    ProgressView().tint(TaleedColor.brandPrimary)
                    Text(l10n.string(.appCheckoutVerifying))
                        .taleedFont(TaleedFont.bodyLarge)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(TaleedSize.alertPadding)
                .background(TaleedColor.blue100, in: RoundedRectangle(cornerRadius: TaleedSize.alertRadius, style: .continuous))
                .accessibilityElement(children: .combine)
            case .paid:
                InlineAlert(kind: .success, title: l10n.string(.walletToppedUp), actionTitle: l10n.string(.commonDismiss),
                            action: onDismiss)
            case .pending:
                InlineAlert(kind: .info, title: l10n.string(.walletTopUpPending), actionTitle: l10n.string(.commonDismiss),
                            action: onDismiss)
            case .failed:
                InlineAlert(kind: .error, title: l10n.string(.walletTopUpFailed), actionTitle: l10n.string(.commonDismiss),
                            action: onDismiss)
            }
        }
        .accessibilityIdentifier("wallet.banner")
        .onAppear { announce() }
        .onChange(of: banner) { _, _ in announce() }
    }

    private func announce() {
        let text: String = switch banner {
        case .checking: l10n.string(.appCheckoutVerifying)
        case .paid: l10n.string(.walletToppedUp)
        case .pending: l10n.string(.walletTopUpPending)
        case .failed: l10n.string(.walletTopUpFailed)
        }
        AccessibilityNotification.Announcement(text).post()
    }
}

/// The header's shape while it loads (six blocks at most, design-system §3.6).
private struct WalletSkeleton: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                HStack(spacing: TaleedSpacing.s12) {
                    SkeletonBlock(height: 48, radius: TaleedRadius.m)
                    SkeletonBlock(height: 48, radius: TaleedRadius.m)
                }
                VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
                    SkeletonBlock(width: 120, height: 12)
                    SkeletonBlock(width: 180, height: 30)
                    SkeletonBlock(width: 140, height: 12)
                    SkeletonBlock(width: 160, height: 30)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .taleedCard(radius: TaleedRadius.l)
            }
            .padding(.horizontal, TaleedLayout.screenMargin)
            .padding(.top, TaleedSpacing.s16)
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.string(.commonLoading))
        .accessibilityIdentifier("wallet.loading")
    }
}
