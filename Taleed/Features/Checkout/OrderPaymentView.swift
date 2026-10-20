import AuthenticationServices
import SwiftUI

/// The payment screen of an order (screens.md §2 G11 steps 9–11; the website shows the same results as
/// banners on the order page): it syncs the payment when it opens, then tells the result (paid,
/// confirmed by cash on delivery or the wallet, still waiting with "Payer maintenant", cancelled), the
/// order with the server's amounts, "Enregistrer cette adresse" after a new home address, "Voir ma
/// commande" and the way back to the listing.
///
/// States: "Vérification du paiement…" while the first sync runs, error with Retry (offline included),
/// "no longer available" (`404`); pull-to-refresh and the foreground sync again.
struct OrderPaymentView: View {
    @State private var model: OrderPaymentViewModel
    @State private var isInBrowser = false
    let route: AppRoute
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(AppToasts.self) private var toasts
    @Environment(ListingChangeCenter.self) private var listingChanges
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.shellTab) private var shellTab
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    init(target: OrderPaymentTarget, route: AppRoute, api: CheckoutApi) {
        self.route = route
        _model = State(initialValue: OrderPaymentViewModel(target: target, api: api))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: model.order.map { l10n.format(.ordersOrderNumber, $0.number) } ?? l10n.string(.checkoutTitle),
                            onBack: { dismiss() })
        } content: {
            content
        }
        .task { await model.loadIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !isInBrowser, model.order != nil { Task { await model.sync(automatic: true) } }
        }
        .onChange(of: model.order?.status) { old, new in
            // Paid, or cancelled (the goods back on sale): the listing below shows it once back.
            guard let old, let new, old != new, let order = model.order else { return }
            for item in order.items { listingChanges.post(.stale, listingId: item.listingId) }
        }
        .onChange(of: model.notice) { _, notice in
            guard let notice else { return }
            model.notice = nil
            switch notice {
            case let .error(error): toasts.show(error: error)
            case .saved: toasts.show(l10n.string(.appCheckoutAddressSaved))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let order = model.order, let outcome = model.outcome {
            ScrollView {
                VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                    PaymentResultHeader(outcome: outcome, order: order)
                    if order.status == .pendingPayment, let deadline = order.payDeadlineAt, outcome != .awaitingPayment {
                        InlineAlert(kind: .warning,
                                    title: l10n.format(.ordersPayDeadline, Self.dateTime(deadline, language: l10n.language)))
                    }
                    orderCard(order)
                    OrderSummary(title: l10n.string(.checkoutSummary), lines: summaryLines(order),
                                 totalLabel: l10n.string(order.amounts.walletApplied > 0 ? .ordersRemainderDue : .ordersTotal),
                                 total: order.amounts.walletApplied > 0 ? order.amounts.amountDue : order.amounts.total)
                    addressOffer
                    actions(order)
                }
                .padding(.top, TaleedSpacing.s24)
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.bottom, TaleedSpacing.s48)
            }
            .refreshable { await model.sync() }
            .accessibilityIdentifier("payment.scroll")
        } else if let error = model.loadError {
            if error.isNotFound {
                NotFoundStateView(onBack: { dismiss() })
            } else {
                ErrorStateView(error: error, retry: { Task { await model.retry() } }, onBack: { dismiss() })
            }
        } else {
            CenteredStateColumn {
                ProgressView()
                    .controlSize(.large)
                    .tint(TaleedColor.brandPrimary)
                Text(l10n.string(.appCheckoutVerifying))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textBody)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("payment.verifying")
        }
    }

    // MARK: Order

    private func orderCard(_ order: OrderPaymentInfo) -> some View {
        HStack(spacing: TaleedSpacing.s12) {
            RemoteImage(url: order.imageURL)
                .frame(width: TaleedSize.checkoutThumbWidth, height: TaleedSize.checkoutThumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: TaleedSize.checkoutThumbRadius, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                Text(l10n.format(.ordersOrderNumber, order.number))
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.textSecondary)
                Text(verbatim: order.title.isolatedByContent)
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .lineLimit(2)
                TaleedBadge(title: order.statusLabel, tone: badgeTone(order.status))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(TaleedSpacing.s16)
        .taleedCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("payment.order")
    }

    private func badgeTone(_ status: OrderState) -> TaleedTone {
        switch status {
        case .pendingPayment: .warning
        case .cancelled, .refunded, .disputed: .neutral
        case .unknown: .neutral
        case .paid, .prepared, .shipped, .delivered, .completed: .success
        }
    }

    /// The order's amounts as the server keeps them (the website's order summary).
    private func summaryLines(_ order: OrderPaymentInfo) -> [OrderSummaryLine] {
        let amounts = order.amounts
        let itemLabel = order.items.count > 1 ? l10n.format(.ordersBundleItemsTotal, order.items.count) : l10n.string(.ordersItemPrice)
        var lines = [
            OrderSummaryLine(id: "item", label: itemLabel, amount: amounts.itemPrice),
            OrderSummaryLine(id: "fee", label: l10n.string(.ordersProtectionFee), amount: amounts.protectionFee),
            OrderSummaryLine(id: "shipping", label: l10n.string(.ordersShippingFee), amount: amounts.shippingFee),
        ]
        // One row per part of the discount (website): the promo code, then the referral voucher.
        if amounts.promoDiscount > 0 {
            lines.append(OrderSummaryLine(id: "discount", label: l10n.string(.ordersDiscount), amount: -amounts.promoDiscount,
                                          isDiscount: true))
        }
        if amounts.voucherDiscount > 0 {
            lines.append(OrderSummaryLine(id: "voucher", label: l10n.string(.checkoutVoucher), amount: -amounts.voucherDiscount,
                                          isDiscount: true))
        }
        if amounts.walletApplied > 0 {
            lines.append(OrderSummaryLine(id: "total", label: l10n.string(.ordersTotal), amount: amounts.total))
            lines.append(OrderSummaryLine(id: "wallet", label: l10n.string(.ordersWalletPaid), amount: -amounts.walletApplied,
                                          isDiscount: true))
        }
        return lines
    }

    // MARK: Saving the address

    @ViewBuilder
    private var addressOffer: some View {
        switch model.addressOffer {
        case .offered, .saving:
            VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
                VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                    Text(l10n.string(.appCheckoutSaveAddressTitle))
                        .taleedFont(TaleedFont.buttonMedium)
                        .foregroundStyle(TaleedColor.textPrimary)
                    Text(l10n.string(.appCheckoutSaveAddressBody))
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: TaleedSpacing.s8) {
                    TaleedButton(title: l10n.string(.appCheckoutSaveAddressAction), kind: .tertiary, size: .medium,
                                 isLoading: model.addressOffer == .saving) {
                        Task { await model.saveAddress() }
                    }
                    .accessibilityIdentifier("payment.saveAddress")
                    TaleedButton(title: l10n.string(.commonDismiss), kind: .hyperlink, size: .medium) {
                        model.dismissAddressOffer()
                    }
                    .disabled(model.addressOffer == .saving)
                }
            }
            .padding(TaleedSpacing.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .taleedCard()
        case .saved:
            InlineAlert(kind: .success, title: l10n.string(.appCheckoutAddressSaved))
        case nil:
            EmptyView()
        }
    }

    // MARK: Actions

    private func actions(_ order: OrderPaymentInfo) -> some View {
        VStack(spacing: TaleedSpacing.s12) {
            if order.canPay {
                TaleedButton(title: isInBrowser ? l10n.string(.checkoutProcessing) : l10n.string(.ordersPayNow), kind: .secondary,
                             size: .large, leadingIcon: .lockKey, isLoading: model.isPaying, isFullWidth: true, action: payAgain)
                    .disabled(isInBrowser || model.isSyncing)
                    .accessibilityIdentifier("payment.payNow")
            }
            TaleedButton(title: l10n.string(.checkoutViewOrder), kind: order.canPay ? .outline : .secondary, size: .large,
                         isFullWidth: true) {
                router.push(.order(id: order.id))
            }
            .accessibilityIdentifier("payment.viewOrder")
            if let listingId = order.listingId {
                TaleedButton(title: l10n.string(.checkoutBackToListing), kind: .hyperlink, size: .medium) {
                    backToListing(listingId)
                }
                .accessibilityIdentifier("payment.backToListing")
            }
        }
    }

    /// Back to the listing below when checkout came from it; otherwise opened on top.
    private func backToListing(_ listingId: String) {
        let stack = shellTab.map { router.path($0) } ?? []
        if stack.count >= 2, stack[stack.count - 2] == .listing(id: listingId) {
            dismiss()
        } else {
            router.push(.listing(id: listingId))
        }
    }

    /// "Payer maintenant": a new page from the gateway, then the sync.
    private func payAgain() {
        Task {
            guard let url = await model.paymentPage() else { return }
            isInBrowser = true
            let callback = try? await webAuthenticationSession.authenticate(
                using: url, callbackURLScheme: LinkRouter.appScheme, preferredBrowserSession: .ephemeral
            )
            isInBrowser = false
            await model.paymentPageClosed(callback: callback)
        }
    }

    static func dateTime(_ date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// The result at the top of the payment screen: an icon in a soft circle, the title and what follows.
struct PaymentResultHeader: View {
    let outcome: PaymentOutcome
    let order: OrderPaymentInfo
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: TaleedSpacing.s12) {
            TaleedIconView(icon, size: 32, color: color)
                .frame(width: 64, height: 64)
                .background(Circle().fill(fill))
                .accessibilityHidden(true)
            Text(title)
                .taleedFont(TaleedFont.title2)
                .foregroundStyle(TaleedColor.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textBody)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("payment.result")
    }

    private var icon: TaleedIcon {
        switch outcome {
        case .paid, .confirmed: .checkCircle
        case .awaitingConfirmation, .awaitingPayment: .clock
        case .failed, .expired: .warningCircle
        case .other: .info
        }
    }

    private var color: Color {
        switch outcome {
        case .paid, .confirmed: TaleedColor.feedbackSuccess
        case .failed, .expired: TaleedColor.feedbackError
        case .awaitingConfirmation, .awaitingPayment: TaleedColor.warningIcon
        case .other: TaleedColor.brandPrimary
        }
    }

    private var fill: Color {
        switch outcome {
        case .paid, .confirmed: TaleedColor.successSoft
        case .failed, .expired: TaleedColor.errorSoft
        case .awaitingConfirmation, .awaitingPayment: TaleedColor.warningSoft
        case .other: TaleedColor.blue100
        }
    }

    private var title: String {
        switch outcome {
        case .paid: l10n.string(.checkoutSuccessTitle)
        case .confirmed: l10n.string(.appCheckoutOrderConfirmedTitle)
        case .awaitingConfirmation: l10n.string(.appCheckoutPendingTitle)
        case .failed: l10n.string(.checkoutFailedTitle)
        case .awaitingPayment, .expired, .other: order.statusLabel
        }
    }

    private var message: String? {
        let days = daysUntil(order.shipDeadlineAt)
        let price = { (amount: Int) in PriceFormatter.format(amount, language: l10n.language) }
        switch outcome {
        case .paid, .confirmed(cash: nil):
            return days.map { l10n.format(.checkoutSuccessBody, $0) }
        case let .confirmed(cash?):
            return cash.deliveryFee > 0
                ? l10n.format(.ordersCodNotice, price(cash.total - cash.deliveryFee), price(cash.deliveryFee))
                : l10n.format(.ordersCodNoticeIncluded, price(cash.total))
        case .awaitingConfirmation: return l10n.string(.appCheckoutPendingBody)
        case .failed: return l10n.string(.checkoutFailedBody)
        case .awaitingPayment:
            return order.payDeadlineAt.map { l10n.format(.ordersPayDeadline, OrderPaymentView.dateTime($0, language: l10n.language)) }
        case .expired: return l10n.string(.appCheckoutPaymentExpired)
        case .other: return nil
        }
    }
}
