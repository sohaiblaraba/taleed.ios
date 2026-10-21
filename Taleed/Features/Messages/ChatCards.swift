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

/// An offer's status as one pill everywhere (cards, the pinned offer and its row): pending in the brand
/// tone, accepted in the success tone, closed neutral. On a `brandSoft` surface (the member's own card,
/// the pinned offer) the pill keeps an outline so "En attente" still reads as a pill.
struct OfferStatusBadge: View {
    let status: ChatOfferStatus
    var isOnTint = false
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        TaleedBadge(title: l10n.string(ChatText.offerStatusKey(status)), tone: ChatText.offerStatusTone(status), isOnTint: isOnTint)
            .fixedSize()
            .accessibilityIdentifier("offer.status")
    }
}

/// An offer's eyebrow ("OFFRE SUR UN LOT · 3 ARTICLES", "VOTRE OFFRE", "OFFRE", "OFFRE DU VENDEUR") with its
/// icon, on a row of its own so that it never has to share the width with the status.
struct OfferEyebrow: View {
    let offer: ChatOffer
    /// One line at its full width (to test whether it fits next to the status).
    var isSingleLine = false
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        HStack(spacing: TaleedSpacing.s4) {
            TaleedIconView(offer.bundle == nil ? .money : .storefront, size: 14, color: TaleedColor.textBody)
            Text(text.uppercased(with: l10n.language.locale))
                .taleedFont(TaleedFont.eyebrow)
                .foregroundStyle(TaleedColor.textBody)
                .fixedSize(horizontal: isSingleLine, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Offre sur un lot · 2 articles", "Votre offre", "Offre" or "Offre du vendeur" (§7 G9).
    private var text: String {
        switch ChatText.offerEyebrow(offer) {
        case let .bundle(count): l10n.format(.offersBundleOffer, count)
        case .mine: l10n.string(.appOfferYourOffer)
        case .buyer: l10n.string(.appOfferBuyerOffer)
        case .seller: l10n.string(.offersSellerOffer)
        }
    }
}

/// An `OFFER` card (slice C, §7 G9): the eyebrow, a bundle's items, the amount with its status under it
/// and, while it waits, when it expires. Its buttons (accept, decline, counter, withdraw, pay) are the
/// offers group's (G10); they follow the offer's `can…` flags.
struct ChatOfferCard: View {
    let offer: ChatOffer
    let isMine: Bool
    var now = Date()
    let openListing: (String) -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        let status = offer.displayStatus(at: now)
        ChatCard(isMine: isMine) {
            OfferEyebrow(offer: offer)
            if let bundle = offer.bundle {
                Divider()
                ForEach(bundle.items) { ChatBundleItemRow(item: $0, openListing: openListing) }
                Divider()
            }
            PriceText(amount: offer.amount, style: TaleedFont.priceDetail)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TaleedSpacing.s8) { statusLine(status) }
                VStack(alignment: .leading, spacing: TaleedSpacing.s4) { statusLine(status) }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The status pill, then the time left while the offer waits.
    @ViewBuilder
    private func statusLine(_ status: ChatOfferStatus) -> some View {
        OfferStatusBadge(status: status, isOnTint: isMine)
        if status == .pending {
            let relative = RelativeTimeText.string(for: offer.expiresAt, now: now, locale: l10n.language.formattingLocale)
            Text(l10n.format(.offersExpiresIn, relative))
                .taleedFont(TaleedFont.caption)
                .foregroundStyle(TaleedColor.textBody)
                .fixedSize(horizontal: false, vertical: true)
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
