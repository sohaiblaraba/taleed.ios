import SwiftUI

/// The bundle review screen (screens.md §2 G10 screen 5 and §7 G10; website `bundle/[id]`; the order
/// summary of Figma Buy Now 184:2383): "Achat groupé · Récapitulatif du lot", the seller, the items
/// (those no longer for sale greyed with "Indisponible", each with "Retirer"), the notice about them, the
/// accepted offer, the summary from the server, then "Faire une offre" and "Acheter le lot" at the bottom
/// and "Poser une question au vendeur".
///
/// States: loading, error with Retry (offline included), "no longer available" (`404`), an empty bundle,
/// a bundle already ordered (its order) or cancelled; pull-to-refresh and a quiet reload when the
/// screen shows again.
struct BundleReviewView: View {
    @State private var model: BundleReviewViewModel
    @State private var offersOnBundle = false
    /// The item whose "Retirer" waits for confirmation: the bundle has an accepted offer it would cancel.
    @State private var confirmingRemoval: BundleLine?
    @State private var hasAppeared = false
    /// The large heading "Récapitulatif du lot" is on screen: the app bar leaves its title out.
    @State private var headingVisible = true
    let route: AppRoute
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(AppToasts.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.shellTab) private var shellTab
    @Environment(\.pushRegistration) private var push

