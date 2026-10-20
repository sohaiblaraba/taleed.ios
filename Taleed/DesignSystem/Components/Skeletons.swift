import SwiftUI

/// A placeholder shape that pulses at 1.2 s (static with Reduce Motion). Show at most six at once.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var color: Color = TaleedColor.skeleton
    var radius: CGFloat = TaleedRadius.full

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// Pulses its content's opacity, unless Reduce Motion is on.
private struct SkeletonPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.55 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: TaleedMotion.skeletonPulse / 2).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

/// The skeleton card of the specimen (design-system §3.6): media, label, title and price bars.
struct SkeletonCard: View {
    var mediaHeight: CGFloat = 136

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            SkeletonBlock(height: mediaHeight, radius: TaleedRadius.m)
            SkeletonBlock(width: 80, height: 14)
            SkeletonBlock(height: 16)
            SkeletonBlock(width: 110, height: 20, color: TaleedColor.surfaceSubtle)
        }
    }
}

/// A product-card-shaped skeleton for the two-column grid (Android `SkeletonProductCard`).
struct SkeletonProductCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            Rectangle()
                .fill(TaleedColor.skeleton)
                .aspectRatio(TaleedSize.productCardWidth / TaleedSize.productCardMediaHeightWithSize, contentMode: .fit)
            VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                SkeletonBlock(height: 12)
                SkeletonBlock(width: 70, height: 14, color: TaleedColor.surfaceSubtle)
                SkeletonBlock(width: 90, height: 11)
            }
            .padding([.horizontal, .bottom], TaleedSpacing.s8)
        }
        .background(TaleedColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.l, style: .continuous))
        .taleedShadow(TaleedElevation.level1)
    }
}

/// The product grid's columns: two (Figma Home: gap 8), one from accessibility text sizes on, where
/// two columns leave each card too narrow for its title, price and city.
enum ProductGridColumns {
    static func count(for dynamicTypeSize: DynamicTypeSize) -> Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

    static func columns(for dynamicTypeSize: DynamicTypeSize, alignment: Alignment = .center) -> [GridItem] {
        let count = count(for: dynamicTypeSize)
        return (0..<count).map { index in
            GridItem(.flexible(), spacing: index < count - 1 ? TaleedLayout.productGridGap : nil, alignment: alignment)
        }
    }
}

/// Loading placeholders that keep the layout: a grid of product-card skeletons, at most six
/// (Android `SkeletonProductGrid`).
struct SkeletonProductGrid: View {
    var count = 4
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(columns: ProductGridColumns.columns(for: dynamicTypeSize), spacing: TaleedLayout.productGridGap) {
            ForEach(0..<min(count, TaleedMotion.skeletonMaxPlaceholders), id: \.self) { _ in
                SkeletonProductCard()
            }
        }
        .modifier(SkeletonPulse())
        .accessibilityElement()
        .accessibilityLabel(DesignSystemStrings.string(.commonLoading, locale: locale))
    }
}

/// Loading placeholders for a results list (design-system §3.3 dense rows): media 92 × 100 and three
/// bars per row, at most six rows.
struct SkeletonProductList: View {
    var count = 4
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: TaleedSpacing.s12) {
            ForEach(0..<min(count, TaleedMotion.skeletonMaxPlaceholders), id: \.self) { _ in
                HStack(alignment: .top, spacing: TaleedSpacing.s12) {
                    SkeletonBlock(width: 92, height: 100, radius: TaleedRadius.s)
                    VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                        SkeletonBlock(width: 90, height: 22)
                        SkeletonBlock(height: 14)
                        SkeletonBlock(width: 80, height: 16, color: TaleedColor.surfaceSubtle)
                    }
                    .padding(.top, TaleedSpacing.s4)
                }
                .padding(TaleedSpacing.s8)
                .background(TaleedColor.surfacePrimary, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
            }
        }
        .modifier(SkeletonPulse())
        .accessibilityElement()
        .accessibilityLabel(DesignSystemStrings.string(.commonLoading, locale: locale))
    }
}

