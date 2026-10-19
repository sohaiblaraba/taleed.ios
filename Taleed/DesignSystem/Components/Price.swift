import SwiftUI

/// A price in dinars with the DA suffix and tabular digits (design-system §3.2, decision D-5).
struct PriceText: View {
    let amount: Int
    var style: TaleedTextStyle = TaleedFont.priceCard
    var color: Color = TaleedColor.textPrimary
    @Environment(\.locale) private var locale

    var body: some View {
        Text(verbatim: PriceFormatter.format(amount, locale: locale))
            .taleedFont(style)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// An amount or "—" while it is unknown (order summary).
struct AmountText: View {
    let amount: Int?
    var style: TaleedTextStyle = TaleedFont.bodyRegular
    var color: Color = TaleedColor.textPrimary

    var body: some View {
        if let amount {
            PriceText(amount: amount, style: style, color: color)
        } else {
            Text(verbatim: "—")
                .taleedFont(style)
                .foregroundStyle(color)
        }
    }
}

/// The price block of the price-treatment specimen: price, "Negotiable price" and a metadata list
/// (location, published, delivery, views), each an icon and a line of text.
struct PriceDetailBlock: View {
    struct Meta: Identifiable {
        let icon: TaleedIcon
        let text: String
        var id: String { icon.rawValue + text }
    }

    let amount: Int
    var negotiableLabel: String?
    var meta: [Meta] = []

    private static let metaStyle = TaleedTextStyle(size: 13, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                   relativeTo: .footnote)

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            PriceText(amount: amount, style: TaleedFont.priceDetail)
            if let negotiableLabel {
                Text(negotiableLabel)
                    .taleedFont(Self.metaStyle)
                    .foregroundStyle(TaleedColor.mint600)
            }
            VStack(alignment: .leading, spacing: 14) {
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
            .padding(.top, TaleedSpacing.s4)
        }
    }
}
