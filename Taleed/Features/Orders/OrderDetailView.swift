import AuthenticationServices
import SwiftUI

/// The order screen (screens.md §2 G12 screens 2–3 and §7 G12; website `orders/[id]/page.tsx`; Figma
/// does not draw it, decision D-12, so it is built from the design system's cards, badges, inline
/// alerts, order summary and buttons):
/// - the status badge with the server's label and the date;
/// - the notices: pay before, the seller ships before, cash on delivery, the parcel waits at the
///   pick-up point, funds released on;
/// - the dispute summary and its thread;
/// - the goods (one item, or each item of a bundle) and the other member;
/// - the member's buttons, only from `actions`. The buyer's: "Payer maintenant", "Confirmer la
///   réception" (after a confirmation; disabled with its hint while the parcel travels), "Laisser une
///   évaluation", "Signaler un problème", "Annuler la commande" (after a confirmation). The seller's
///   (G13): "Bordereau d'expédition" (after a confirmation; the carrier takes several seconds, then the
///   label opens in the in-app browser, whose share sheet prints), "Imprimer le bordereau" (a fresh link
///   on each tap), "Générer le vrai bordereau" (test servers), "Accepter la réclamation" (after a
///   confirmation) and "Contester", "Laisser une évaluation". A carrier refusal stays under the buttons
///   with the carrier's own words. Then "Envoyer un message";
/// - the amounts, the delivery with its tracking number, the timeline with the carrier's scans folded
///   under it, and the reviews.
///
/// States: loading, error with Retry (offline included), "no longer available" (`404`), pull-to-refresh,
/// reload on return to the foreground and when shown again.
struct OrderDetailView: View {
    @State private var model: OrderDetailViewModel
    @State private var confirmation: Confirmation?
    @State private var sheet: Sheet?
    let dependencies: OrdersDependencies
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(AppToasts.self) private var toasts
    @Environment(OrderChangeCenter.self) private var orderChanges
    @Environment(ListingChangeCenter.self) private var listingChanges
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    private enum Confirmation: Equatable {
        case cancel, confirmReceipt, ship, replaceTestLabel, acceptClaim
    }

    private enum Sheet: String, Identifiable {
        case dispute, review
        var id: String { rawValue }
    }

