import SwiftUI

/// The seller (wireframes.md #4.10, screens.md §2 G4 "Seller card"): "Vendeur", the avatar 44 with the
/// handle and badge, the rating ("Aucune évaluation pour le moment." without reviews), online or last
/// seen, "Voir le profil", then "Envoyer un message".
struct ListingSellerSection: View {
    let seller: ListingSellerInfo
    let showsMessage: Bool
    let isOpeningConversation: Bool
    let onProfile: (() -> Void)?
    let onMessage: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            SectionTitle(text: l10n.string(.listingSeller))
            HStack(alignment: .center, spacing: TaleedSpacing.s12) {
                identity
                Spacer(minLength: 0)
                if let onProfile {
                    TaleedButton(title: l10n.string(.listingViewProfile), kind: .hyperlink, size: .large, action: onProfile)
                        .accessibilityIdentifier("listing.seller.profile")
                }
            }
            if showsMessage {
                TaleedButton(title: l10n.string(.listingMessageSeller), kind: .tertiary, size: .large, leadingIcon: .chatCircle,
                             isLoading: isOpeningConversation, isFullWidth: true, action: onMessage)
                    .accessibilityIdentifier("listing.message")
            }
        }
        .padding(TaleedSpacing.s16)
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: TaleedSpacing.s12) {
            TaleedAvatar(initials: TaleedAvatar.initials(from: seller.username ?? seller.displayName), size: 44,
                         imageURL: seller.avatarURL, isVerified: seller.isVerified && !seller.isOfficial, style: .wireframe)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                HStack(spacing: TaleedSpacing.s4) {
                    Text(verbatim: seller.displayName.isolatedLeftToRight)
                        .taleedFont(TaleedFont.bodyLarge.with(weight: .bold))
                        .foregroundStyle(TaleedColor.textPrimary)
                        .lineLimit(1)
                    // The official badge replaces the verified one (screens.md §0.3). The verified one is
                    // the avatar's badge (design-system §2.11), read with the identity below.
                    if seller.isOfficial {
                        TaleedIconView(.sealCheck, size: 16, color: TaleedColor.brandPrimary)
                            .accessibilityLabel(l10n.string(.profileOfficial))
                    }
                }
                rating
                presence
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(seller.isVerified && !seller.isOfficial ? l10n.string(.profileVerified) : "")
    }

    @ViewBuilder
    private var rating: some View {
        if let rating = seller.rating {
            HStack(spacing: TaleedSpacing.s4) {
                TaleedIconView(.star, size: 14, color: TaleedColor.warningIcon)
                Text(verbatim: "\(RatingText.average(rating.average)) · \(rating.count)".isolatedLeftToRight)
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.textBody)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(l10n.format(.listingSellerRating, RatingText.average(rating.average), "\(rating.count)"))
        } else {
            Text(l10n.string(.reviewsNoReviews))
                .taleedFont(TaleedFont.caption)
                .foregroundStyle(TaleedColor.textSecondary)
        }
    }

    @ViewBuilder
    private var presence: some View {
        if seller.isOnline {
            HStack(spacing: 6) {
                Circle().fill(TaleedColor.feedbackSuccess).frame(width: 6, height: 6).accessibilityHidden(true)
                Text(l10n.string(.listingOnlineNow))
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.textSecondary)
            }
        } else if let lastSeen = seller.lastSeenAt {
            Text(l10n.format(.listingLastSeen, RelativeTimeText.string(for: lastSeen, locale: l10n.language.formattingLocale)))
                .taleedFont(TaleedFont.caption)
                .foregroundStyle(TaleedColor.textSecondary)
        }
    }
}

/// "Articles du membre" (up to 5, in a row of cards, then "Voir tout" to the profile) with "Achète en
/// lot" when the server allows a bundle (wireframes.md #4.14, screens.md §7 G4).
struct ListingMemberItemsSection: View {
    let items: [ListingSummary]
    let showsShopBundles: Bool
    let onShopBundles: () -> Void
    let onSeeAll: (() -> Void)?
    @Environment(LanguageManager.self) private var l10n
    @Environment(FavoriteStore.self) private var favorites
    @Environment(ListingChangeCenter.self) private var listingChanges

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            HStack(spacing: TaleedSpacing.s8) {
                SectionTitle(text: l10n.string(.listingMemberItems))
                if showsShopBundles {
                    TaleedButton(title: l10n.string(.bundleBannerTitle), kind: .secondary, size: .small, action: onShopBundles)
                        .accessibilityIdentifier("listing.shopBundles")
                }
            }
            .padding(.horizontal, TaleedSpacing.s16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: TaleedLayout.productGridGap) {
                    // Two cards per screen width, as the grid below (Figma: one 200 pt card per column).
                    ForEach(visibleItems) {
                        ListingCardView(listing: $0, showsSellerRating: false)
                            .containerRelativeFrame(.horizontal, count: 2, spacing: TaleedLayout.productGridGap)
                    }
                }
            }
            .contentMargins(.horizontal, TaleedLayout.screenMargin, for: .scrollContent)
            if let onSeeAll {
                TaleedButton(title: l10n.string(.commonSeeAll), kind: .hyperlink, size: .medium, trailingIcon: .caretRight,
                             action: onSeeAll)
                    .padding(.horizontal, TaleedSpacing.s16)
            }
        }
        .padding(.vertical, TaleedSpacing.s16)
    }

    private var visibleItems: [ListingSummary] {
        listingChanges.cards(items.filter { !favorites.removedIds.contains($0.id) })
    }
}

/// "Articles similaires": up to 5 cards in the two-column grid (wireframes.md #4.16).
struct ListingSimilarSection: View {
    let items: [ListingSummary]
    @Environment(LanguageManager.self) private var l10n
    @Environment(FavoriteStore.self) private var favorites
    @Environment(ListingChangeCenter.self) private var listingChanges

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            SectionTitle(text: l10n.string(.listingSimilar))
                .padding(.horizontal, TaleedSpacing.s16)
            ListingGrid(listings: listingChanges.cards(items.filter { !favorites.removedIds.contains($0.id) }))
        }
        .padding(.vertical, TaleedSpacing.s16)
    }
}
