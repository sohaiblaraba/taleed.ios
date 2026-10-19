import NukeUI
import SwiftUI

/// A product photo: a URL from the API, or a bundled image (previews and the gallery).
enum ProductMedia {
    case remote(URL?)
    case local(Image)
}

/// Draws a product photo, aspect-fill, with a skeleton while it loads. Photos never mirror.
struct ProductMediaView: View {
    let media: ProductMedia
    var contentMode: ContentMode = .fill

    var body: some View {
        Rectangle()
            .fill(TaleedColor.skeleton)
            .overlay {
                switch media {
                case let .local(image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                case let .remote(url):
                    LazyImage(url: url) { state in
                        if let image = state.image { image.resizable().aspectRatio(contentMode: contentMode) }
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
                    .aspectRatio(TaleedSize.ProductCard.width / TaleedSize.ProductCard.mediaHeightWithSize, contentMode: .fit)
                info
            }
            .background(TaleedColor.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: TaleedSize.ProductCard.radius, style: .continuous))
            .taleedShadow(TaleedElevation.level1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .overlay(alignment: .top) {
            // One row so that, with large text, the tag truncates instead of running under the heart.
            HStack(alignment: .top, spacing: TaleedSpacing.s4) {
                if let code = product.conditionCode {
                    ConditionTag(code: code, catalogLabel: product.conditionLabel,
                                 catalogShortLabel: product.conditionShortLabel)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                FavoriteControl(isSaved: product.isFavorite, count: product.favoriteCount, action: onFavorite)
                    .layoutPriority(1)
            }
            .padding(TaleedSize.ProductCard.padding)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: TaleedSize.ProductCard.infoGap) {
            HStack(spacing: TaleedSpacing.s4) {
                Text(verbatim: product.title)
                    .taleedFont(TaleedFont.cardTitle)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let rating = product.rating {
                    HStack(spacing: TaleedSpacing.s4) {
                        TaleedIconView(.star, size: 14, color: TaleedColor.feedbackWarning)
                        Text(rating, format: .number.precision(.fractionLength(1)))
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
                            .foregroundStyle(TaleedColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                if let size = product.sizeLabel { SizeTag(text: size) }
            }
            // Cards without a size tag keep the height of those with one, so grid rows line up.
            .frame(minHeight: TaleedSize.SizeTag.height, alignment: .leading)
        }
        .padding(TaleedSize.ProductCard.padding)
    }

    private var accessibilityText: String {
        let language = AppLanguage(locale: locale)
        let condition = product.conditionCode.map {
            ProductCondition.label(code: $0, catalogLabel: product.conditionLabel,
                                   catalogShortLabel: product.conditionShortLabel, length: .full, language: language)
        }
        let rating = product.rating.map { "★ " + $0.formatted(.number.precision(.fractionLength(1)).locale(locale)) }
        return [product.title, PriceFormatter.format(product.price, language: language), condition, rating,
                product.location, product.sizeLabel]
            .compactMap { $0 }
            .joined(separator: ", ")
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

    var body: some View {
        let dense = style == .dense
        Button(action: onTap) {
            HStack(alignment: dense ? .top : .center, spacing: dense ? TaleedSpacing.s12 : TaleedSpacing.s16) {
                ProductMediaView(media: product.media)
                    .frame(width: dense ? 92 : TaleedSize.ProductListRow.media, height: dense ? 100 : TaleedSize.ProductListRow.media)
                    .clipShape(RoundedRectangle(cornerRadius: dense ? TaleedRadius.s : TaleedRadius.m, style: .continuous))
                details
                    .padding(.trailing, dense ? 28 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(dense ? TaleedSpacing.s8 : TaleedSize.ProductListRow.padding)
            .background(TaleedColor.surfacePrimary,
                        in: RoundedRectangle(cornerRadius: dense ? TaleedRadius.m : TaleedRadius.l, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .overlay(alignment: dense ? .topTrailing : .trailing) {
            favorite.padding(dense ? TaleedSpacing.s8 : TaleedSize.ProductListRow.padding)
        }
    }

    @ViewBuilder
    private var favorite: some View {
        if style == .dense {
            FavoriteCircleButton(isSaved: product.isFavorite, diameter: 28, showsBackground: false, action: onFavorite)
        } else {
            FavoriteCircleButton(isSaved: product.isFavorite, action: onFavorite)
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
            .foregroundStyle(TaleedColor.textSecondary)
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

/// Seller card (design-system §3.4): identity, three stats and "View profile".
struct SellerCard: View {
    struct Stat: Identifiable {
        let value: String
        let label: String
        var id: String { label }
    }

    let name: String
    let reputation: String
    var initials: String?
    var imageURL: URL?
    var isVerified = false
    var verifiedLabel: String?
    var stats: [Stat] = []
    let viewProfileTitle: String
    let onViewProfile: () -> Void

    private static let nameStyle = TaleedTextStyle(size: 18, weight: .regular, lineHeight: nil, letterSpacing: 0, relativeTo: .body)
    private static let reputationStyle = TaleedTextStyle(size: 13, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                         relativeTo: .footnote)
    private static let statValueStyle = TaleedTextStyle(size: 15, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                        relativeTo: .subheadline)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                TaleedAvatar(initials: initials ?? TaleedAvatar.initials(from: name), size: 56, imageURL: imageURL,
                             isVerified: isVerified)
                VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                    Text(verbatim: name.isolatedByContent)
                        .taleedFont(Self.nameStyle)
                        .foregroundStyle(TaleedColor.textPrimary)
                    Text(reputation)
                        .taleedFont(Self.reputationStyle)
                        .foregroundStyle(TaleedColor.textBody)
                    if isVerified, let verifiedLabel {
                        TaleedBadge(title: verifiedLabel, tone: .success, icon: .shieldCheck)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if !stats.isEmpty {
                HStack(alignment: .top, spacing: TaleedSpacing.s8) {
                    ForEach(stats) { stat in
                        VStack(spacing: TaleedSpacing.s4) {
                            Text(stat.value)
                                .taleedFont(Self.statValueStyle)
                                .foregroundStyle(TaleedColor.textPrimary)
                            Text(stat.label)
                                .taleedFont(TaleedFont.meta)
                                .foregroundStyle(TaleedColor.textSecondary)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(TaleedSpacing.s16)
                .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
            }
            Button(viewProfileTitle, action: onViewProfile)
                .buttonStyle(TaleedOutlineButtonStyle(height: 48, paddingX: TaleedSpacing.s24,
                                                      textStyle: TaleedOutlineButtonStyle.label15, isFullWidth: true))
        }
    }
}
