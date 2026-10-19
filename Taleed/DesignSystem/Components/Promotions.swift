import SwiftUI

/// Home hero banner (wireframe Home #4): photo with a 40 % overlay (the title's only contrast aid), a cut-out that pops 24 pt above
/// the card, a two-line title, a mint CTA and a dismiss button. Photos do not mirror.
struct HeroBanner: View {
    let title: String
    let ctaLabel: String
    var background: Image = Image(taleed: .homeHeroBackground)
    var foreground: Image? = Image(taleed: .homeHeroForeground)
    let onCta: () -> Void
    var onDismiss: (() -> Void)?
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection

    private let popOut = TaleedSize.heroBannerForegroundOverflowTop

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TaleedSize.heroBannerRadius, style: .continuous)
        content
            .frame(maxWidth: .infinity, minHeight: TaleedSize.heroBannerHeight, alignment: .leading)
            .background {
                ZStack {
                    Color.clear
                        .overlay { background.resizable().scaledToFill() }
                        .overlay(TaleedColor.heroOverlay)
                        .clipShape(shape)
                    // The cut-out's own frame is the banner plus `popOut`, with the same corner radius,
                    // so it shows above the card's top edge, behind the copy.
                    if let foreground {
                        GeometryReader { proxy in
                            Color.clear
                                .overlay(alignment: .bottom) { foreground.resizable().scaledToFill() }
                                .frame(width: proxy.size.width, height: proxy.size.height + popOut)
                                .clipShape(shape)
                                .offset(y: -popOut)
                        }
                    }
                }
                .accessibilityHidden(true)
            }
            .overlay(alignment: .topTrailing) {
                if let onDismiss {
                    Button(action: onDismiss) {
                        TaleedIconView(.x, size: 14, color: TaleedColor.textInverse)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(TaleedColor.imageRemoveScrim))
                            .minimumHitArea()
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .accessibilityLabel(DesignSystemStrings.string(.commonDismiss, locale: locale))
                }
            }
            .padding(.top, popOut)
            // The artwork does not mirror, so the copy stays on the photo's empty side in every
            // language; the copy itself keeps the reading direction.
            .environment(\.layoutDirection, .leftToRight)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
            Text(title)
                .taleedFont(TaleedFont.headline)
                .foregroundStyle(TaleedColor.textInverse)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            TaleedButton(title: ctaLabel, kind: .secondary, size: .small, isFullWidth: true, action: onCta)
        }
        .environment(\.layoutDirection, layoutDirection)
        .frame(width: 160, alignment: .leading)
        .frame(minHeight: 112)
        .padding(.vertical, TaleedSize.heroBannerPaddingY)
        .padding(.horizontal, TaleedSize.heroBannerPaddingX)
    }
}

/// Trust strip (Home and Item Detail): protected pay, delivery, trusted sellers.
struct TrustStrip: View {
    enum Style: Sendable {
        /// Home: inside the margins, radius 16.
        case card
        /// Item Detail: full bleed, no radius.
        case fullBleed
    }

    var style: Style = .card
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: TaleedSpacing.s8) {
            item(.shieldCheck, .trustProtectedPay)
            divider
            item(.truck, .trustDelivery)
            divider
            item(.sealCheck, .trustTrustedSellers)
        }
        .padding(TaleedSpacing.s12)
        .frame(minHeight: 72)
        .background(TaleedColor.blue50, in: RoundedRectangle(cornerRadius: style == .card ? 16 : 0, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(TaleedColor.blue200).frame(width: 1, height: 48).accessibilityHidden(true)
    }

    private func item(_ icon: TaleedIcon, _ key: L10nKey) -> some View {
        VStack(spacing: TaleedSpacing.s4) {
            TaleedIconView(icon, size: 24, color: TaleedColor.blue500)
            Text(DesignSystemStrings.string(key, locale: locale))
                .taleedFont(TaleedFont.tagLabel)
                .foregroundStyle(TaleedColor.blue700)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Promotions") {
    VStack(spacing: 24) {
        HeroBanner(title: "Give your things a second life.", ctaLabel: "Browse near you", onCta: {}, onDismiss: {})
        TrustStrip()
    }
    .padding()
}
