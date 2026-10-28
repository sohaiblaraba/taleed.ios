import SwiftUI

/// Checkout item (design-system §4.3): thumbnail 56 x 72, "Item", name and price.
struct CheckoutItem: View {
    let title: String
    let price: Int
    let media: ProductMedia
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: TaleedSpacing.s12) {
            ProductMediaView(media: media)
                .frame(width: TaleedSize.checkoutThumbWidth, height: TaleedSize.checkoutThumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: TaleedSize.checkoutThumbRadius, style: .continuous))
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                Text(DesignSystemStrings.string(.checkoutItemLabel, locale: locale))
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
                Text(verbatim: title.isolatedByContent)
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textPrimary)
                PriceText(amount: price, style: TaleedFont.buttonMedium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(TaleedSpacing.s16)
        .taleedCard()
        .accessibilityElement(children: .combine)
    }
}

/// Delivery option card (design-system §4.4): icon, name and supporting text, radio, gap 12. Selected:
/// `blue/50` fill and a brand border. Single choice; the whole card is the tap target. `fee`: the
/// delivery price at the end of the name row, as the website shows both kinds side by side; from
/// accessibility text sizes on, on its own line under the name, so the name keeps the full width.
struct DeliveryOption: View {
    let icon: TaleedIcon
    let title: String
    let description: String
    let selected: Bool
    var fee: String?
    let onSelect: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: TaleedSpacing.s12) {
                TaleedIconView(icon, size: 24, color: selected ? TaleedColor.brandPrimary : TaleedColor.textSecondary)
                VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                    if dynamicTypeSize.isAccessibilitySize {
                        titleText
                        if let fee { feeText(fee) }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: TaleedSpacing.s8) {
                            titleText
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let fee {
                                feeText(fee)
                                    .multilineTextAlignment(.trailing)
                                    .layoutPriority(1)
                            }
                        }
                    }
                    Text(description)
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textSecondarySmall)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RadioIndicator(isSelected: selected)
            }
            .padding(TaleedSpacing.s16)
            .taleedCard(fill: selected ? TaleedColor.brandTint : TaleedColor.surfacePrimary,
                        border: selected ? TaleedColor.brandPrimary : TaleedColor.borderSubtle)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var titleText: some View {
        Text(title)
            .taleedFont(TaleedFont.buttonMedium)
            .foregroundStyle(TaleedColor.textPrimary)
    }

    private func feeText(_ fee: String) -> some View {
        Text(fee)
            .taleedFont(TaleedFont.buttonMedium)
            .foregroundStyle(TaleedColor.textPrimary)
            .monospacedDigit()
    }
}

/// One amount row of the order summary. A nil amount shows "—" (not set yet: Pending). `onInfo` adds
/// the info icon that explains the line (the platform and service fee).
struct OrderSummaryLine: Identifiable {
    let id: String
    var label: String
    var amount: Int?
    var onInfo: (() -> Void)?
    /// A value that is not an amount ("dès 400 DA", "calculée au paiement"); shown instead of `amount`.
    var valueText: String?
    /// A small tag after the label: a promo code, "auto" for a voucher.
    var tag: String?
    /// A discount (promo, voucher, wallet): the amount in the brand colour, as on the website.
    var isDiscount = false

    init(id: String, label: String, amount: Int?, onInfo: (() -> Void)? = nil, valueText: String? = nil,
         tag: String? = nil, isDiscount: Bool = false) {
        self.id = id
        self.label = label
        self.amount = amount
        self.onInfo = onInfo
        self.valueText = valueText
        self.tag = tag
        self.isDiscount = isDiscount
    }
}

