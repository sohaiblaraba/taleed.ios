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

/// A product-card-shaped skeleton for the two-column grid.
struct ProductCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            Rectangle()
                .fill(TaleedColor.skeleton)
                .aspectRatio(TaleedSize.ProductCard.width / TaleedSize.ProductCard.mediaHeightWithSize, contentMode: .fit)
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

/// Loading placeholders that keep the layout: a grid of product-card skeletons (at most six).
struct SkeletonGrid: View {
    var count = 4
    @Environment(\.locale) private var locale

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: TaleedLayout.ProductGrid.gap),
                            GridItem(.flexible())], spacing: TaleedLayout.ProductGrid.gap) {
            ForEach(0..<min(count, TaleedMotion.skeletonMaxPlaceholders), id: \.self) { _ in
                ProductCardSkeleton()
            }
        }
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
        SkeletonGrid(count: 2)
    }
    .padding()
}
