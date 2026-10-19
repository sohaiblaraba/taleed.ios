import SwiftUI

// The offer and bundle cards of a conversation (slice C, §7 G9).

/// A card on its sender's side: the member's on the trailing side.
struct ChatSideRow<Content: View>: View {
    let isMine: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            if isMine { Spacer(minLength: 0) }
            content
            if !isMine { Spacer(minLength: 0) }
        }
    }
}

/// A bundle item line on the offer and bundle cards: thumbnail, title and price; opens the listing.
struct ChatBundleItemRow: View {
    let item: ChatBundleItem
    let openListing: (String) -> Void

    var body: some View {
        Button { openListing(item.listingId) } label: {
            HStack(spacing: TaleedSpacing.s8) {
                RemoteImage(url: item.imageURL)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.s, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: item.title.isolatedByContent)
                        .taleedFont(TaleedFont.caption)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .lineLimit(1)
                    PriceText(amount: item.price, style: TaleedFont.meta, color: TaleedColor.textBody)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: TaleedSize.touchTargetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }
}

/// The frame of the offer and bundle cards: 264 wide, `radius.l`, the member's on `brandSoft`.
struct ChatCard<Content: View>: View {
    let isMine: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) { content }
            .padding(TaleedSpacing.s12)
            .frame(width: 264, alignment: .leading)
            .background(isMine ? TaleedColor.brandSoft : TaleedColor.surfacePrimary, in: ChatBubbleStyle.shape)
            .overlay(ChatBubbleStyle.shape.strokeBorder(isMine ? TaleedColor.brandSoftBorder : TaleedColor.borderSubtle))
    }
}

/// An `OFFER` card (slice C, §7 G9): the eyebrow, the status, a bundle's items, the amount and, while it
/// waits, when it expires. Its buttons (accept, decline, counter, withdraw, pay) are the offers group's
/// (G10); they follow the offer's `can…` flags.
struct ChatOfferCard: View {
    let offer: ChatOffer
    let isMine: Bool
    var now = Date()
    let openListing: (String) -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        let status = offer.displayStatus(at: now)
        ChatCard(isMine: isMine) {
            HStack(alignment: .center, spacing: TaleedSpacing.s8) {
                HStack(spacing: TaleedSpacing.s4) {
                    TaleedIconView(offer.bundle == nil ? .money : .storefront, size: 14, color: TaleedColor.textBody)
                    Text(eyebrow.uppercased(with: l10n.language.locale))
                        .taleedFont(TaleedFont.eyebrow)
                        .foregroundStyle(TaleedColor.textBody)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                TaleedBadge(title: l10n.string(ChatText.offerStatusKey(status)), tone: ChatText.offerStatusTone(status))
                    .fixedSize()
            }
            if let bundle = offer.bundle {
                Divider()
                ForEach(bundle.items) { ChatBundleItemRow(item: $0, openListing: openListing) }
                Divider()
            }
            PriceText(amount: offer.amount, style: TaleedFont.priceDetail)
            if status == .pending {
                let relative = RelativeTimeText.string(for: offer.expiresAt, now: now, locale: l10n.language.formattingLocale)
                Text(l10n.format(.offersExpiresIn, relative))
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.textBody)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var eyebrow: String {
        switch ChatText.offerEyebrow(offer) {
        case let .bundle(count): l10n.format(.offersBundleOffer, count)
        case .buyer: l10n.string(.offersMakeOffer)
        case .seller: l10n.string(.offersSellerOffer)
        }
    }
}

/// A `BUNDLE` card: the bundle the buyer asked about, its items and their total.
struct ChatBundleCard: View {
    let bundle: ChatBundle
    let isMine: Bool
    let openListing: (String) -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ChatCard(isMine: isMine) {
            HStack(spacing: TaleedSpacing.s4) {
                TaleedIconView(.storefront, size: 14, color: TaleedColor.textBody)
                Text(l10n.format(.chatBundleQuestion, bundle.items.count).uppercased(with: l10n.language.locale))
                    .taleedFont(TaleedFont.eyebrow)
                    .foregroundStyle(TaleedColor.textBody)
            }
            Divider()
            ForEach(bundle.items) { ChatBundleItemRow(item: $0, openListing: openListing) }
            Divider()
            PriceText(amount: bundle.itemsTotal, style: TaleedFont.sectionTitle)
        }
        .accessibilityElement(children: .contain)
    }
}
