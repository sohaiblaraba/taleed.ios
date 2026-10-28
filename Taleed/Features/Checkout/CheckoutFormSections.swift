import SwiftUI

// The lower half of the checkout form: the server's summary, the promo code, the payment method and the
// button (screens.md §7 G11), then the pickers.
extension CheckoutFormView {
    // MARK: Summary

    @ViewBuilder
    var summary: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            if let error = model.quoteError {
                InlineAlert(kind: .error, title: l10n.message(for: error), actionTitle: l10n.string(.commonRetry)) {
                    Task { await model.retryQuote() }
                }
                .accessibilityIdentifier("checkout.quoteError")
            }
            OrderSummary(title: l10n.string(.checkoutSummary), lines: summaryLines,
                         totalLabel: l10n.string(.checkoutTotal),
                         total: model.isStale ? nil : model.pricing?.amounts.amountDue)
                .opacity(model.isQuoting ? 0.6 : 1)
                .overlay(alignment: .topTrailing) {
                    if model.isQuoting {
                        ProgressView()
                            .tint(TaleedColor.brandPrimary)
                            .padding(TaleedSpacing.s16)
                            .accessibilityLabel(l10n.string(.commonLoading))
                    }
                }
                .popover(isPresented: $showsFeeInfo) {
                    Text(l10n.string(.checkoutProtectionTooltip))
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(TaleedSpacing.s16)
                        .frame(idealWidth: 280)
                        .presentationCompactAdaptation(.popover)
                        .appLanguage(l10n.language)
                }
                .accessibilityIdentifier("checkout.summary")
        }
    }

    /// The quote's amounts line by line (screens.md §0.2); before a wilaya, the goods and their fee with
    /// "—" for the rest (Figma: Order summary / Pending).
    private var summaryLines: [OrderSummaryLine] {
        let showFeeInfo = { showsFeeInfo = true }
        guard let pricing = model.pricing else {
            let preview = model.preview
            let itemLabel = preview?.isBundle == true
                ? l10n.format(.checkoutBundleItems, preview?.items.count ?? 0) : l10n.string(.checkoutItemLabel)
            return [
                OrderSummaryLine(id: "item", label: itemLabel, amount: preview?.itemPrice),
                OrderSummaryLine(id: "fee", label: l10n.string(.checkoutProtectionFee), amount: preview?.protectionFee,
                                 onInfo: showFeeInfo),
                OrderSummaryLine(id: "shipping", label: l10n.string(.checkoutShippingFee), amount: nil),
            ]
        }
        return CheckoutSummary.rows(for: pricing).map { row in
            switch row.kind {
            case let .item(bundleCount):
                OrderSummaryLine(id: "item", label: bundleCount.map { l10n.format(.checkoutBundleItems, $0) }
                    ?? l10n.string(.checkoutItemLabel), amount: row.amount)
            case .protectionFee:
                OrderSummaryLine(id: "fee", label: l10n.string(.checkoutProtectionFee), amount: row.amount, onInfo: showFeeInfo)
            case let .shipping(estimate):
                OrderSummaryLine(id: "shipping", label: l10n.string(.checkoutShippingFee), amount: row.amount,
                                 valueText: estimate ? feeText(row.amount, exact: false) : nil)
            case let .promo(kind, code):
                OrderSummaryLine(id: "promo", label: l10n.string(promoLabel(kind)), amount: row.amount, tag: code, isDiscount: true)
            case .voucher:
                OrderSummaryLine(id: "voucher", label: l10n.string(.checkoutVoucher), amount: row.amount,
                                 tag: l10n.string(.checkoutVoucherAuto), isDiscount: true)
            }
        }
    }

    private func promoLabel(_ kind: PromoKindValue) -> L10nKey {
        switch kind {
        case .freeDelivery: .checkoutPromoFreeDelivery
        case .freeFees: .checkoutPromoFreeFees
        case .percent, .fixed, .unknown: .checkoutDiscount
        }
    }

    // MARK: Promo code

    @ViewBuilder
    var promo: some View {
        if let code = model.form.appliedPromoCode {
            VStack(alignment: .leading, spacing: TaleedSize.inputLabelGap) {
                // An eyebrow, as the form's other sections.
                Eyebrow(text: l10n.string(.promoCodeLabel))
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: TaleedSpacing.s8) {
                    TaleedBadge(title: code, icon: .check)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TaleedButton(title: l10n.string(.checkoutPromoRemove), kind: .hyperlink, size: .small, leadingIcon: .x) {
                        Task { await model.removePromo() }
                    }
                    .disabled(model.isPlacing)
                    .accessibilityIdentifier("checkout.promoRemove")
                }
            }
            .accessibilityIdentifier("checkout.promoApplied")
        } else {
            PromoCodeField(code: promoBinding, error: promoErrorText, isApplying: model.isApplyingPromo, labelIsEyebrow: true) {
                Task { await model.applyPromo() }
            }
            .disabled(model.isPlacing)
            .accessibilityIdentifier("checkout.promo")
        }
    }

    private var promoBinding: Binding<String> {
        Binding(get: { model.form.promoInput }, set: {
            // No case change while typing: the server ignores case and spaces.
            model.form.promoInput = $0.prefix(utf16Units: CheckoutLimits.promoCodeMax)
            model.promoInputChanged()
        })
    }

    private var promoErrorText: String? {
        switch model.promoError {
        case let .server(message): message
        case .invalid: l10n.string(.checkoutPromoInvalid)
        case nil: nil
        }
    }

    // MARK: Payment method

    @ViewBuilder
    var paymentMethods: some View {
        if let pricing = model.pricing, CheckoutSummary.showsPaymentMethods(pricing) {
            let selected = model.form.paymentMethod ?? pricing.paymentMethod
            VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                Eyebrow(text: l10n.string(.checkoutPaymentMethod))
                    .accessibilityAddTraits(.isHeader)
                ForEach(pricing.paymentMethods) { method in
                    DeliveryOption(icon: method.isCashOnDelivery ? .money : .lockKey, title: method.label, description: method.hint,
                                   selected: selected == method.value) {
                        Task { await model.selectPaymentMethod(method.value) }
                    }
                    .disabled(model.isPlacing)
                    .accessibilityIdentifier("checkout.method.\(method.value)")
                }
            }
        }
        if let pricing = model.pricing, pricing.isCashOnDelivery, pricing.amounts.amountDue > 0 {
            InlineAlert(kind: .info, title: l10n.string(.checkoutCodNotice))
                .accessibilityIdentifier("checkout.codNotice")
        }
    }

    // MARK: Button

    var payButton: some View {
        let action = model.displayedAction
        return VStack(spacing: TaleedSpacing.s8) {
            TaleedButton(title: buttonTitle(action), kind: .secondary, size: .large, isFullWidth: true, action: pay)
                .disabled(!model.canPlaceOrder || isInBrowser)
                .accessibilityIdentifier("checkout.pay")
            // Nothing left to pay: no hint under the button, as the website.
            if let hint = buttonHint(action) {
                HStack(alignment: .firstTextBaseline, spacing: TaleedSpacing.s4) {
                    TaleedIconView(action.isCashOnDelivery ? .money : .lockKey, size: 14, color: TaleedColor.textSecondary)
                        .accessibilityHidden(true)
                    Text(hint)
                        .taleedFont(TaleedFont.meta)
                        .foregroundStyle(TaleedColor.textSecondarySmall)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func buttonTitle(_ action: CheckoutAction) -> String {
        if model.isPlacing || isInBrowser { return l10n.string(.checkoutProcessing) }
        let format = { (amount: Int) in PriceFormatter.format(amount, language: l10n.language) }
        return switch action {
        case .pending: l10n.format(.checkoutPayCta, "…")
        case .confirm: l10n.string(.checkoutConfirmCta)
        case let .cashOnDelivery(amount): l10n.format(.checkoutCodCta, format(amount))
        case let .pay(amount): l10n.format(.checkoutPayCta, format(amount))
        }
    }

    private func buttonHint(_ action: CheckoutAction) -> String? {
        switch action {
        case .confirm: nil
        case .cashOnDelivery: l10n.string(.checkoutCodHint)
        case .pending, .pay: l10n.string(.checkoutPayHint)
        }
    }

    // MARK: Pickers

    var shortPickerBinding: Binding<Bool> {
        Binding(get: { picker.map { !$0.isLong } ?? false }, set: { if !$0, picker?.isLong == false { picker = nil } })
    }

    var longPickerBinding: Binding<CheckoutPicker?> {
        Binding(get: { picker?.isLong == true ? picker : nil }, set: { if $0 == nil, picker?.isLong == true { picker = nil } })
    }

    @ViewBuilder
    var shortPicker: some View {
        switch picker {
        case .savedAddress:
            SellChoiceSheet(
                title: l10n.string(.appCheckoutSavedAddress),
                options: model.savedAddresses.map {
                    FilterOption(value: $0.id, title: "\($0.recipientName) · \(CheckoutRules.addressTitle($0))")
                } + [FilterOption(value: Self.newAddressValue, title: l10n.string(.appCheckoutNewAddress))],
                selection: model.selectedAddressId ?? Self.newAddressValue
            ) { value in
                Task { await model.selectSavedAddress(value == Self.newAddressValue ? nil : value) }
            }
        case .stopdesk:
            SellChoiceSheet(title: l10n.string(.checkoutStopdesk),
                            options: model.desksForCommune.map { FilterOption(value: String($0.id), title: deskTitle($0)) },
                            selection: model.form.stopdeskId.map(String.init)) { value in
                if let id = Int(value) { Task { await model.selectStopdesk(id) } }
            }
        case .wilaya, .commune, nil:
            EmptyView()
        }
    }

    @ViewBuilder
    func longPicker(_ picker: CheckoutPicker) -> some View {
        switch picker {
        case .wilaya:
            SellSearchableChoiceSheet(
                title: l10n.string(.checkoutWilaya),
                options: (catalog.catalog?.wilayas ?? []).map {
                    FilterOption(value: String($0.id), title: "\($0.id) — \($0.name)", searchText: String($0.id))
                },
                selection: model.form.wilayaId.map(String.init)
            ) { value in
                if let id = Int(value) { Task { await model.selectWilaya(id) } }
            }
        case .commune:
            SellSearchableChoiceSheet(title: l10n.string(.checkoutCommune),
                                      options: model.communes.map { FilterOption(value: String($0.id), title: $0.name) },
                                      selection: model.form.communeId.map(String.init)) { value in
                if let id = Int(value) { Task { await model.selectCommune(id) } }
            }
        case .savedAddress, .stopdesk:
            EmptyView()
        }
    }

    private static let newAddressValue = "new"
}
