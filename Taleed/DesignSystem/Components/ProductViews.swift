import NukeUI
import SwiftUI

/// A product photo: a URL from the API, or a bundled image (previews and the gallery).
enum ProductMedia {
    case remote(URL?)
    case local(Image)
}

/// Draws a product photo, aspect-fill, with a skeleton while it loads. Fitted photos (Item Detail's
/// gallery, wireframes.md #4.3) sit on white once loaded. Photos never mirror.
struct ProductMediaView: View {
    let media: ProductMedia
    var contentMode: ContentMode = .fill

    var body: some View {
        Rectangle()
            .fill(contentMode == .fit ? TaleedColor.surfacePrimary : TaleedColor.skeleton)
            .overlay {
                switch media {
                case let .local(image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                case let .remote(url):
                    LazyImage(url: url) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: contentMode)
                        } else if contentMode == .fit {
                            Rectangle().fill(TaleedColor.skeleton)
                        }
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// What product cards and list rows show. Plain data, built by the feature from API models.
struct ProductSummary: Identifiable {
    let id: String
    var title: String
    /// Whole dinars.
    var price: Int
    var media: ProductMedia
    /// API condition code (`VERY_GOOD`) and the catalog's `label` / `shortLabel` for it
    /// (`GET /catalog` conditions), which tags show for codes the app does not know.
    var conditionCode: String?
    var conditionLabel: String = ""
    var conditionShortLabel: String?
    var location: String?
    /// "2 hours ago", already formatted.
    var recency: String?
    var sizeLabel: String?
    var rating: Double?
    var isFavorite = false
    var favoriteCount: Int?
    /// The strip at the bottom of the photo for a listing that is not for sale ("Reserved", "Sold",
    /// "Hidden"); nil for one on sale.
    var statusLabel: String?
    /// The label of the boosted tag under the condition tag ("Boosted"); nil when not boosted.
    var boostedLabel: String?
}

/// Product card for the two-column grid (design-system §3.1). The whole card opens the item;
/// the favorite control is a separate target.
struct ProductCard: View {
    let product: ProductSummary
    let onTap: () -> Void
    let onFavorite: () -> Void
    @Environment(\.locale) private var locale

    private static let ratingStyle = TaleedFont.cardRating

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ProductMediaView(media: product.media)
                    .aspectRatio(TaleedSize.productCardWidth / TaleedSize.productCardMediaHeightWithSize, contentMode: .fit)
                    .overlay(alignment: .bottom) {
                        if let status = product.statusLabel { ProductStatusStrip(text: status) }
                    }
                info
            }
            .background(TaleedColor.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: TaleedSize.productCardRadius, style: .continuous))
            .taleedShadow(TaleedElevation.level1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .overlay(alignment: .top) {
            // One row so that, with large text, the tag wraps (and steps its size down) beside the heart
            // instead of running under it; the label is never cut.
            HStack(alignment: .top, spacing: TaleedSpacing.s4) {
                VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                    if let code = product.conditionCode {
                        ConditionTag(code: code, catalogLabel: product.conditionLabel,
                                     catalogShortLabel: product.conditionShortLabel)
                    }
                    if let boosted = product.boostedLabel { BoostedTag(title: boosted) }
                }
                .accessibilityHidden(true)
                Spacer(minLength: 0)
                FavoriteButton(isFavorite: product.isFavorite, count: product.favoriteCount, onToggle: onFavorite)
                    .layoutPriority(1)
            }
            .padding(TaleedSize.productCardPadding)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: TaleedSize.productCardInfoGap) {
            HStack(alignment: .firstTextBaseline, spacing: TaleedSpacing.s4) {
                // Two lines, as the website's and Figma's product cards; every card keeps both, so the
                // cards of a grid row line up.
                Text(verbatim: product.title)
                    .taleedFont(TaleedFont.cardTitle)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let rating = product.rating {
                    HStack(spacing: TaleedSpacing.s4) {
                        TaleedIconView(.star, size: 14, color: TaleedColor.feedbackWarning)
                        // "4.8" as on the detail's seller card and the website (`toFixed(1)`).
                        Text(verbatim: RatingText.average(rating))
                            .taleedFont(Self.ratingStyle)
                            .foregroundStyle(TaleedColor.textPrimary)
                            .monospacedDigit()
                    }
                }
            }
            PriceText(amount: product.price, style: TaleedFont.priceCard)
            HStack(spacing: TaleedSpacing.s4) {
                if let location = product.location {
                    HStack(spacing: TaleedSpacing.s4) {
                        TaleedIconView(.mapPin, size: 13, color: TaleedColor.textSecondary)
                        Text(verbatim: location)
                            .taleedFont(TaleedFont.meta)
                            .foregroundStyle(TaleedColor.textSecondarySmall)
                            .lineLimit(1)
                    }
                }
                if let size = product.sizeLabel { SizeTag(text: size) }
            }
            // Cards without a size tag keep the height of those with one, so grid rows line up.
            .frame(minHeight: TaleedSize.sizeTagHeight, alignment: .leading)
        }
        .padding(TaleedSize.productCardPadding)
    }

