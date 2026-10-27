import SwiftUI

/// A row of My listings: the design-system product list row (§3.3: 108 pt photo, condition tag, title,
/// price, wilaya), with the status strip of cards on the photo ("Masqué", "Réservé", "Vendu") and, in
/// place of the heart, the 40 pt circle that opens the seller's actions for its status. A row with no
/// action allowed (reserved) has no menu. VoiceOver offers the same actions on the row.
struct MyListingRow: View {
    struct Handlers {
        let open: (ListingSummary) -> Void
        let edit: (ListingSummary) -> Void
        let visibility: (ListingSummary, ListingDetailActions.Visibility) -> Void
        let delete: (ListingSummary) -> Void
    }

    let listing: ListingSummary
    let actions: ListingDetailActions.OwnerActions
    /// An action runs on it: a spinner in place of the menu.
    let isBusy: Bool
    let handlers: Handlers
    @Environment(CatalogStore.self) private var catalog
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let nameStyle = TaleedTextStyle(size: 15, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                   relativeTo: .subheadline)

    private var hasActions: Bool { actions.canEdit || actions.visibility != nil || actions.canDelete }

    var body: some View {
        let product = ListingCardContent.product(for: listing, favorite: FavoriteState(isFavorited: false, count: 0),
                                                 catalog: catalog.catalog, showsOwnerTag: false, text: { l10n.string($0) })
        Button { handlers.open(listing) } label: {
            // Accessibility text sizes: the photo above the details, so the text keeps the row's width.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: TaleedSpacing.s12))
                : AnyLayout(HStackLayout(spacing: TaleedSize.productListRowGap))
            layout {
                ProductMediaView(media: product.media)
                    .frame(width: TaleedSize.productListRowMedia, height: TaleedSize.productListRowMedia)
                    .overlay(alignment: .bottom) {
                        if let status = product.statusLabel { ProductStatusStrip(text: status) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TaleedSize.productListRowMediaRadius, style: .continuous))
                details(product)
                    .padding(.trailing, hasActions && !dynamicTypeSize.isAccessibilitySize
                        ? TaleedSize.productListRowFavorite + TaleedSpacing.s8 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(TaleedSize.productListRowPadding)
            .background(TaleedColor.surfacePrimary,
                        in: RoundedRectangle(cornerRadius: TaleedSize.productListRowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(product))
        .accessibilityAddTraits(.isButton)
        .accessibilityActions { accessibilityActions }
        .overlay(alignment: .topTrailing) {
            if hasActions {
                menu.padding(TaleedSize.productListRowPadding)
            }
        }
        .accessibilityIdentifier("myListings.row.\(listing.id)")
    }

    private func details(_ product: ProductSummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let code = product.conditionCode {
                ConditionTag(code: code, catalogLabel: product.conditionLabel, catalogShortLabel: product.conditionShortLabel,
                             size: .large)
            }
            Text(verbatim: product.title)
                .taleedFont(Self.nameStyle)
                .foregroundStyle(TaleedColor.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            PriceText(amount: product.price, style: TaleedFont.priceListRow)
            if let location = product.location {
                Text(verbatim: location)
                    .taleedFont(TaleedFont.meta)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        if isBusy {
            ProgressView()
                .tint(TaleedColor.brandPrimary)
                .frame(width: TaleedSize.productListRowFavorite, height: TaleedSize.productListRowFavorite)
                .accessibilityLabel(l10n.string(.commonLoading))
        } else {
            Menu {
                menuItems
            } label: {
                TaleedIconView(.dotsThree, size: 18, color: TaleedColor.textPrimary)
                    .frame(width: TaleedSize.productListRowFavorite, height: TaleedSize.productListRowFavorite)
                    .background(Circle().fill(TaleedColor.surfaceGrouped))
                    .contentShape(Circle())
                    .minimumHitArea()
            }
            .buttonStyle(.plain)
            // The entries' icons in the text colour (the app's tint would draw them blue).
            .tint(TaleedColor.textPrimary)
            .accessibilityLabel(l10n.string(.commonMore))
            .accessibilityIdentifier("myListings.menu.\(listing.id)")
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        // Leading icons as in iOS menus: the design system's eye and trash, a pencil (SF Symbol, the set has none).
        if actions.canEdit {
            Button { handlers.edit(listing) } label: {
                Label(l10n.string(.listingEditListing), systemImage: "pencil")
            }
        }
        if let visibility = actions.visibility {
            Button { handlers.visibility(listing, visibility) } label: {
                Label { Text(l10n.string(visibility == .hide ? .listingHide : .listingUnhide)) } icon: {
                    Image(taleedMenuIcon: .eye)
                }
            }
        }
        if actions.canDelete {
            Button(role: .destructive) { handlers.delete(listing) } label: {
                Label { Text(l10n.string(.listingDeleteListing)) } icon: {
                    Image(taleedMenuIcon: .trash, color: TaleedColor.feedbackError)
                }
            }
        }
    }

    @ViewBuilder
    private var accessibilityActions: some View {
        if !isBusy { menuItems }
    }

    private func accessibilityText(_ product: ProductSummary) -> String {
        let condition = product.conditionCode.map {
            ProductCondition.label(code: $0, catalogLabel: product.conditionLabel,
                                   catalogShortLabel: product.conditionShortLabel, length: .full, language: l10n.language)
        }
        return [product.title, PriceFormatter.format(product.price, language: l10n.language), product.statusLabel,
                condition, product.location]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
