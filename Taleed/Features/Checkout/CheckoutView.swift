import AuthenticationServices
import SwiftUI

/// The checkout screen (screens.md §2 G11 and §7 G11; Figma Buy Now 184:2383; website
/// `checkout/[listingId]`): the app bar with the trust shield, "Récapitulatif · Finaliser l'achat", the
/// goods, the delivery method with both fees, the delivery address, the server's summary, the promo
/// code, the wallet, the payment method and the button, without the tab bar.
///
/// States: loading, error with Retry (offline included), "no longer available" (`404`), no longer for
/// sale, blocked, the member's own item; the member's own order awaiting payment opens instead.
/// "Payer" opens the gateway's page in an ephemeral `WebAuthenticationSession`, never a web view; the
/// payment screen then replaces checkout and syncs the order.
struct CheckoutView: View {
    @State private var model: CheckoutViewModel
    /// The gateway's page is open.
    @State private var isInBrowser = false
    @State private var hasAppeared = false
    let route: AppRoute
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(AppToasts.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.shellTab) private var shellTab
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    init(target: CheckoutTarget, route: AppRoute, dependencies: CheckoutDependencies) {
        self.route = route
        _model = State(initialValue: CheckoutViewModel(target: target, dependencies: dependencies))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(
                title: l10n.string(.checkoutTitle),
                onBack: { dismiss() },
                // The wireframe's trust indicator: no action.
                actions: [AppBarAction(icon: .shieldCheck, accessibilityLabel: l10n.string(.trustProtectedPay))]
            )
        } content: {
            content
        }
        .task { await model.loadIfNeeded() }
        .onAppear {
            // No tab bar here: toasts sit at the bottom.
            if let shellTab { toasts.setBottomBarHeight(0, tab: shellTab, route: route) }
            if hasAppeared { Task { await model.refresh() } }
            hasAppeared = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !isInBrowser { Task { await model.refresh() } }
        }
        .onChange(of: model.phase) { _, phase in
            // The member's own order awaiting payment holds the goods: it opens instead (slice F).
            if case let .heldByOrder(orderId) = phase {
                router.replace(route, with: .orderPayment(OrderPaymentTarget(orderId: orderId)))
            }
        }
        .onChange(of: model.notice) { _, notice in
            guard let notice else { return }
            model.notice = nil
            switch notice {
            case let .error(error): toasts.show(error: error)
            case let .info(key): toasts.show(l10n.string(key), kind: .info)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading, .heldByOrder:
            LoadingStateView()
        case .form:
            CheckoutFormView(model: model, isInBrowser: isInBrowser, pay: pay)
        case let .failed(error):
            ErrorStateView(error: error, retry: { Task { await model.retry() } }, onBack: { dismiss() })
        case .notFound:
            NotFoundStateView(title: l10n.string(.checkoutErrorListingUnavailable), onBack: { dismiss() })
        case .unavailable:
            refusal(l10n.string(.checkoutErrorListingUnavailable))
        case .blocked:
            refusal(l10n.string(.commonBlocked))
        case .forbidden:
            refusal(l10n.string(.appErrorForbidden))
        }
    }

    /// The website sends the member back to the goods page: the app offers the way back.
    private func refusal(_ text: String) -> some View {
        MessageStateView(text: text) {
            TaleedButton(title: l10n.string(model.target.bundleId == nil ? .checkoutBackToListing : .commonBack),
                         kind: .tertiary, size: .medium) { dismiss() }
        }
        .accessibilityIdentifier("checkout.refusal")
    }

    // MARK: Ordering

    private func pay() {
        Task {
            switch await model.placeOrder() {
            case let .payOnline(url, orderId, address):
                isInBrowser = true
                // Back through the return link, or the member closed the page (an error): the payment
                // screen asks the API either way.
                let callback = try? await webAuthenticationSession.authenticate(
                    using: url, callbackURLScheme: LinkRouter.appScheme, preferredBrowserSession: .ephemeral
                )
                isInBrowser = false
                let attempt = OrderPaymentViewModel.attempt(from: callback)
                router.replace(route, with: .orderPayment(OrderPaymentTarget(orderId: orderId, attempt: attempt,
                                                                             addressToSave: address)))
            case let .placed(orderId, address):
                router.replace(route, with: .orderPayment(OrderPaymentTarget(orderId: orderId, addressToSave: address)))
            case .stay:
                break
            }
        }
    }
}