    private var accessibilityText: String {
        let language = AppLanguage(locale: locale)
        let condition = product.conditionCode.map {
            ProductCondition.label(code: $0, catalogLabel: product.conditionLabel,
                                   catalogShortLabel: product.conditionShortLabel, length: .full, language: language)
        }
        let rating = product.rating.map { "★ " + RatingText.average($0) }
        return [product.title, PriceFormatter.format(product.price, language: language), product.statusLabel, condition,
                product.boostedLabel, rating, product.location, product.sizeLabel]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// The strip across the bottom of a card's photo for a listing that is not for sale: `navy/800` at
/// 85 %, white caption, centred (the website's status strip in the design system's colours).
struct ProductStatusStrip: View {
    let text: String

    var body: some View {
        Text(text)
            .taleedFont(TaleedFont.tagLabel)
            .foregroundStyle(TaleedColor.textInverse)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, TaleedSpacing.s8)
            .background(TaleedColor.navy800.opacity(0.85))
    }
}

/// Product list row (design-system §3.3). `.standard` for results lists, `.dense` for the search pattern.
struct ProductListRow: View {
    enum Style: Sendable { case standard, dense }

    let product: ProductSummary
    var style: Style = .standard
    let onTap: () -> Void
    let onFavorite: () -> Void

    private static let nameStyle = TaleedTextStyle(size: 15, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                   relativeTo: .subheadline)
    private static let denseNameStyle = TaleedTextStyle(size: 13, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                        relativeTo: .footnote)
    private static let densePriceStyle = TaleedTextStyle(size: 15, weight: .extrabold, lineHeight: nil, letterSpacing: 0,
                                                         relativeTo: .subheadline)

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let dense = style == .dense
        Button(action: onTap) {
            Group {
                if isStacked {
                    // From accessibility sizes on, the photo goes on top, so the text keeps the row's width.
                    VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
                        ProductMediaView(media: product.media)
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.s, style: .continuous))
                        details
                            .padding(.trailing, TaleedSize.touchTargetMin)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    HStack(alignment: dense ? .top : .center, spacing: dense ? TaleedSpacing.s12 : TaleedSpacing.s16) {
                        ProductMediaView(media: product.media)
                            .frame(width: dense ? 92 : TaleedSize.productListRowMedia,
                                   height: dense ? 100 : TaleedSize.productListRowMedia)
                            .clipShape(RoundedRectangle(cornerRadius: dense ? TaleedRadius.s : TaleedRadius.m, style: .continuous))
                        details
                            .padding(.trailing, dense ? 28 : 0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(dense ? TaleedSpacing.s8 : TaleedSize.productListRowPadding)
            .background(TaleedColor.surfacePrimary,
                        in: RoundedRectangle(cornerRadius: dense ? TaleedRadius.m : TaleedRadius.l, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .overlay(alignment: isStacked ? .bottomTrailing : dense ? .topTrailing : .trailing) {
            // The dense heart's 44 pt box keeps the glyph where its 32 pt box had it.
            favorite.padding(dense ? TaleedSpacing.s4 / 2 : TaleedSize.productListRowPadding)
        }
    }

    /// The dense row from accessibility sizes on: photo on top, the heart at the end of the details.
    private var isStacked: Bool { style == .dense && dynamicTypeSize.isAccessibilitySize }

    @ViewBuilder
    private var favorite: some View {
        if style == .dense {
            FavoriteHeartToggle(isFavorite: product.isFavorite, onToggle: onFavorite)
        } else {
            FavoriteCircleButton(isFavorite: product.isFavorite, onToggle: onFavorite)
        }
    }

    private var details: some View {
        let dense = style == .dense
        return VStack(alignment: .leading, spacing: dense ? TaleedSpacing.s4 : 7) {
            if let code = product.conditionCode {
                ConditionTag(code: code, catalogLabel: product.conditionLabel, catalogShortLabel: product.conditionShortLabel,
                             size: .large)
            }
            Text(verbatim: product.title)
                .taleedFont(dense ? Self.denseNameStyle : Self.nameStyle)
                .foregroundStyle(TaleedColor.textPrimary)
                .lineLimit(2)
            PriceText(amount: product.price, style: dense ? Self.densePriceStyle : TaleedFont.priceListRow)
            HStack(spacing: 10) {
                if let location = product.location {
                    Text(verbatim: location)
                }
                if product.location != nil, product.recency != nil {
                    Circle().fill(TaleedColor.textSecondary).frame(width: 3, height: 3).accessibilityHidden(true)
                }
                if let recency = product.recency {
                    Text(recency)
                }
            }
            .taleedFont(TaleedFont.meta)
            .foregroundStyle(TaleedColor.textSecondarySmall)
            .lineLimit(1)
        }
        .padding(.trailing, dense ? 0 : 48)
    }
}

/// The grouped list container of list rows (design-system §3.3): `surfaceGrouped`, `radius.l`, rows
/// 8 apart with a 1 pt `surface/subtle` divider in the gap.
struct ProductListContainer<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    @ViewBuilder let row: (Data.Element) -> Row

    init(_ data: Data, @ViewBuilder row: @escaping (Data.Element) -> Row) {
        self.data = data
        self.row = row
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                if index > 0 {
                    Rectangle()
                        .fill(TaleedColor.surfaceSubtle)
                        .frame(height: 1)
                        .padding(.vertical, (TaleedSpacing.s8 - 1) / 2)
                        .accessibilityHidden(true)
                }
                row(element)
            }
        }
        .padding(TaleedSpacing.s8)
        .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.l, style: .continuous))
    }
}