    init(bundleId: String, route: AppRoute, api: BundlesApi) {
        self.route = route
        _model = State(initialValue: BundleReviewViewModel(bundleId: bundleId, api: api))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.bundleReviewTitle), onBack: { dismiss() },
                            showsTitle: model.bundle == nil || !headingVisible)
        } content: {
            content
                .taleedSheet(isPresented: $offersOnBundle) { offerSheet }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if let shellTab { toasts.setBottomBarHeight(height, tab: shellTab, route: route) }
            }
        }
        .task { await model.loadIfNeeded() }
        .onAppear {
            // Back from a listing or the conversation: the bundle may have changed there.
            if hasAppeared { Task { await model.reload(automatic: true) } }
            hasAppeared = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.reload(automatic: true) } }
        }
        .taleedConfirmation(isPresented: confirmingRemoval != nil) {
            ConfirmationModalCard(
                title: l10n.string(.appBundleRemoveTitle),
                message: l10n.format(.appBundleRemoveBody,
                                     PriceFormatter.format(model.bundle?.acceptedOffer?.amount ?? 0, language: l10n.language)),
                confirmTitle: l10n.string(.bundleRemove),
                onConfirm: {
                    guard let item = confirmingRemoval else { return }
                    confirmingRemoval = nil
                    Task { await model.remove(item.listingId) }
                },
                onCancel: { confirmingRemoval = nil },
                icon: .warning
            )
        }
        .onChange(of: model.notice) { _, notice in
            guard let notice else { return }
            model.notice = nil
            switch notice {
            case let .error(error): toasts.show(error: error)
            case let .confirmation(key): toasts.show(l10n.string(key))
            case let .information(key): toasts.show(l10n.string(key), kind: .info)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let bundle = model.bundle, let state = model.content {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeading(eyebrow: l10n.string(.bundleReviewEyebrow), title: l10n.string(.bundleReviewTitle))
                        // The bar's title shows once the heading has scrolled under it.
                        .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY > 0 } action: { headingVisible = $0 }
                    VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                        seller(bundle)
                        switch state {
                        case .items: items(bundle)
                        case .empty: emptyBundle(bundle)
                        case let .ordered(orderId): ordered(orderId)
                        case .closed: EmptyState(title: l10n.string(.appBundleClosed), icon: .storefront)
                        }
                    }
                    .padding(.top, TaleedSpacing.s24)
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .padding(.bottom, TaleedSpacing.s48)
                }
            }
            .refreshable { await model.reload() }
            .accessibilityIdentifier("bundle.scroll")
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

    private func seller(_ bundle: BundleDetail) -> some View {
        SellerRow(name: bundle.seller.displayName, reputation: l10n.string(.bundleSellerLots), imageURL: bundle.seller.avatarURL,
                  isVerified: bundle.seller.isVerified || bundle.seller.isOfficial,
                  verifiedLabel: l10n.string(bundle.seller.isOfficial ? .profileOfficial : .profileVerified)) {
            if let username = bundle.seller.username { router.push(.member(username: username)) }
        }
        .disabled(bundle.seller.username == nil)
    }

    @ViewBuilder
    private func items(_ bundle: BundleDetail) -> some View {
        if bundle.unavailableCount > 0 {
            // Above the items, so the greyed ones come with their reason (below them it ended under the bar).
            InlineAlert(kind: .warning, title: l10n.format(.bundleUnavailableNotice, bundle.unavailableCount))
                .accessibilityIdentifier("bundle.unavailableNotice")
        }
        VStack(spacing: TaleedSpacing.s12) {
            ForEach(bundle.items) { item in
                BundleItemRow(item: item, isRemoving: model.work == .remove(listingId: item.listingId),
                              isDisabled: model.work != nil,
                              open: { router.push(.listing(id: item.listingId)) },
                              remove: { remove(item) })
            }
        }
        if let accepted = bundle.acceptedOffer {
            InlineAlert(kind: .success,
                        title: l10n.format(.appListingAcceptedOffer, PriceFormatter.format(accepted.amount, language: l10n.language)))
        }
        if !bundle.availableItems.isEmpty {
            OrderSummary(title: l10n.string(.bundleSummary), lines: summaryLines(bundle), totalLabel: l10n.string(.bundleTotalToPay),
                         total: bundle.total)
                .accessibilityIdentifier("bundle.summary")
        }
        if bundle.canBuy {
            TaleedButton(title: l10n.string(.bundleAskSeller), kind: .hyperlink, size: .medium, leadingIcon: .chatCircle,
                         isLoading: model.work == .ask, isFullWidth: true, action: askSeller)
                .disabled(model.work != nil)
                .accessibilityIdentifier("bundle.ask")
        }
    }

    /// The server's amounts, line by line (screens.md §0.2): the items (or the accepted offer), the fee,
    /// the shipping estimate ("dès 400 DA", or "calculée au paiement").
    private func summaryLines(_ bundle: BundleDetail) -> [OrderSummaryLine] {
        let shipping = bundle.shippingFrom.map {
            l10n.format(.bundleShippingFrom, PriceFormatter.format($0, language: l10n.language))
        } ?? l10n.string(.bundleShippingAtCheckout)
        return [
            OrderSummaryLine(id: "items", label: l10n.format(.bundleItemsTotal, bundle.availableItems.count), amount: bundle.itemsTotal),
            OrderSummaryLine(id: "fee", label: l10n.string(.bundleProtectionFee), amount: bundle.protectionFee),
            OrderSummaryLine(id: "shipping", label: l10n.string(.bundleShipping), amount: nil, valueText: shipping),
        ]
    }

    private func emptyBundle(_ bundle: BundleDetail) -> some View {
        EmptyState(title: l10n.string(.bundleEmpty), actionTitle: bundle.seller.username == nil ? nil : l10n.string(.bundleSellerLots),
                   action: { if let username = bundle.seller.username { router.push(.bundleBuilder(username: username)) } },
                   icon: .storefront)
            .frame(maxWidth: .infinity)
    }

    private func ordered(_ orderId: String?) -> some View {
        EmptyState(title: l10n.string(.appBundleOrdered), actionTitle: orderId == nil ? nil : l10n.string(.checkoutViewOrder),
                   action: { if let orderId { router.push(.order(id: orderId)) } }, icon: .checkCircle)
            .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    @ViewBuilder
    private var actionBar: some View {
        if let bundle = model.bundle, model.content == .items {
            let buyTitle = bundle.acceptedOffer.map {
                "\(l10n.string(.offersPayNow)) · \(PriceFormatter.format($0.amount, language: l10n.language))"
            } ?? l10n.string(.bundleBuy)
            BottomActionBar {
                ViewThatFits(in: .horizontal) {
                    GrowRow(spacing: TaleedSize.bottomActionBarGap) { barButtons(bundle, buyTitle: buyTitle) }
                    VStack(spacing: TaleedSize.bottomActionBarGap) { barButtons(bundle, buyTitle: buyTitle) }
                }
            }
        }
    }

    @ViewBuilder
    private func barButtons(_ bundle: BundleDetail, buyTitle: String) -> some View {
        if bundle.offerRange != nil {
            TaleedButton(title: l10n.string(.offersMakeOffer), kind: .tertiary, size: .large, isFullWidth: true) {
                offersOnBundle = true
            }
            .disabled(model.work != nil)
            .accessibilityIdentifier("bundle.offer")
        }
        TaleedButton(title: buyTitle, kind: .secondary, size: .large, leadingIcon: .storefront, isFullWidth: true) {
            if let checkout = model.checkout { router.pushSignedIn(.checkout(checkout)) }
        }
        // Off while the items save, as the bundle's other actions.
        .disabled(model.checkout == nil || model.work != nil)
        .accessibilityIdentifier("bundle.buy")
    }

    @ViewBuilder
    private var offerSheet: some View {
        if let bundle = model.bundle, let range = bundle.offerRange {
            OfferAmountSheet(
                title: l10n.string(.bundleOfferTitle),
                hint: l10n.format(.bundleOfferHint, PriceFormatter.format(bundle.subtotal, language: l10n.language)),
                range: range,
                submit: { amount in
                    let outcome = await model.makeOffer(amount: amount)
                    switch outcome {
                    case let .outOfRange(newRange?): return .showRange(newRange)
                    case .busy: return .stay
                    case .sent, .pending, .outOfRange(nil), .failed:
                        offersOnBundle = false
                        offerFinished(outcome)
                        return .finish
                    }
                },
                onClose: { offersOnBundle = false }
            )
        }
    }

    private func offerFinished(_ outcome: BundleReviewViewModel.OfferOutcome) {
        switch outcome {
        case let .sent(conversationId):
            toasts.show(l10n.string(.offersOfferSent))
            router.pushSignedIn(.conversation(id: conversationId))
            Task { await push?.memberReachedOut() }
        case let .pending(conversationId):
            toasts.show(l10n.string(.offersErrorActive), kind: .info)
            router.pushSignedIn(.conversation(id: conversationId))
        case .outOfRange:
            toasts.show(l10n.string(.appErrorOfferOutOfRange), kind: .error)
        case .failed, .busy:
            break
        }
    }

    /// "Retirer": changing the items withdraws the bundle's offers (screens.md §2 G10), so with an
    /// accepted price the member confirms first (an app-only confirmation, like Accept).
    private func remove(_ item: BundleLine) {
        if model.removalCancelsAcceptedOffer {
            confirmingRemoval = item
        } else {
            Task { await model.remove(item.listingId) }
        }
    }

    private func askSeller() {
        Task {
            if let conversationId = await model.askSeller() {
                router.pushSignedIn(.conversation(id: conversationId, focusesComposer: true))
            }
        }
    }
}

