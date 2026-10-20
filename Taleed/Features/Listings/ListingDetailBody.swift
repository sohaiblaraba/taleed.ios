import SwiftUI

/// The scrolling part of the listing screen, in the Figma order with the website's extra blocks
/// (screens.md §7 G4): photos, the seller's bar, the notice, price and fee, the buyer's accepted offer
/// and bundle toggle, specs, description, seller, trust strip, report link, member's items, similar items.
struct ListingDetailBody: View {
    struct Handlers {
        let favorite: () -> Void
        let openPhoto: (Int) -> Void
        let search: (ExploreQuery) -> Void
        let profile: (String) -> Void
        let message: () -> Void
        let shopBundles: () -> Void
        let toggleBundle: () -> Void
        let report: () -> Void
        let edit: () -> Void
        let visibility: (ListingDetailActions.Visibility) -> Void
        let delete: () -> Void
    }

    let listing: ListingDetail
    let actions: ListingDetailActions
    let model: ListingDetailViewModel
    let handlers: Handlers
    var galleryHeight = ListingDetailLayout.galleryMaxHeight
    @Environment(FavoriteStore.self) private var favorites

    var body: some View {
        Group { top }
        Group { bottom }
    }

    @ViewBuilder
    private var top: some View {
        ListingGallerySection(listing: listing, favorite: favorites.state(for: listing.summary), height: galleryHeight,
                              onFavorite: handlers.favorite, onOpenPhoto: handlers.openPhoto)
        if let owner = actions.owner {
            ListingOwnerBar(actions: owner, isChangingVisibility: model.isRunning(.visibility),
                            isDeleting: model.isRunning(.delete), onEdit: handlers.edit,
                            onVisibility: handlers.visibility, onDelete: handlers.delete)
        }
        if let banner = actions.banner {
            ListingNotice(banner: banner)
        }
        ListingInfoSection(listing: listing)
        ListingBuyerExtras(listing: listing, actions: actions, bundle: model.bundle,
                           isSavingBundle: model.isRunning(.bundle), onToggleBundle: handlers.toggleBundle,
                           onBackToBundle: handlers.shopBundles)
    }

    @ViewBuilder
    private var bottom: some View {
        SectionBand()
        ListingSpecsSection(listing: listing, onSearch: handlers.search)
        SectionBand()
        ListingDescriptionSection(text: listing.description)
        // Figma draws this band in `surfaceSubtle` (wireframes.md #4.9, flagged); the others are `navy/50`.
        SectionBand()
        ListingSellerSection(seller: listing.seller, showsMessage: actions.showsMessage,
                             isOpeningConversation: model.isRunning(.message),
                             onProfile: listing.seller.username.map { username in { handlers.profile(username) } },
                             onMessage: handlers.message)
        SectionBand()
        TrustStrip(style: .fullBleed)
        if actions.showsReport {
            ListingReportLink(onReport: handlers.report)
        }
        if !listing.memberItems.isEmpty {
            SectionBand()
            ListingMemberItemsSection(items: listing.memberItems, showsShopBundles: actions.showsShopBundles,
                                      onShopBundles: handlers.shopBundles,
                                      onSeeAll: listing.seller.username.map { username in { handlers.profile(username) } })
        }
        if !listing.similar.isEmpty {
            SectionBand()
            ListingSimilarSection(items: listing.similar)
        }
    }
}

/// Under the price, for a buyer: the offer the seller accepted, and the bundle toggle while they build
/// a bundle with this seller ("Ajouter au lot" / "Retirer du lot", "Retour à la boutique · N articles").
private struct ListingBuyerExtras: View {
    let listing: ListingDetail
    let actions: ListingDetailActions
    let bundle: BundleDetail?
    let isSavingBundle: Bool
    let onToggleBundle: () -> Void
    let onBackToBundle: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        if actions.acceptedOfferAmount != nil || actions.bundleToggle != nil {
            VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                if let amount = actions.acceptedOfferAmount {
                    // The website's banner speaks of "the buyer"; the app speaks to them (screens.md §7 G4).
                    InlineAlert(kind: .success,
                                title: l10n.format(.appListingAcceptedOffer, PriceFormatter.format(amount, language: l10n.language)))
                        .accessibilityIdentifier("listing.acceptedOffer")
                }
                if let toggle = actions.bundleToggle {
                    TaleedButton(title: l10n.string(toggle == .add ? .bundleAddToBundle : .bundleRemoveFromBundle),
                                 kind: toggle == .add ? .tertiary : .outline, size: .large,
                                 leadingIcon: toggle == .add ? .plus : .x, isLoading: isSavingBundle, isFullWidth: true,
                                 action: onToggleBundle)
                        .accessibilityIdentifier("listing.bundleToggle")
                    TaleedButton(title: l10n.format(.bundleBackToBundle, bundle?.selection.count ?? 0), kind: .hyperlink,
                                 size: .medium, isFullWidth: true, action: onBackToBundle)
                }
            }
            .padding(.horizontal, TaleedSpacing.s16)
            .padding(.bottom, TaleedSpacing.s16)
        }
    }
}

/// "Signaler" under the trust strip (the website's report link). Also in the overflow menu.
private struct ListingReportLink: View {
    let onReport: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        TaleedButton(title: l10n.string(.reportAction), kind: .hyperlink, size: .small, leadingIcon: .warning,
                     action: onReport)
            .padding(.horizontal, TaleedSpacing.s16)
            .padding(.vertical, TaleedSpacing.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("listing.report")
    }
}

/// The sticky bar with the tab bar under it (wireframes.md #4.17): "Faire une offre" and "Acheter" (or
/// "Payer maintenant · X"), either alone when only one is offered, or "Voir ma commande" for the order's
/// buyer or seller. Without any of them, the tab bar alone.
struct ListingDetailBottomBar: View {
    let actions: ListingDetailActions?
    let onBuy: () -> Void
    let onOffer: () -> Void
    let onViewOrder: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        if let actions, actions.hasBottomBar {
            if let buy = actions.buy, actions.showsMakeOffer, !actions.showsViewOrder {
                ItemDetailActionBar(makeOfferLabel: l10n.string(.listingMakeOffer), onMakeOffer: onOffer,
                                    buyNowLabel: buyLabel(buy), onBuyNow: onBuy) {
                    ShellTabBar(isEmbedded: true)
                }
            } else {
                BottomActionBar {
                    single(actions)
                } footer: {
                    ShellTabBar(isEmbedded: true)
                }
            }
        } else {
            ShellTabBar()
        }
    }

    @ViewBuilder
    private func single(_ actions: ListingDetailActions) -> some View {
        if actions.showsViewOrder {
            TaleedButton(title: l10n.string(.checkoutViewOrder), kind: .secondary, size: .large, isFullWidth: true,
                         action: onViewOrder)
                .accessibilityIdentifier("listing.viewOrder")
        } else if let buy = actions.buy {
            TaleedButton(title: buyLabel(buy), kind: .secondary, size: .large, isFullWidth: true, action: onBuy)
        } else {
            TaleedButton(title: l10n.string(.listingMakeOffer), kind: .tertiary, size: .large, isFullWidth: true,
                         action: onOffer)
        }
    }

    private func buyLabel(_ buy: ListingDetailActions.BuyButton) -> String {
        switch buy {
        case .buy: l10n.string(.listingBuyNow)
        case let .payNow(_, amount): "\(l10n.string(.offersPayNow)) · \(PriceFormatter.format(amount, language: l10n.language))"
        }
    }
}