/// Loading placeholder of a conversation list (the inbox): per row the 48 pt avatar circle and three
/// bars (name, item, last message), at the rows' margins and height, at most six rows.
struct SkeletonConversationList: View {
    var count = 6
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<min(count, TaleedMotion.skeletonMaxPlaceholders), id: \.self) { index in
                HStack(alignment: .center, spacing: TaleedSpacing.s12) {
                    SkeletonBlock(width: 48, height: 48)
                        .padding(.trailing, 4)
                    VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                        SkeletonBlock(width: index.isMultiple(of: 2) ? 120 : 96, height: 14)
                        SkeletonBlock(width: 150, height: 11, color: TaleedColor.surfaceSubtle)
                        SkeletonBlock(height: 12)
                    }
                }
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.vertical, TaleedSpacing.s12)
                .frame(minHeight: 72)
            }
        }
        .modifier(SkeletonPulse())
        .accessibilityElement()
        .accessibilityLabel(DesignSystemStrings.string(.commonLoading, locale: locale))
    }
}

/// Loading placeholder of a seller card header (§3.4, a member's profile): the avatar circle, two text
/// bars, the stats strip and the button, then the start of the product grid.
struct SkeletonSellerHeader: View {
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
            HStack(alignment: .top, spacing: 14) {
                SkeletonBlock(width: SellerCard<EmptyView, EmptyView>.avatarSize, height: SellerCard<EmptyView, EmptyView>.avatarSize)
                VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                    SkeletonBlock(width: 140, height: 18)
                    SkeletonBlock(width: 100, height: 12, color: TaleedColor.surfaceSubtle)
                }
                .padding(.top, TaleedSpacing.s4)
            }
            SkeletonBlock(height: 56, radius: TaleedRadius.m)
            SkeletonBlock(height: 44, radius: TaleedRadius.s)
            SkeletonBlock(height: 160, color: TaleedColor.surfaceSubtle, radius: TaleedRadius.m)
        }
        .modifier(SkeletonPulse())
        .accessibilityElement()
        .accessibilityLabel(DesignSystemStrings.string(.commonLoading, locale: locale))
    }
}

/// Loading placeholder of a form with photos (the edit form, §3.6 "Preserve layout · avoid jump"): the
/// uploader's label and tiles (a cover and a 2 × 2 grid), then `fields` label and 44 pt field bars, at
/// the form's margins and gaps.
struct SkeletonPhotoForm: View {
    var fields = 4
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedLayout.formFieldGap) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                SkeletonBlock(width: 110, height: 12)
                HStack(alignment: .top, spacing: TaleedSize.photoUploaderTileGap) {
                    RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous)
                        .fill(TaleedColor.skeleton)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    Grid(horizontalSpacing: TaleedSize.photoUploaderTileGap, verticalSpacing: TaleedSize.photoUploaderTileGap) {
                        ForEach(0..<2, id: \.self) { _ in
                            GridRow {
                                ForEach(0..<2, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous)
                                        .fill(TaleedColor.surfaceSubtle)
                                        .aspectRatio(1, contentMode: .fit)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<min(fields, TaleedMotion.skeletonMaxPlaceholders), id: \.self) { index in
                VStack(alignment: .leading, spacing: TaleedSize.inputLabelGap) {
                    SkeletonBlock(width: index.isMultiple(of: 2) ? 70 : 96, height: 12)
                    SkeletonBlock(height: TaleedSize.inputHeight, color: TaleedColor.surfaceGrouped, radius: TaleedRadius.m)
                }
            }
        }
        .padding(.top, TaleedLayout.formBodyPaddingTop)
        .padding(.horizontal, TaleedLayout.formBodyPaddingX)
        .modifier(SkeletonPulse())
        .accessibilityElement()
        .accessibilityLabel(DesignSystemStrings.string(.commonLoading, locale: locale))
    }
}

/// The specimen's row of three skeleton cards.
struct SkeletonCardRow: View {
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: TaleedSpacing.s16) {
            ForEach(0..<3, id: \.self) { _ in SkeletonCard() }
        }
        .modifier(SkeletonPulse())
        .accessibilityElement()
        .accessibilityLabel(DesignSystemStrings.string(.commonLoading, locale: locale))
    }
}

#Preview("Skeletons") {
    VStack(spacing: 24) {
        SkeletonCardRow()
        SkeletonProductGrid(count: 2)
    }
    .padding()
}