/// An item of the bundle: its photo, title and price (Checkout item §4.3), greyed with "Indisponible"
/// when no longer for sale, and "Retirer". The row opens the listing.
struct BundleItemRow: View {
    let item: BundleLine
    let isRemoving: Bool
    let isDisabled: Bool
    let open: () -> Void
    let remove: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        HStack(alignment: .center, spacing: TaleedSpacing.s12) {
            Button(action: open) {
                HStack(spacing: TaleedSpacing.s12) {
                    RemoteImage(url: item.imageURL)
                        .frame(width: TaleedSize.checkoutThumbWidth, height: TaleedSize.checkoutThumbHeight)
                        .clipShape(RoundedRectangle(cornerRadius: TaleedSize.checkoutThumbRadius, style: .continuous))
                    VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                        Text(verbatim: item.title.isolatedByContent)
                            .taleedFont(TaleedFont.bodyRegular)
                            .foregroundStyle(TaleedColor.textPrimary)
                            .lineLimit(2)
                        PriceText(amount: item.price, style: TaleedFont.buttonMedium)
                        if !item.isAvailable {
                            TaleedBadge(title: l10n.string(.bundleUnavailable), tone: .neutral)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .opacity(item.isAvailable ? 1 : 0.6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isLink)
            TaleedButton(title: l10n.string(.bundleRemove), kind: .hyperlink, size: .small, leadingIcon: .x,
                         isLoading: isRemoving, action: remove)
                .disabled(isDisabled)
                .accessibilityLabel("\(l10n.string(.bundleRemove)), \(item.title)")
                .accessibilityIdentifier("bundle.remove")
        }
        .padding(TaleedSpacing.s12)
        .taleedCard()
    }
}