    init(orderId: String, dependencies: OrdersDependencies) {
        self.dependencies = dependencies
        _model = State(initialValue: OrderDetailViewModel(orderId: orderId, api: dependencies.orders))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: model.order.map { l10n.format(.ordersOrderNumber, $0.number) } ?? l10n.string(.ordersTitle),
                            onBack: { dismiss() })
        } content: {
            content
        }
        .task { await model.loadIfNeeded() }
        .onAppear { Task { await model.appeared() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !model.isInPaymentPage, model.order != nil { Task { await model.reload(automatic: true) } }
        }
        .onChange(of: model.order) { old, new in orderChanged(from: old, to: new) }
        .onChange(of: model.notice) { _, notice in
            guard let notice else { return }
            model.notice = nil
            switch notice {
            case let .success(key): toasts.show(l10n.string(key))
            case let .info(key): toasts.show(l10n.string(key), kind: .info)
            case let .payment(key, kind): toasts.show(l10n.string(key), kind: kind)
            case let .error(error): toasts.show(error: error)
            }
        }
        .onChange(of: model.carrierError) { _, error in
            // The refusal shows under the buttons: say it too.
            if let error { AccessibilityNotification.Announcement(l10n.message(for: error)).post() }
        }
        .taleedConfirmation(isPresented: confirmation != nil) { confirmationModal }
        .sheet(item: $sheet) { sheet in
            // A sheet does not inherit the app's language and direction.
            Group {
                switch sheet {
                case .dispute: disputeSheet
                case .review: reviewSheet
                }
            }
            .appLanguage(l10n.language)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let order = model.order {
            ScrollView {
                VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                    OrderStatusHeader(order: order)
                    OrderNoticesView(order: order)
                    if let dispute = order.dispute {
                        OrderDisputeCard(dispute: dispute, side: order.side) { router.push(.dispute(id: dispute.id)) }
                    }
                    OrderGoodsCard(order: order)
                    actions(order)
                    OrderSummary(title: l10n.string(.checkoutSummary), lines: summaryLines(order),
                                 totalLabel: totalLabel(order), total: OrderRules.amounts(for: order).totalAmount)
                    OrderDeliveryCard(delivery: order.delivery)
                    OrderTimelineCard(steps: order.steps, scans: order.carrierScans)
                    OrderReviewsCard(order: order)
                }
                .padding(.top, TaleedSpacing.s16)
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.bottom, TaleedSpacing.s48)
            }
            .refreshable { await model.reload() }
            .accessibilityIdentifier("order.scroll")
        } else if let error = model.loadError {
            if error.isNotFound {
                NotFoundStateView(onBack: { dismiss() })
            } else {
                ErrorStateView(error: error, retry: { Task { await model.retry() } }, onBack: { dismiss() })
            }
        } else {
            LoadingStateView()
        }
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(_ order: OrderDetailInfo) -> some View {
        let memberActions = model.memberActions
        if !memberActions.isEmpty || order.conversationId != nil {
            VStack(spacing: TaleedSpacing.s12) {
                ForEach(Array(memberActions.enumerated()), id: \.offset) { index, action in
                    button(action, isFirst: index == 0)
                }
                if model.showsCarrierError, let error = model.carrierError {
                    InlineAlert(kind: .error, title: l10n.message(for: error), message: error.detail)
                        .accessibilityIdentifier("order.carrierError")
                }
                if let conversationId = order.conversationId {
                    // The other member by role: "Message buyer" on a sale.
                    let label: L10nKey = order.side == .seller ? .appOrderMessageBuyer : .listingMessageSeller
                    TaleedButton(title: l10n.string(label), kind: .tertiary, size: .large, leadingIcon: .chatCircle,
                                 isFullWidth: true) {
                        router.push(.conversation(id: conversationId))
                    }
                    .accessibilityIdentifier("order.message")
                }
            }
        }
    }

    @ViewBuilder
    private func button(_ action: OrderRules.MemberAction, isFirst: Bool) -> some View {
        // The first action is the main one (mint, decision D-10); the others are quieter.
        let isBusy = model.busy != nil
        switch action {
        case .pay:
            TaleedButton(title: model.isInPaymentPage ? l10n.string(.checkoutProcessing) : l10n.string(.ordersPayNow),
                         kind: .secondary, size: .large, leadingIcon: .lockKey, isLoading: model.busy == .paying,
                         isFullWidth: true, action: pay)
                .disabled(isBusy || model.isInPaymentPage)
                .accessibilityIdentifier("order.pay")
        case .confirmReceipt:
            TaleedButton(title: l10n.string(.ordersConfirmReceipt), kind: isFirst ? .secondary : .outline, size: .large,
                         leadingIcon: .checkCircle, isLoading: model.busy == .confirming, isFullWidth: true) {
                confirmation = .confirmReceipt
            }
            .disabled(isBusy)
            .accessibilityIdentifier("order.confirmReceipt")
        case .awaitingArrival:
            AwaitingArrivalButton()
        case .review:
            TaleedButton(title: l10n.string(.ordersLeaveReview), kind: isFirst ? .secondary : .outline, size: .large,
                         leadingIcon: .star, isFullWidth: true) {
                sheet = .review
            }
            .disabled(isBusy)
            .accessibilityIdentifier("order.review")
        case .openDispute:
            TaleedButton(title: l10n.string(.ordersOpenDispute), kind: .outline, size: .large, leadingIcon: .warning,
                         isFullWidth: true) {
                sheet = .dispute
            }
            .disabled(isBusy)
            .accessibilityIdentifier("order.openDispute")
        case .cancel:
            TaleedButton(title: l10n.string(.ordersCancelOrder), kind: .hyperlink, size: .medium,
                         isLoading: model.busy == .cancelling) {
                confirmation = .cancel
            }
            .disabled(isBusy)
            .accessibilityIdentifier("order.cancel")
        case .ship, .printLabel, .replaceTestLabel, .acceptClaim, .contestClaim:
            SellerOrderButton(action: action, isFirst: isFirst, busy: model.busy, perform: performSellerAction)
        }
    }

    /// A seller's button: ship, replace the demo label and accept the claim ask first.
    private func performSellerAction(_ action: OrderRules.MemberAction) {
        switch action {
        case .ship: confirmation = .ship
        case .replaceTestLabel: confirmation = .replaceTestLabel
        case .acceptClaim: confirmation = .acceptClaim
        // No confirmation, as on the website: Taleed mediates, nothing is paid out.
        case .contestClaim: Task { await model.answerClaim(.contest) }
        case .printLabel: printLabel()
        case .pay, .confirmReceipt, .awaitingArrival, .openDispute, .cancel, .review: break
        }
    }

    /// Creates the parcel, then opens its label (the website opens it in a new tab).
    private func ship() {
        Task {
            if let url = await model.ship() { InAppBrowser.open(url) }
        }
    }

    /// A fresh link to the label, opened in the in-app browser: the carrier's PDF or the printable page,
    /// printed from its share sheet.
    private func printLabel() {
        Task {
            if let url = await model.labelURL() { InAppBrowser.open(url) }
        }
    }

    /// "Payer maintenant": a new page from the gateway in the browser tab, then the sync.
    private func pay() {
        Task {
            guard let url = await model.paymentPage() else { return }
            let callback = try? await webAuthenticationSession.authenticate(
                using: url, callbackURLScheme: LinkRouter.appScheme, preferredBrowserSession: .ephemeral
            )
            await model.paymentPageClosed(callback: callback)
        }
    }

    private var confirmationModal: ConfirmationModalCard {
        switch confirmation {
        case .confirmReceipt:
            ConfirmationModalCard(title: l10n.string(.ordersConfirmReceipt), message: l10n.string(.ordersConfirmReceiptHint),
                                  confirmTitle: l10n.string(.commonConfirm),
                                  onConfirm: {
                                      confirmation = nil
                                      Task { await model.confirmReceipt() }
                                  },
                                  onCancel: { confirmation = nil },
                                  icon: .checkCircle, tone: .positive)
        case .ship:
            shipModal(title: .ordersGetShippingLabel, message: .ordersGetShippingLabelHint)
        case .replaceTestLabel:
            shipModal(title: .ordersGetRealShippingLabel, message: .ordersGetRealShippingLabelHint)
        case .acceptClaim:
            ConfirmationModalCard(title: l10n.string(.disputesAcceptClaim), message: l10n.string(.disputesAcceptClaimHint),
                                  confirmTitle: l10n.string(.disputesAcceptClaim),
                                  onConfirm: {
                                      confirmation = nil
                                      Task { await model.answerClaim(.accept) }
                                  },
                                  onCancel: { confirmation = nil },
                                  icon: .checkCircle, tone: .positive)
        case .cancel, nil:
            ConfirmationModalCard(title: l10n.string(.appOrderCancelTitle),
                                  message: l10n.string((model.order?.amounts.walletApplied ?? 0) > 0
                                      ? .appOrderCancelBody : .appOrderCancelBodyNoWallet),
                                  confirmTitle: l10n.string(.ordersCancelOrder),
                                  onConfirm: {
                                      confirmation = nil
                                      Task { await model.cancel() }
                                  },
                                  onCancel: { confirmation = nil },
                                  cancelTitle: l10n.string(.commonBack),
                                  icon: .x)
        }
    }

    /// "Bordereau d'expédition" or "Générer le vrai bordereau": what happens, then "Générer et télécharger".
    private func shipModal(title: L10nKey, message: L10nKey) -> ConfirmationModalCard {
        ConfirmationModalCard(title: l10n.string(title), message: l10n.string(message),
                              confirmTitle: l10n.string(.ordersGenerateAndDownload),
                              onConfirm: {
                                  confirmation = nil
                                  ship()
                              },
                              onCancel: { confirmation = nil },
                              icon: .truck, tone: .positive)
    }

}

