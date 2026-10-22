import SwiftUI

// The blocks of the listing screen (Figma Item Detail 135:9161, wireframes.md #4), top to bottom.

/// The photos (wireframes.md #4.3): 340 high, each fitted on white, page dots, the condition tag at
/// 16 / 12 and the favorite with its count at the top end. A tap opens the photos full screen.
struct ListingGallerySection: View {
    let listing: ListingDetail
    let favorite: FavoriteState
    var height = ListingDetailLayout.galleryMaxHeight
    let onFavorite: () -> Void
    let onOpenPhoto: (Int) -> Void
    @State private var current = 0
    @Environment(CatalogStore.self) private var catalog
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ItemPhotoGallery(photos: media, height: height, current: $current) {
            VStack {
                HStack(alignment: .top) {
                    if let condition = ListingCardContent.conditionTag(listing.condition, catalog: catalog.catalog) {
                        ConditionTag(code: condition.code, catalogLabel: condition.label,
                                     catalogShortLabel: condition.shortLabel)
                    }
                    Spacer(minLength: 0)
                    FavoriteButton(isFavorite: favorite.isFavorited, count: favorite.count >= 1 ? favorite.count : nil,
                                   onToggle: onFavorite)
                        .accessibilityIdentifier("listing.favorite")
                }
                Spacer(minLength: 0)
            }
            .padding(.top, TaleedSpacing.s12)
            .padding(.horizontal, TaleedSpacing.s16)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !listing.photos.isEmpty { onOpenPhoto(current) } }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: l10n.string(.appA11yOpenPhoto)) { onOpenPhoto(current) }
    }

    private var media: [ProductMedia] {
        listing.photos.isEmpty ? [.remote(nil)] : listing.photos.map { .remote($0.url) }
    }
}

/// The seller's bar (owner only, screens.md §7 G4): "Ceci est votre annonce.", then Edit, Hide or
/// "Remettre en vente", and Delete, as the status allows. Never a Boost (D1).
struct ListingOwnerBar: View {
    let actions: ListingDetailActions.OwnerActions
    let isChangingVisibility: Bool
    let isDeleting: Bool
    let onEdit: () -> Void
    let onVisibility: (ListingDetailActions.Visibility) -> Void
    let onDelete: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            Text(l10n.string(.listingOwnListingBanner))
                .taleedFont(TaleedFont.bodySmall)
                .foregroundStyle(TaleedColor.textBody)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TaleedSpacing.s8) { buttons }
                VStack(alignment: .leading, spacing: TaleedSpacing.s8) { buttons }
            }
        }
        .padding(TaleedSpacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TaleedColor.surfaceGrouped)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var buttons: some View {
        if actions.canEdit {
            TaleedButton(title: l10n.string(.listingEditListing), kind: .tertiary, size: .small, action: onEdit)
                .accessibilityIdentifier("listing.owner.edit")
        }
        if let visibility = actions.visibility {
            TaleedButton(title: l10n.string(visibility == .hide ? .listingHide : .listingUnhide), kind: .tertiary,
                         size: .small, leadingIcon: .eye, isLoading: isChangingVisibility) {
                onVisibility(visibility)
            }
            .accessibilityIdentifier("listing.owner.visibility")
        }
        if actions.canDelete {
            TaleedButton(title: l10n.string(.listingDeleteListing), kind: .outline, size: .small, leadingIcon: .trash,
                         isLoading: isDeleting, action: onDelete)
                .accessibilityIdentifier("listing.owner.delete")
        }
    }
}

/// Price, title, the buyer's fee and the views (wireframes.md #4.4), then the posted date (screens.md
/// §7 G4: the apps show `createdAt`).
struct ListingInfoSection: View {
    let listing: ListingDetail
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        HStack(alignment: .top, spacing: TaleedSpacing.s8) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                VStack(alignment: .leading, spacing: 0) {
                    PriceText(amount: listing.price, style: TaleedFont.priceDetail)
                        .accessibilityIdentifier("listing.price")
                    Text(verbatim: listing.title.isolatedByContent)
                        .taleedFont(TaleedFont.itemTitleDetail)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(l10n.format(.listingProtectionFeeNote, PriceFormatter.format(listing.protectionFee, language: l10n.language)))
                    .taleedFont(TaleedFont.meta)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
                    .accessibilityIdentifier("listing.fee")
                Text(l10n.format(.appListingPosted, posted))
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
            }
            Spacer(minLength: 0)
            HStack(spacing: TaleedSpacing.s4) {
                TaleedIconView(.eyeBold, size: 14, color: TaleedColor.navy500)
                Text(l10n.format(.listingViews, listing.viewsCount))
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(TaleedSpacing.s16)
    }

