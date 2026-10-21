import SwiftUI

// MARK: - Item Detail

/// Sticky bottom bar of Item Detail (wireframes.md #4.17, `size.bottomActionBar`): white, top corners
/// `radius.l`, `elevation.navTop`; the actions row has padding 12 / 16 / 8 / 16 and gap 8, and every
/// action grows from its own width ("Make an offer" Tertiary + "Buy now" Secondary render 180 / 220
/// on 440). `footer` takes the bottom navigation drawn without its own background. Only the top corners
/// are rounded: the fill runs under the home indicator. Without a footer, at the bottom of the screen,
/// the actions keep max(16, inset) below them, as the bottom navigation (D-15); above the tab bar, 8.
struct BottomActionBar<Actions: View, Footer: View>: View {
    @ViewBuilder let actions: Actions
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            if Footer.self == EmptyView.self {
                actionsRow
                    .bottomBarPadding(TaleedSize.bottomNavPaddingBottom, elsewhere: TaleedSize.bottomActionBarPaddingBottom)
            } else {
                actionsRow
                    .padding(.bottom, TaleedSize.bottomActionBarPaddingBottom)
                footer
            }
        }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: TaleedRadius.l, topTrailingRadius: TaleedRadius.l, style: .continuous)
                .fill(TaleedColor.surfacePrimary)
                .taleedShadow(TaleedElevation.navTop)
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
    }

    private var actionsRow: some View {
        GrowRow(spacing: TaleedSize.bottomActionBarGap) { actions }
            .padding(.top, TaleedSize.bottomActionBarPaddingTop)
            .padding(.horizontal, TaleedSize.bottomActionBarPaddingX)
    }
}

extension BottomActionBar where Footer == EmptyView {
    init(@ViewBuilder actions: () -> Actions) {
        self.actions = actions()
        self.footer = EmptyView()
    }
}

/// The Item Detail decision pair (wireframes.md Item Detail #17) in a `BottomActionBar`: Tertiary Large
/// "Make an offer" and Secondary Large "Buy now", both stretching (180 / 220 in Figma). When the two
/// labels no longer fit side by side (large text), the buttons stack. `footer` takes the bottom
/// navigation (`TaleedBottomNavigation(…, isEmbedded: true)`). Android: `ItemDetailActionBar`.
struct ItemDetailActionBar<Footer: View>: View {
    let makeOfferLabel: String
    let onMakeOffer: () -> Void
    let buyNowLabel: String
    let onBuyNow: () -> Void
    @ViewBuilder let footer: Footer

    var body: some View {
        BottomActionBar {
            ViewThatFits(in: .horizontal) {
                GrowRow(spacing: TaleedSize.bottomActionBarGap) {
                    offer
                    buy
                }
                VStack(spacing: TaleedSize.bottomActionBarGap) {
                    offer
                    buy
                }
            }
        } footer: {
            footer
        }
    }

    private var offer: some View {
        TaleedButton(title: makeOfferLabel, kind: .tertiary, size: .large, isFullWidth: true, action: onMakeOffer)
    }

    private var buy: some View {
        TaleedButton(title: buyNowLabel, kind: .secondary, size: .large, isFullWidth: true, action: onBuyNow)
    }
}

extension ItemDetailActionBar where Footer == EmptyView {
    init(makeOfferLabel: String, onMakeOffer: @escaping () -> Void, buyNowLabel: String, onBuyNow: @escaping () -> Void) {
        self.init(makeOfferLabel: makeOfferLabel, onMakeOffer: onMakeOffer, buyNowLabel: buyNowLabel, onBuyNow: onBuyNow) {
            EmptyView()
        }
    }
}

/// A row whose children share the width like CSS flex-grow 1: each gets its own width plus an equal
/// share of what is left. When they do not fit, each gets a share in proportion to its width (labels
/// then wrap). Mirrors in right-to-left layouts.
struct GrowRow: Layout {
    var spacing: CGFloat = TaleedSpacing.s8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = widths(total: proposal.width, subviews: subviews)
        let height = zip(subviews, widths)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        let width = proposal.width ?? widths.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var leading = bounds.minX
        for (subview, width) in zip(subviews, widths(total: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: leading, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            leading += width + spacing
        }
    }

    private func widths(total: CGFloat?, subviews: Subviews) -> [CGFloat] {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        guard let total, !ideal.isEmpty else { return ideal }
        let available = max(0, total - spacing * CGFloat(subviews.count - 1))
        let sum = ideal.reduce(0, +)
        if sum <= available {
            let extra = (available - sum) / CGFloat(ideal.count)
            return ideal.map { $0 + extra }
        }
        return ideal.map { sum > 0 ? available * $0 / sum : available / CGFloat(ideal.count) }
    }
}

/// Item Detail spec row (wireframes.md #4.6): label 13/400 `text/secondary`, value 13/600
/// `text/primary` (a link in `blue/600`), space-between, padding 14 / 16, at least 44 high (50 with a
/// condition tag), 1 pt `border/subtle` bottom border except on the last row.
struct SpecRow<Value: View>: View {
    let label: String
    var showsDivider = true
    var action: (() -> Void)?
    @ViewBuilder let value: Value

