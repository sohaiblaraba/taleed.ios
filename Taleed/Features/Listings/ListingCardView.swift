import SwiftUI

/// The listing card of every grid (screens.md §2 G2 screen 2): the design-system product card with the
/// catalog's condition labels, the shared heart, and the listing screen on tap. Signed out, the heart
/// asks to sign in and then adds the favorite (screens.md §0.5).
struct ListingCardView: View {
    let listing: ListingSummary
    /// The heart's tap on a screen that handles it itself (Favorites); the shared toggle otherwise.
    var onFavorite: ((ListingSummary) -> Void)?
    /// False where every card is the same seller's (a wardrobe, "Articles du membre"): the rating would
    /// repeat on each.
    var showsSellerRating = true
    /// False where every card is the same seller's: "Your item" would repeat on each when the member
    /// looks at their own (the website shows it only in the feed and search).
    var showsOwnerTag = true
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoriteStore.self) private var favorites
    @Environment(AppRouter.self) private var router
    @Environment(SessionManager.self) private var session
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ProductCard(
            product: ListingCardContent.product(
                for: listing, favorite: favorites.state(for: listing), catalog: catalog.catalog,
                showsSellerRating: showsSellerRating, showsOwnerTag: showsOwnerTag, text: { l10n.string($0) }
            ),
            onTap: { router.push(.listing(id: listing.id)) },
            onFavorite: favorite
        )
    }

    private func favorite() {
        if let onFavorite {
            onFavorite(listing)
        } else if session.isSignedIn {
            favorites.toggle(listing)
        } else {
            router.requireSignIn { [favorites, listing] in favorites.setFavorite(listing, to: true) }
        }
    }
}

/// What a listing card shows, from the API's card, the heart's state and the catalog.
enum ListingCardContent {
    static func product(for listing: ListingSummary, favorite: FavoriteState, catalog: Catalog?,
                        showsSellerRating: Bool = true, showsOwnerTag: Bool = true,
                        text: (L10nKey) -> String) -> ProductSummary {
        let condition = conditionTag(listing.condition, catalog: catalog)
        return ProductSummary(
            id: listing.id,
            title: listing.title,
            price: listing.price,
            media: .remote(listing.imageURL),
            conditionCode: condition?.code,
            conditionLabel: condition?.label ?? "",
            conditionShortLabel: condition?.shortLabel,
            location: listing.shipsFrom?.name,
            sizeLabel: listing.size,
            rating: showsSellerRating ? listing.sellerRating?.average : nil,
            isFavorite: favorite.isFavorited,
            // The count shows only above 0, as on the website.
            favoriteCount: favorite.count >= 1 ? favorite.count : nil,
            statusLabel: statusKey(listing.status).map(text),
            boostedLabel: listing.isBoosted ? text(.listingBoosted) : nil,
            ownerLabel: showsOwnerTag && listing.isOwner ? text(.listingYourItem) : nil
        )
    }

    /// The strip of a listing that is not for sale. On sale, a draft or an unknown status: none.
    static func statusKey(_ status: ListingStatus) -> L10nKey? {
        switch status {
        case .reserved: .listingStatusReserved
        case .sold: .listingStatusSold
        case .hidden: .listingStatusHidden
        case .active, .draft, .unknown: nil
        }
    }

    /// The condition tag: the catalog's labels (decision 6), or the app's own for the five known codes
    /// before the catalog arrived. A code neither knows shows no tag (screens.md §0.4).
    static func conditionTag(_ code: String?, catalog: Catalog?) -> ConditionTagContent? {
        guard let code else { return nil }
        if let entry = catalog?.condition(code) {
            return ConditionTagContent(code: code, label: entry.label,
                                       shortLabel: entry.shortLabel.isEmpty ? nil : entry.shortLabel)
        }
        return ProductCondition(code: code) == nil ? nil : ConditionTagContent(code: code, label: "", shortLabel: nil)
    }

    /// A condition code with the catalog's labels for it.
    struct ConditionTagContent: Equatable {
        let code: String
        let label: String
        let shortLabel: String?
    }
}

/// The two-column grid of listing cards (Figma Home: gap 8, inside the 16 pt margins); one column at
/// accessibility text sizes.
struct ListingGrid: View {
    let listings: [ListingSummary]
    /// See `ListingCardView.onFavorite`.
    var onFavorite: ((ListingSummary) -> Void)?
    /// See `ListingCardView.showsSellerRating`.
    var showsSellerRating = true
    /// See `ListingCardView.showsOwnerTag`.
    var showsOwnerTag = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(columns: ProductGridColumns.columns(for: dynamicTypeSize, alignment: .top),
                  spacing: TaleedLayout.productGridGap) {
            ForEach(listings) {
                ListingCardView(listing: $0, onFavorite: onFavorite, showsSellerRating: showsSellerRating,
                                showsOwnerTag: showsOwnerTag)
            }
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
    }
}
