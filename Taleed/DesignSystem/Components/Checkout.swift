import SwiftUI

/// Checkout item (design-system §4.3): thumbnail, "Item", name and price.
struct CheckoutItem: View {
    let caption: String
    let title: String
    let price: Int
    let media: ProductMedia

    var body: some View {
        HStack(spacing: TaleedSpacing.s12) {
            ProductMediaView(media: media)
                .frame(width: TaleedSize.CheckoutThumb.width, height: TaleedSize.CheckoutThumb.height)
                .clipShape(RoundedRectangle(cornerRadius: TaleedSize.CheckoutThumb.radius, style: .continuous))
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                Text(caption)
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.textSecondary)
                Text(verbatim: title)
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

/// Delivery option card (design-system §4.4): icon, name, description and a radio. The whole card selects.
struct DeliveryOption: View {
    let icon: TaleedIcon
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: TaleedSpacing.s8) {
                TaleedIconView(icon, size: 24, color: isSelected ? TaleedColor.brandPrimary : TaleedColor.textSecondary)
                VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                    Text(title)
                        .taleedFont(TaleedFont.buttonMedium)
                        .foregroundStyle(TaleedColor.textPrimary)
                    Text(subtitle)
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RadioIndicator(isSelected: isSelected)
            }
            .padding(TaleedSpacing.s16)
            .taleedCard(fill: isSelected ? TaleedColor.blue50 : TaleedColor.surfacePrimary,
                        border: isSelected ? TaleedColor.brandPrimary : TaleedColor.borderSubtle)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A line of the order summary. A nil amount shows "—" (Pending).
struct OrderSummaryLine: Identifiable {
    let id: String
    var label: String
    var amount: Int?
    /// Adds the info icon after the label (Platform & Service Fee) that opens an explanation.
    var onInfo: (() -> Void)?
}

/// Order summary (design-system §4.5).
struct OrderSummary: View {
    let title: String
    let lines: [OrderSummaryLine]
    let totalLabel: String
    let total: Int?
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
            Text(title)
                .taleedFont(TaleedFont.headline)
                .foregroundStyle(TaleedColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(lines) { line in
                HStack(spacing: TaleedSpacing.s8) {
                    HStack(spacing: TaleedSpacing.s4) {
                        Text(line.label)
                            .taleedFont(TaleedFont.bodyRegular)
                            .foregroundStyle(TaleedColor.textSecondary)
                        if let onInfo = line.onInfo {
                            Button(action: onInfo) {
                                TaleedIconView(.info, size: 16, color: TaleedColor.textSecondary).minimumHitArea()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(DesignSystemStrings.string(.a11yMoreInfo, locale: locale))
                        }
                    }
                    Spacer(minLength: TaleedSpacing.s8)
                    AmountText(amount: line.amount)
                }
            }
            Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1)
            HStack {
                Text(totalLabel)
                    .taleedFont(TaleedFont.buttonMedium)
                    .foregroundStyle(TaleedColor.textPrimary)
                Spacer(minLength: TaleedSpacing.s8)
                AmountText(amount: total, style: TaleedFont.buttonMedium)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(TaleedSpacing.s16)
        .taleedCard()
    }
}

/// Promo code (design-system §4.6): a field and "Apply" (Tertiary Large), enabled once there is text.
struct PromoCodeField: View {
    let label: String
    @Binding var code: String
    var placeholder: String
    let applyTitle: String
    var error: String?
    var isApplying = false
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
            FieldLabel(text: label, color: error == nil ? TaleedColor.textPrimary : TaleedColor.feedbackError)
            // Row gap 8, centred (§4.6): the 44 field centres on the 48 button; the error sits under
            // the row so it never moves the button.
            HStack(alignment: .center, spacing: TaleedSpacing.s8) {
                TaleedTextField(label: nil, text: $code, placeholder: placeholder, error: error, showsMessage: false)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityLabel(label)
                TaleedButton(title: applyTitle, kind: .tertiary, size: .large, isLoading: isApplying, minWidth: 96,
                             action: onApply)
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error {
                FieldHelper(text: error, color: TaleedColor.feedbackError)
            }
        }
    }
}