/// Order summary (design-system §4.5): "Summary", amount rows, divider, "Total to pay". "—" while
/// pending. `title` defaults to the design-system copy (`order_summary_title`).
struct OrderSummary: View {
    var title: String?
    let lines: [OrderSummaryLine]
    let totalLabel: String
    let total: Int?
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
            Text(title ?? DesignSystemStrings.string(.orderSummaryTitle, locale: locale))
                .taleedFont(TaleedFont.headline)
                .foregroundStyle(TaleedColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(lines) { line in
                row(line, style: TaleedFont.bodyRegular, labelColor: TaleedColor.textSecondarySmall)
            }
            Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1).accessibilityHidden(true)
            row(OrderSummaryLine(id: "total", label: totalLabel, amount: total), style: TaleedFont.buttonMedium,
                labelColor: TaleedColor.textPrimary)
        }
        .padding(TaleedSpacing.s16)
        .taleedCard()
    }

    private func row(_ line: OrderSummaryLine, style: TaleedTextStyle, labelColor: Color) -> some View {
        HStack(spacing: TaleedSpacing.s8) {
            // The label takes what is left after the info button, so a label that wraps at large text
            // never pushes the button out (the explanation stays reachable at every size).
            HStack(spacing: TaleedSpacing.s4) {
                Text(line.label)
                    .taleedFont(style)
                    .foregroundStyle(labelColor)
                    .fixedSize(horizontal: false, vertical: true)
                if let tag = line.tag {
                    TaleedBadge(title: tag)
                }
                if let onInfo = line.onInfo {
                    Button(action: onInfo) {
                        TaleedIconView(.info, size: 16, color: TaleedColor.textSecondary).minimumHitArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DesignSystemStrings.string(.orderSummaryFeeInfo, locale: locale))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if let valueText = line.valueText {
                    Text(valueText)
                        .taleedFont(style)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .multilineTextAlignment(.trailing)
                } else {
                    AmountText(amount: line.amount, style: style,
                               color: line.isDiscount ? TaleedColor.brandPrimary : TaleedColor.textPrimary)
                }
            }
            .layoutPriority(1)
        }
        .accessibilityElement(children: line.onInfo == nil ? .combine : .contain)
    }
}

/// Promo code (design-system §4.6): label, then a row (gap 8, centred) of a field and a Tertiary
/// Large "Apply" that is enabled once there is text. `error` draws the field's Error state, with the
/// message under the row. When the placeholder would not fit next to "Apply" (large text), "Apply"
/// goes under the field at full width (Android's PromoCodeField).
struct PromoCodeField: View {
    @Binding var code: String
    var error: String?
    var isApplying = false
    /// The label as a section eyebrow, as the other sections of a form made of eyebrowed groups (checkout).
    var labelIsEyebrow = false
    let onApply: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let label = DesignSystemStrings.string(.promoCodeLabel, locale: locale)
        let placeholder = DesignSystemStrings.string(.promoCodePlaceholder, locale: locale)
        let fieldWidth = TaleedFont.bodyRegular.width(of: placeholder, sizeCategory: UIContentSizeCategory(dynamicTypeSize))
            + 2 * TaleedSize.inputPaddingX
        VStack(alignment: .leading, spacing: TaleedSize.inputLabelGap) {
            if labelIsEyebrow {
                Eyebrow(text: label)
                    .accessibilityAddTraits(.isHeader)
            } else {
                FieldLabel(text: label, color: error == nil ? TaleedColor.textPrimary : TaleedColor.feedbackError)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: TaleedSpacing.s8) {
                    field(placeholder: placeholder, label: label)
                        .frame(minWidth: 0, idealWidth: fieldWidth, maxWidth: .infinity)
                    apply(fullWidth: false)
                }
                VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                    field(placeholder: placeholder, label: label)
                    apply(fullWidth: true)
                }
            }
            // The field announces a new error itself.
            if let error {
                FieldHelper(text: error, color: TaleedColor.feedbackError)
            }
        }
    }

    private func field(placeholder: String, label: String) -> some View {
        TaleedTextField(label: nil, text: $code, placeholder: placeholder, error: error, showsClearButton: false,
                        showsMessage: false)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .accessibilityLabel(label)
    }

    private func apply(fullWidth: Bool) -> some View {
        TaleedButton(title: DesignSystemStrings.string(.commonApply, locale: locale), kind: .tertiary, size: .large,
                     isLoading: isApplying, isFullWidth: fullWidth, action: onApply)
            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}
