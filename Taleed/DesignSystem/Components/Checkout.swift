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
                    .foregroundStyle(TaleedColor.textSecondary)
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
/// `blue/50` fill and a brand border. Single choice; the whole card is the tap target.
struct DeliveryOption: View {
    let icon: TaleedIcon
    let title: String
    let description: String
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: TaleedSpacing.s12) {
                TaleedIconView(icon, size: 24, color: selected ? TaleedColor.brandPrimary : TaleedColor.textSecondary)
                VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                    Text(title)
                        .taleedFont(TaleedFont.buttonMedium)
                        .foregroundStyle(TaleedColor.textPrimary)
                    Text(description)
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RadioIndicator(isSelected: selected)
            }
            .padding(TaleedSpacing.s16)
            .taleedCard(fill: selected ? TaleedColor.blue50 : TaleedColor.surfacePrimary,
                        border: selected ? TaleedColor.brandPrimary : TaleedColor.borderSubtle)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// One amount row of the order summary. A nil amount shows "—" (not set yet: Pending). `onInfo` adds
/// the info icon that explains the line (the platform and service fee).
struct OrderSummaryLine: Identifiable {
    let id: String
    var label: String
    var amount: Int?
    var onInfo: (() -> Void)?
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
                row(line.label, amount: line.amount, style: TaleedFont.bodyRegular, labelColor: TaleedColor.textSecondary,
                    onInfo: line.onInfo)
            }
            Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1).accessibilityHidden(true)
            row(totalLabel, amount: total, style: TaleedFont.buttonMedium, labelColor: TaleedColor.textPrimary, onInfo: nil)
        }
        .padding(TaleedSpacing.s16)
        .taleedCard()
    }

    private func row(_ label: String, amount: Int?, style: TaleedTextStyle, labelColor: Color,
                     onInfo: (() -> Void)?) -> some View {
        HStack(spacing: TaleedSpacing.s8) {
            // The label takes what is left after the info button, so a label that wraps at large text
            // never pushes the button out (the explanation stays reachable at every size).
            HStack(spacing: TaleedSpacing.s4) {
                Text(label)
                    .taleedFont(style)
                    .foregroundStyle(labelColor)
                    .fixedSize(horizontal: false, vertical: true)
                if let onInfo {
                    Button(action: onInfo) {
                        TaleedIconView(.info, size: 16, color: TaleedColor.textSecondary).minimumHitArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DesignSystemStrings.string(.orderSummaryFeeInfo, locale: locale))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AmountText(amount: amount, style: style)
                .layoutPriority(1)
        }
        .accessibilityElement(children: onInfo == nil ? .combine : .contain)
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
    let onApply: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let label = DesignSystemStrings.string(.promoCodeLabel, locale: locale)
        let placeholder = DesignSystemStrings.string(.promoCodePlaceholder, locale: locale)
        let fieldWidth = TaleedFont.bodyRegular.width(of: placeholder, sizeCategory: UIContentSizeCategory(dynamicTypeSize))
            + 2 * TaleedSize.inputPaddingX
        VStack(alignment: .leading, spacing: TaleedSize.inputLabelGap) {
            FieldLabel(text: label, color: error == nil ? TaleedColor.textPrimary : TaleedColor.feedbackError)
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