// MARK: - Sheets, amounts, changes

private extension OrderDetailView {
    var disputeSheet: some View {
        DisputeFormSheet(model: DisputeFormViewModel(orderId: model.orderId, api: dependencies.orders,
                                                     upload: { [uploads = dependencies.uploads] data throws(ApiError) in
                                                         try await uploads.upload(data, purpose: .disputeEvidence)
                                                     })) { outcome in
            switch outcome {
            case let .opened(dispute):
                toasts.show(l10n.string(.disputesOpened))
                Task { await model.reload(automatic: true) }
                router.push(.dispute(id: dispute.id))
            case let .orderChanged(error):
                Task { await model.actionFailed(error) }
            case .failed:
                break
            }
        }
    }

    var reviewSheet: some View {
        ReviewFormSheet(model: ReviewFormViewModel(orderId: model.orderId, api: dependencies.orders)) { outcome in
            switch outcome {
            case let .reviewed(order):
                model.show(order)
                toasts.show(l10n.string(.reviewsThanks))
            case let .orderChanged(error):
                Task { await model.actionFailed(error) }
            case .failed:
                break
            }
        }
    }

    // MARK: Amounts

    func summaryLines(_ order: OrderDetailInfo) -> [OrderSummaryLine] {
        OrderRules.amounts(for: order).lines.enumerated().map { index, entry in
            let (line, amount) = entry
            let label: String = switch line {
            case let .itemPrice(count?): l10n.format(.ordersBundleItemsTotal, count)
            case .itemPrice(nil): l10n.string(.ordersItemPrice)
            case .protectionFee: l10n.string(.ordersProtectionFee)
            case .shippingFee: l10n.string(.ordersShippingFee)
            case .discount: l10n.string(.ordersDiscount)
            case .total: l10n.string(.ordersTotal)
            case .walletPaid: l10n.string(.ordersWalletPaid)
            }
            return OrderSummaryLine(id: "\(index)", label: label, amount: amount, isDiscount: amount < 0)
        }
    }

