#if DEBUG
import SwiftUI

/// Debug-only catalogue of every design-system component in every variant and state, grouped like
/// design-system.md. Open it from Settings → Design system.
struct DesignSystemGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var toasts = TaleedToastState()
    /// "Text 200 %": the gallery at an accessibility text size, to check large text without changing
    /// the device settings (as Android's gallery switch).
    @State private var largeText = DebugLaunchOptions.galleryLargeText

    var body: some View {
        ShellScreen {
            VStack(spacing: 0) {
                TaleedTopAppBar(title: "Design system", onBack: { dismiss() })
                Toggle(isOn: $largeText) {
                    Text(verbatim: "Text 200 %")
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(TaleedColor.textPrimary)
                }
                .toggleStyle(.taleed)
                .padding(.horizontal, TaleedLayout.screenMargin)
                .background(TaleedColor.surfacePrimary)
                .overlay(alignment: .bottom) { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
            }
        } content: {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: TaleedSpacing.s48) {
                        GalleryFoundations()
                        GalleryCoreComponents(toasts: toasts)
                        GalleryMarketplace()
                        GallerySellingAndCheckout()
                        GalleryNavigation()
                        GalleryComposed()
                    }
                    .padding(.vertical, TaleedSpacing.s24)
                    // Off, the full range leaves the device's text size alone.
                    .dynamicTypeSize(largeText ? .accessibility3 ... .accessibility3 : .xSmall ... .accessibility5)
                }
                .onAppear {
                    if let section = DebugLaunchOptions.gallerySection {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo(section, anchor: .top) }
                    }
                }
            }
            .taleedToastHost(toasts)
        }
    }
}

/// A gallery section: spec number and title, then the specimens with the screen margin.
struct GallerySection<Content: View>: View {
    let id: String
    let number: String
    let title: String
    var note: String?
    var fullBleed = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                Eyebrow(text: number)
                Text(verbatim: title)
                    .taleedFont(TaleedFont.title2)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let note {
                    Text(verbatim: note)
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textSecondary)
                }
            }
            .padding(.horizontal, TaleedLayout.screenMargin)
            content
                .padding(.horizontal, fullBleed ? 0 : TaleedLayout.screenMargin)
        }
        .id(id)
    }
}

/// A caption above a specimen ("Primary · Large", "Pressed").
struct GalleryCaption: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .taleedFont(TaleedFont.caption)
            .foregroundStyle(TaleedColor.textSecondary)
    }
}

/// Sample copy for the gallery in the app language (French, Arabic, English).
struct GalleryCopy {
    let language: AppLanguage

    init(_ locale: Locale) {
        language = AppLanguage(locale: locale)
    }

    func callAsFunction(_ french: String, _ arabic: String, _ english: String) -> String {
        switch language {
        case .fr: french
        case .ar: arabic
        case .en: english
        }
    }
}

/// Sample products for the gallery, with bundled artwork as photos.
enum GallerySamples {
    static func products(_ copy: GalleryCopy) -> [ProductSummary] {
        [
            ProductSummary(id: "1", title: copy("Veste vintage", "سترة عتيقة", "Vintage jacket"), price: 4800,
                           media: .local(Image(taleed: .loginBlueTop)), conditionCode: "NEW_WITH_TAGS",
                           location: copy("Hydra, Alger", "حيدرة، الجزائر", "Hydra, Algiers"), sizeLabel: "M",
                           isFavorite: true, favoriteCount: 1),
            ProductSummary(id: "2", title: copy("Casque audio", "سماعات رأس", "Headphones"), price: 12500,
                           media: .local(Image(taleed: .loginHeadphones)), conditionCode: "VERY_GOOD",
                           location: copy("Oran", "وهران", "Oran"), rating: 4.8, favoriteCount: 7),
            ProductSummary(id: "3", title: copy("Appareil photo rose", "كاميرا وردية", "Pink camera"), price: 6900,
                           media: .local(Image(taleed: .loginPinkCamera)), conditionCode: "SATISFACTORY",
                           location: copy("Tizi Ouzou", "تيزي وزو", "Tizi Ouzou"), rating: 5.0, isFavorite: true,
                           favoriteCount: 2),
            ProductSummary(id: "4", title: copy("Robe verte", "فستان أخضر", "Green dress"), price: 5600,
                           media: .local(Image(taleed: .loginGreenDress)), conditionCode: "NEW_WITHOUT_TAGS",
                           location: copy("Bab Ezzouar", "باب الزوار", "Bab Ezzouar"), sizeLabel: "38"),
            ProductSummary(id: "5", title: copy("Sac en cuir", "حقيبة جلدية", "Leather bag"), price: 9500,
                           media: .local(Image(taleed: .loginBrownBag)), conditionCode: "GOOD",
                           location: copy("Blida", "البليدة", "Blida"),
                           recency: copy("il y a 2 heures", "منذ ساعتين", "2 hours ago")),
            ProductSummary(id: "6", title: copy("Pull rose", "كنزة وردية", "Pink knit"), price: 1500,
                           media: .local(Image(taleed: .loginPinkShirt)), conditionCode: "UNKNOWN_CODE",
                           conditionLabel: copy("Libellé du catalogue", "تسمية الفهرس", "Catalog label"),
                           location: copy("Alger", "الجزائر", "Algiers"),
                           recency: copy("hier", "أمس", "yesterday")),
        ]
    }
}

/// Lays children out in rows that wrap, leading-aligned (mirrors in right-to-left layouts).
struct FlowRow: Layout {
    var spacing: CGFloat = TaleedSpacing.s8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var top = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var leading = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: leading, y: top + (row.height - size.height) / 2), proposal: .unspecified)
                leading += size.width + spacing
            }
            top += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
#endif