    private var posted: String {
        RelativeTimeText.string(for: listing.createdAt, locale: l10n.language.formattingLocale)
    }
}

/// Brand, size, condition, category (`Parent › Child`, a link to its search) and where it ships from
/// (wireframes.md #4.6 and the website's rows). A catalog brand links to its search; a brand the seller
/// typed stays text (slice A).
struct ListingSpecsSection: View {
    let listing: ListingDetail
    let onSearch: (ExploreQuery) -> Void
    @Environment(CatalogStore.self) private var catalog
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                row.view(index < rows.count - 1)
            }
        }
    }

    private struct Row {
        let view: (_ showsDivider: Bool) -> AnyView
    }

    private var rows: [Row] {
        var rows: [Row] = []
        if let brand = listing.brand {
            let search = brand.slug.map { slug in { onSearch(ExploreQuery(brand: slug)) } }
            rows.append(Row {
                AnyView(SpecRow(label: l10n.string(.listingBrand), value: brand.name.isolatedByContent, showsDivider: $0,
                                action: search))
            })
        }
        if let size = listing.size {
            rows.append(Row { AnyView(SpecRow(label: l10n.string(.listingSize), value: size.isolatedByContent, showsDivider: $0)) })
        }
        if let condition = ListingCardContent.conditionTag(listing.condition, catalog: catalog.catalog) {
            rows.append(Row {
                AnyView(SpecRow(label: l10n.string(.listingConditionLabel), showsDivider: $0) {
                    ConditionTag(code: condition.code, catalogLabel: condition.label, catalogShortLabel: condition.shortLabel)
                })
            })
        }
        let category = [listing.category.parentName, listing.category.name].compactMap { $0 }.joined(separator: " › ")
        rows.append(Row {
            AnyView(SpecRow(label: l10n.string(.listingCategory), value: category, showsDivider: $0) {
                onSearch(ExploreQuery(category: listing.category.slug))
            })
        })
        if let wilaya = listing.shipsFrom {
            rows.append(Row { AnyView(SpecRow(label: l10n.string(.listingShipsFrom), value: wilaya.name, showsDivider: $0)) })
        }
        return rows
    }
}

/// The description, as the seller wrote it (never translated).
struct ListingDescriptionSection: View {
    let text: String
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            SectionTitle(text: l10n.string(.listingDescription))
            // Member-written: laid out by its own script, as the profile's bio (api-guide.md: natural
            // alignment), so a French description starts at the left in the Arabic app.
            Text(verbatim: text)
                .taleedFont(TaleedFont.descriptionBody)
                .foregroundStyle(TaleedColor.textSecondarySmall)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .naturalDirection(of: text)
        }
        .padding(TaleedSpacing.s16)
    }
}

/// A notice above the product block: reserved, sold, hidden (owner), or the buyer's accepted offer.
struct ListingNotice: View {
    let banner: ListingDetailActions.Banner
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        let (kind, key): (TaleedFeedbackKind, L10nKey) = switch banner {
        case .reserved: (.warning, .listingReserved)
        case .sold: (.info, .listingSold)
        case .hidden: (.info, .appListingHiddenBanner)
        }
        InlineAlert(kind: kind, title: l10n.string(key))
            .padding(.horizontal, TaleedSpacing.s16)
            .padding(.top, TaleedSpacing.s16)
            .accessibilityIdentifier("listing.banner")
    }
}

/// The listing screen while it loads: the gallery, the price block and three rows.
struct ListingDetailSkeleton: View {
    var galleryHeight = ListingDetailLayout.galleryMaxHeight
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
            SkeletonBlock(height: galleryHeight, radius: 0)
            VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
                SkeletonBlock(width: 120, height: 24)
                SkeletonBlock(width: 220, height: 18)
                SkeletonBlock(width: 180, height: 12, color: TaleedColor.surfaceSubtle)
                SkeletonBlock(height: 44, radius: TaleedRadius.s)
                SkeletonBlock(height: 44, radius: TaleedRadius.s)
            }
            .padding(.horizontal, TaleedSpacing.s16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.string(.commonLoading))
    }
}

/// The listing screen's layout rules.
enum ListingDetailLayout {
    /// The photos' height in Figma's Item Detail.
    static let galleryMaxHeight: CGFloat = 340

    /// 340 pt, but at most 60 % of the height between the app bar and the bottom bar (never under
    /// 220 pt), so a short screen still shows the price, the title and the fee line under the photos.
    /// Before the screen is measured: 340.
    static func galleryHeight(viewport: CGFloat) -> CGFloat {
        guard viewport > 0 else { return galleryMaxHeight }
        return min(galleryMaxHeight, max(220, (viewport * 0.6).rounded()))
    }
}