    func totalLabel(_ order: OrderDetailInfo) -> String {
        switch OrderRules.amounts(for: order).total {
        case .total: l10n.string(.ordersTotal)
        case .remainderDue: l10n.string(.ordersRemainderDue)
        case .sellerEarns: l10n.string(.ordersSellerEarns)
        }
    }

    // MARK: Changes

    /// The list below shows the new status; a cancelled order put its items back on sale.
    func orderChanged(from old: OrderDetailInfo?, to new: OrderDetailInfo?) {
        guard let new, let old, old.status != new.status || old.statusLabel != new.statusLabel else { return }
        orderChanges.post(new)
        if new.status == .cancelled {
            for item in new.items { listingChanges.post(.stale, listingId: item.listingId) }
        }
    }
}

/// "Confirmer la réception" disabled while the parcel travels, with "Disponible dès que le colis est
/// arrivé à destination." under it (slice D, Receiving).
private struct AwaitingArrivalButton: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: TaleedSpacing.s8) {
            TaleedButton(title: l10n.string(.ordersConfirmReceipt), kind: .secondary, size: .large, leadingIcon: .checkCircle,
                         isFullWidth: true) {}
                .disabled(true)
                .accessibilityHint(l10n.string(.ordersConfirmReceiptWaiting))
            Text(l10n.string(.ordersConfirmReceiptWaiting))
                .taleedFont(TaleedFont.bodySmall)
                .foregroundStyle(TaleedColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
        .accessibilityIdentifier("order.awaitingArrival")
    }
}