    var body: some View {
        let row = HStack(spacing: TaleedSpacing.s16) {
            Text(label)
                .taleedFont(PatternStyles.body13)
                .foregroundStyle(TaleedColor.textSecondary)
            Spacer(minLength: 0)
            value
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, TaleedSpacing.s16)
        .frame(minHeight: TaleedSize.touchTargetMin)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
        }
        .contentShape(Rectangle())
        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isLink)
        } else {
            row.accessibilityElement(children: .combine)
        }
    }
}

extension SpecRow where Value == SpecValueText {
    /// A text value; with an action the value is a link ("Women › Clothes").
    init(label: String, value: String, showsDivider: Bool = true, action: (() -> Void)? = nil) {
        self.label = label
        self.showsDivider = showsDivider
        self.action = action
        self.value = SpecValueText(text: value, isLink: action != nil)
    }
}

/// The value of a spec row: 13/600, `text/primary` or `blue/600` for a link.
struct SpecValueText: View {
    let text: String
    var isLink = false

    var body: some View {
        Text(verbatim: text)
            .taleedFont(PatternStyles.body13Strong)
            .foregroundStyle(isLink ? TaleedColor.blue600 : TaleedColor.textPrimary)
    }
}

/// Page count over the photos (§6.3): "1 / 4", 11/600 white on `#11182D` 80 %, padding 5 / 10.
/// Digits read left to right in every language. Android: `PageCountPill`.
struct PageCountPill: View {
    /// 1-based.
    let current: Int
    let total: Int
    @Environment(\.locale) private var locale

    var body: some View {
        Text(verbatim: "\(current) / \(total)".isolatedLeftToRight)
            .taleedFont(TaleedFont.tagLabel)
            .foregroundStyle(TaleedColor.textInverse)
            .monospacedDigit()
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(Capsule().fill(TaleedColor.scrim))
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DesignSystemStrings.format(.appA11yPhotoPosition, locale: locale, current, total))
    }
}

/// Page dots on the Item Detail photos (wireframes.md Item Detail #3): active 8 white, inactive 6
/// white at 50 %, gap 6. Android: `PageDots`.
struct PageDots: View {
    let count: Int
    /// 0-based.
    let current: Int
    var color: Color = TaleedColor.textInverse
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                let isActive = index == current
                Circle()
                    .fill(color.opacity(isActive ? 1 : 0.5))
                    .frame(width: isActive ? 8 : 6, height: isActive ? 8 : 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesignSystemStrings.format(.appA11yPhotoPosition, locale: locale, current + 1, count))
    }
}

/// Look of a `GalleryCircleButton`: white (back, share) or the favorite's `errorSoft`.
enum GalleryCircleTone: Sendable { case standard, favorite }

/// A 38 circle control over the item photos (§6.3): white with an 18 icon in `text/primary` (back,
/// `share-network`), or `errorSoft` with a `feedback/error` heart for the favorite. 44 pt hit area.
/// `selectedDescription` is read as the state ("In your favorites"). Android: `GalleryCircleButton`.
struct GalleryCircleButton: View {
    let icon: TaleedIcon
    let accessibilityLabel: String
    var tone: GalleryCircleTone = .standard
    var iconSize: CGFloat = 18
    var selectedDescription: String?
    let action: () -> Void

    var body: some View {
        let favorite = tone == .favorite
        Button(action: action) {
            TaleedIconView(icon, size: iconSize, color: favorite ? TaleedColor.feedbackError : TaleedColor.textPrimary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(favorite ? TaleedColor.errorSoft : TaleedColor.surfacePrimary))
                .contentShape(Circle())
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selectedDescription ?? "")
    }
}

/// How `ItemPhotoGallery` shows the position: page dots (Item Detail wireframe) or the "1 / 4" pill (§6.3).
enum GalleryIndicator: Sendable { case dots, count }

/// Item photos (wireframes.md Item Detail #3, §6.3): swipe between photos; each one is fitted on white
/// (portrait photos keep white sides) or cropped. Photos never mirror. The position shows as page dots
/// centred near the bottom or as the count pill at the bottom end (inset 16 / 14). `overlay` draws the
/// controls on top (condition tag and favorite, or the back / share / favorite circles). Android:
/// `ItemPhotoGallery`.
struct ItemPhotoGallery<Overlay: View>: View {
    let photos: [ProductMedia]
    var height: CGFloat = 340
    var contentMode: ContentMode = .fit
    var indicator: GalleryIndicator = .dots
    @Binding var current: Int
    @ViewBuilder let overlay: Overlay

    var body: some View {
        TabView(selection: $current) {
            ForEach(photos.indices, id: \.self) { index in
                ProductMediaView(media: photos[index], contentMode: contentMode)
                    .background(TaleedColor.surfacePrimary)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: height)
        .background(TaleedColor.surfacePrimary)
        .overlay(alignment: indicator == .dots ? .bottom : .bottomTrailing) {
            if photos.count > 1 {
                switch indicator {
                case .dots:
                    PageDots(count: photos.count, current: current).padding(.bottom, 20)
                case .count:
                    PageCountPill(current: current + 1, total: photos.count).padding(.trailing, 16).padding(.bottom, 14)
                }
            }
        }
        .overlay { overlay }
    }
}

extension ItemPhotoGallery where Overlay == EmptyView {
    init(photos: [ProductMedia], height: CGFloat = 340, contentMode: ContentMode = .fit, indicator: GalleryIndicator = .dots,
         current: Binding<Int>) {
        self.init(photos: photos, height: height, contentMode: contentMode, indicator: indicator, current: current) {
            EmptyView()
        }
    }
}
