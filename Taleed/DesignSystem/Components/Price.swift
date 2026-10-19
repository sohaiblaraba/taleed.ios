import SwiftUI

/// A price in dinars with the DA suffix and tabular digits (design-system §3.2, decision D-5).
///
/// A price is never cut (D-9, §7): the line may break only between the amount and the currency,
/// never inside the amount or inside "DA" / "د.ج.". When the amount alone is still wider than the
/// room (very large text in a narrow column), the size steps down until it fits. Android's
/// `PriceText` does the same.
struct PriceText: View {
    let amount: Int
    var style: TaleedTextStyle = TaleedFont.priceCard
    var color: Color = TaleedColor.textPrimary
    @Environment(\.locale) private var locale

    var body: some View {
        WordFittingText(text: Self.breakableBeforeCurrency(PriceFormatter.format(amount, locale: locale)),
                        style: style, monospacedDigits: true)
            .foregroundStyle(color)
    }

    /// The formatter joins the amount and the currency with a no-break space. Swapping that last one
    /// for a normal space lets the line break there only: the digit groups (narrow no-break spaces or
    /// ".") and the currency stay whole.
    static func breakableBeforeCurrency(_ price: String) -> String {
        guard let index = price.lastIndex(of: "\u{00A0}") else { return price }
        var result = price
        result.replaceSubrange(index...index, with: " ")
        return result
    }
}

/// An amount, or "—" while it is not set yet (order summary: Pending), read as "Not set yet".
struct AmountText: View {
    let amount: Int?
    var style: TaleedTextStyle = TaleedFont.bodyRegular
    var color: Color = TaleedColor.textPrimary
    @Environment(\.locale) private var locale

    var body: some View {
        if let amount {
            PriceText(amount: amount, style: style, color: color)
        } else {
            Text(verbatim: "—")
                .taleedFont(style)
                .foregroundStyle(color)
                .accessibilityLabel(DesignSystemStrings.string(.commonNotSet, locale: locale))
        }
    }
}

/// One metadata line under a detail price: icon 17 and a 13/400 text.
struct PriceMeta: Identifiable {
    let icon: TaleedIcon
    let text: String
    var id: String { icon.rawValue + text }
}

/// Price treatment of the detail spec (design-system §3.2): price, optional "Negotiable price" note,
/// then the metadata list (location, published, delivery, views). The note is `feedback/success`
/// #139A6C, as on Android, instead of Figma's `brand/accent` (1.7:1 on white). It is still 3.58:1,
/// under 4.5:1 for 13 pt text: a darker shared token is Saad's call.
struct PriceDetail: View {
    let amount: Int
    var meta: [PriceMeta] = []
    var negotiableLabel: String?

    private static let metaStyle = TaleedTextStyle(size: 13, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                   relativeTo: .footnote)

    var body: some View {
        // Price and note 4 apart, then 14 between every line (as Android's PriceDetail).
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                PriceText(amount: amount, style: TaleedFont.priceDetail)
                if let negotiableLabel {
                    Text(negotiableLabel)
                        .taleedFont(Self.metaStyle)
                        .foregroundStyle(TaleedColor.feedbackSuccess)
                }
            }
            ForEach(meta) { item in
                HStack(spacing: 10) {
                    TaleedIconView(item.icon, size: 17, color: TaleedColor.textSecondary)
                    Text(item.text)
                        .taleedFont(Self.metaStyle)
                        .foregroundStyle(TaleedColor.textBody)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
